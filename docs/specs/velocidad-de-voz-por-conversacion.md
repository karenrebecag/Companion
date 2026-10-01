# Velocidad de voz por conversacion ("habla mas rapido / mas lento")

**Estado: APROBADO** (Karen, 2026-10-01; Q1 = A).
Research: `docs/research/velocidad-de-voz-por-conversacion.md` (APROBADO 2026-10-01, opcion c). Ese brief va en la rama de cada PR, porque el research-gate lo exige.

## 1. Objetivo

Si la usuaria dice "habla mas rapido", "mas lento" o "normal", el modelo llama a `set_speech_speed` y ajusta tambien su ritmo. A partir de ahi la voz suena a la velocidad nueva y dice una frase corta ya a esa velocidad. El valor vive en memoria durante una sesion de voz, de `start()` a `hangUp()`, y la sesion siguiente vuelve a la base.

**R8 queda fuera, por escrito.** R8 (`ajuste-en-la-isla.md:7`) dice que ninguna tool del modelo escribe un ajuste. El valor de esta spec no es un ajuste guardado: no se persiste, no aparece en Ajustes y muere con la sesion. Karen decidio el 2026-10-01 que R8 no lo cubre. Para que no se pueda persistir por accidente:
- nunca se pasa por el setter de `VoiceProfile.settings` (`UserPreferences.swift:264`), que escribe `companion.voice.speed` (`UserPreferences.swift:195`);
- las capas lo garantizan ademas en compilacion: Services no puede importar UI, y `VoiceProfile` vive en UI.

### Criterios de aceptacion

Cada criterio tiene su test o su evidencia.

- **A1. Clasico, bocas TTS.** Despues de `set_speech_speed(factor: 1.3)`:
  - las peticiones a OpenAI TTS llevan `speed` = clamp(1.1 x 1.3) = 1.43;
  - las de ElevenLabs llevan `voice_settings.speed` = clamp(1.0 x 1.3) = 1.2.
- **A2. Clasico, frase de confirmacion.** Tras el cambio suena exactamente una frase fija y corta, del catalogo de Core, y no hay una segunda ronda de chat.
- **A3. Realtime, momento del envio.**
  - Mientras hay una respuesta activa no sale ningun `session.update` de velocidad.
  - Despues de `response.done`, el update que solo lleva `audio.output.speed` (`RealtimeCodec.swift:166`) sale antes del siguiente `response.create`.
  - Ese update no lleva `voice` ni `turn_detection`.
- **A4. Reconexion (regresion).** El `session.update` de la conexion nueva lleva la velocidad viva, no `config.voice.speed` (`RealtimeRuntime.swift:212`).
- **A5. Reinicio.**
  - Tras `hangUp()`, el siguiente `start()` abre con la base.
  - Las bocas vuelven a 1.1 y ElevenLabs deja de mandar `voice_settings`.
  - `start()` tambien reinicia.
- **A6. Nunca persiste.**
  - `companion.voice.speed` en UserDefaults tiene el mismo valor antes y despues de un ciclo completo tool -> hangUp.
  - Los archivos nuevos no mencionan `UserDefaults` ni `VoiceProfile`.
- **A7. Recorte por proveedor:**
  - Realtime: 0.25-1.5.
  - OpenAI TTS: 0.25-4.0.
  - ElevenLabs: 0.7-1.2.
- **A8. Disponibilidad de la tool.** Se ofrece en los dos pipelines, aunque no haya especialista. El nombre en el cable es `set_speech_speed` en es y en en.
- **A9. Clave de cache de frases.** Con factor 1 es identica a la de hoy, y con factor distinto de 1 cambia.
- **A10. Ajustes sin cambios.** Ajustes sigue sin control de velocidad: `SettingsParityTests` en verde y ningun archivo de `CompanionUI` tocado.
- **A11. Evidencia en vivo.** Existe el archivo de evidencia de la tarea 0, con P1-P3 en PASS, antes de mergear el PR-5.
- **A11b. Formato en el cable (hallazgo de la tarea 0, corrida 1, 2026-10-01).**
  - `encodeJSON` usa `JSONSerialization` (`ToolSpec.swift:211-213`), que escribe 0.8 como `0.80000000000000004` y 1.6 como `1.6000000000000001`. El servidor realtime rechaza el `session.update` entero con `decimal_max_decimal_places_exceeded` (mas de 16 decimales). Evidencia: `docs/research/evidence/realtime-speed-marin-2026-10-01-run1-float.txt`.
  - Toda velocidad que sale al cable (realtime, OpenAI TTS, ElevenLabs) se redondea a 2 decimales y se serializa como `Decimal`, que sale como literal corto (`0.8`, `1.43`). Un solo helper en Core: `ConversationSpeed.wire(_ speed: Double) -> Decimal`.
  - Tests: el JSON de `speedUpdate(0.8)`, de `sessionUpdate` con 0.8 y de los cuerpos de las dos bocas contiene `"speed":0.8` literal; `1.1 x 1.3` sale `1.43`.
  - **Bug latente de hoy:** `prepareSessionUpdate` manda `config.voice.speed` con `JSONSerialization` (`RealtimeRuntime.swift:212`). Con una velocidad guardada como 0.8, el `session.update` completo se rechaza y la sesion arranca sin instrucciones ni tools. Hoy no se alcanza: el valor guardado de Karen es 1 y Ajustes ya no expone la velocidad. Lo cierra el PR-5; el helper entra en el PR-3.
- **A12. Prueba en vivo de Karen** (app release):
  - con manos libres, "habla mas rapido" acelera y suena una frase;
  - con FN, "mas lento" frena;
  - despues de colgar y volver a abrir, la velocidad es la normal.
- **Gates:**
  - `scripts/gates.sh` en verde en cada PR;
  - `swift test --sanitize=thread --filter SpeechSpeed` sin avisos;
  - code-reviewer, security-reviewer y qa-reviewer.

## 2. Estado actual (verificado)

**Realtime**
- La sesion realtime solo la abre `start()`, en modo manos libres. El hold siempre arranca clasico: `.holdPressed(preferRealtime: false)` en `VoiceSession+Hold.swift:104`.
- `start()` esta en `VoiceSession.swift:352` y `hangUp()` en `VoiceSession.swift:361`.
- `VoiceSession.setSpeed` (`VoiceSession.swift:339`) solo actua en realtime y no guarda el valor. No tiene llamadores de UI.
- `prepareSessionUpdate` (`RealtimeRuntime.swift:185`) usa `speed: config.voice.speed` en la linea 212.
- La reconexion vuelve a llamar a `prepareSessionUpdate(config: configProvider.current)` (`VoiceSession+Pumps.swift:206-209`), asi que hoy borra cualquier velocidad viva.
- La base persistida sale de `VoiceSettings`:
  - rango 0.25...1.5 (`Config.swift:207`);
  - valores por defecto `.marin` y 1.0 (`Config.swift:229-230`).
- El servidor admite una sola respuesta a la vez y todo pasa por `requestResponse` (`RealtimeRuntime.swift:170`). Hay tres envios de `response.create`: en las lineas 172 y 179, y en la 371 dentro de `.responseDone`.

**Clasico**
- Las tools se arman en cada turno (`ClassicRuntime.swift:307-312`). `delegate`, `stop_job` y `resolve_approval` solo entran con `onDelegate`.
- `handleJobTool` (`ClassicRuntime.swift:537`) maneja tools que no abren otra ronda y puede dejar una frase pendiente en `mouth.owedLines` (`ClassicRuntime+Mouth.swift:111`).

**Bocas TTS**
- `OpenAITTSClient` fija `speed` como `let`, con 1.1 por defecto (`OpenAITTS.swift:9,13`). Su clave de cache incluye esa velocidad (`OpenAITTS.swift:41-43`) y el cuerpo la manda (`OpenAITTS.swift:97`).
- ElevenLabs no manda `voice_settings` (`ElevenLabsTTS.swift:105-109`). Ya lee la voz con un closure en cada peticion (`ElevenLabsTTS.swift:25`), que es el patron que se reusa aqui.
- La app construye las bocas una sola vez (`CompanionMainVoice.swift:57-63`) y despues la `VoiceSession` (`CompanionMainVoice.swift:112`).

**Patrones que se reusan**
- Estado compartido bajo lock en una `final class @unchecked Sendable` (`InstalledAppsCache.swift:7,14`).
- `ToolSpec` (`ToolSpec.swift:15`): nombre de cable fijo y descripcion en el idioma de la respuesta (linea 39).

## 3. Archivos y API por capa

### Core (puro)

`Sources/CompanionCore/Voice/ConversationSpeed.swift` (nuevo):
- `SpeechSpeedProvider`: `realtime`, `openAITTS` y `elevenLabs`, cada uno con su rango.
- `ConversationSpeed`:
  - factor relativo a la base de cada boca, 1.0 = normal;
  - rango del factor 0.25...4.0, cuantizado a pasos de 0.05 para acotar las variantes de cache;
  - `speed(for:base:)`, `isLimited(for:base:)`;
  - `factor(fromArguments:)`, que solo acepta un numero JSON finito y mayor que 0.
- `SpeechSpeedCopy`:
  - `toolOutput(applied:limited:)`;
  - `pacingNote`, que devuelve nil en la base;
  - `confirmation`: "Listo, ¿asi?" / "Done. Like this?".

`Sources/CompanionCore/Tools/ToolSpec+SpeechSpeed.swift` (nuevo):
- `ToolSpec.setSpeechSpeed(language, current:)`, con un solo parametro requerido, `factor` (number).
- La descripcion dice:
  - llamarla SOLO cuando la usuaria pide mas rapido, mas lento o normal;
  - el factor es absoluto respecto de la normal, y se indica el valor actual;
  - no decir nada antes de llamarla.

### Services

`Sources/CompanionServices/Voice/Session/ConversationSpeedBox.swift` (nuevo):
- `final class @unchecked Sendable` con lock: `current`, `factor`, `set(factor:)` y `reset()`.
- Las bocas leen el factor sincronicamente en cada peticion, sin `await`. Por eso es una caja y no estado de un actor.

`VoiceSession.swift`:
- `init` recibe `speech: ConversationSpeedBox` con default, y se la pasa a `classic.speech` (PR-4) y a `realtime.speech` (PR-5).
- `start()` y `hangUp()` llaman a `speech.reset()`.
- `recover` (realtime -> clasico dentro de la misma sesion) no la reinicia.

`ClassicRuntime.swift`:
- Nueva propiedad `speech`. En `submit` agrega `.setSpeechSpeed` siempre, fuera del `if onDelegate`.
- `handleJobTool` gana el caso `set_speech_speed`:
  - si el argumento sirve, hace `set(factor:)` y agrega la confirmacion a `owedLines`;
  - si no, registra en el log y no cambia nada.
- Lleva un `HACK:` sobre el fallback de AVSpeech, que ignora la velocidad. Disparador: que un usuario sin claves la pida.

`RealtimeRuntime.swift`:
- Nuevas propiedades `speech`, `speedOwed` y `baseSpeed`.
- `prepareSessionUpdate`:
  - toma la velocidad viva (arreglo de la linea 212);
  - declara la tool siempre;
  - agrega `pacingNote` a las instrucciones.
- En `.functionCall`, el caso `set_speech_speed`:
  - parsea el argumento; si no sirve, responde con un `functionOutput` de argumento invalido y no cambia nada;
  - si sirve: `speech.set`, `speedOwed = true`, `functionOutput(toolOutput)` y `requestResponse()`.
- Un solo `createResponse()` reemplaza los tres envios: si `speedOwed`, manda primero `speedUpdate` y despues `response.create`. Asi el update nunca sale con una respuesta en curso.
- `resetConnection()` limpia `speedOwed`, porque el update completo de la conexion nueva ya lleva el valor.

`OpenAITTS.swift` y `ElevenLabsTTS.swift`:
- `init` recibe `factor: @escaping @Sendable () -> Double = { 1.0 }`.
- Ese factor entra en el cuerpo y en `cacheVariant`.
- En la base, el cuerpo y la clave quedan identicos a los de hoy.

### UI

Sin cambios.

### App

`CompanionMainVoice.swift`:
- crea un solo `ConversationSpeedBox`;
- pasa `factor: { speech.factor }` a las dos bocas;
- pasa `speech:` a `VoiceSession`.

## 4. Tarea 0: verificacion en vivo (va primero y es gate del PR-5)

`scripts/probe-realtime-speed.swift` es un script suelto con Foundation (`URLSessionWebSocketTask`). No toca `Package.swift` ni agrega dependencias. Lo corre Karen, o el orquestador con su permiso. La clave entra solo por `OPENAI_API_KEY` y nunca se imprime. La salida va a `docs/research/evidence/realtime-speed-marin-<fecha>.txt`.

Pasos:
1. Conectar a `gpt-realtime` con voz `marin`, speed 1.0 y `turn_detection: null`.
2. Turno de texto fijo. Medir los segundos de audio y guardar el transcript.
3. Entre turnos, mandar `speedUpdate(1.4)` y registrar `session.updated` o el error literal.
4. Repetir el paso 2.
5. Ruta de tool: `set_speech_speed`, luego `function_call_output`, `response.done`, `speedUpdate(0.8)` y `response.create`.
6. Informativos, no bloquean:
   - update a media respuesta;
   - update despues de un `response.cancel`;
   - speed 1.6.

Criterios de PASS:
- **P1:** sin error tras el update, y `session.updated` refleja 1.4.
- **P2:** en el paso 4, los segundos por caracter son ≤ 0.85 x los del paso 2.
- **P3:** el paso 5 termina sin error y produce audio.

Si falla:
- **P1 o P2:** el PR-5 vuelve a Karen con la evidencia y una variante de "solo instruccion" en realtime. Los PR-1 a PR-4 siguen.
- **Solo P3:** se prueba esperar `session.updated` antes del `response.create`.

### Resultado (2026-10-01, corridas de Karen)

- **Corrida 1** (`realtime-speed-marin-2026-10-01-run1-float.txt`): P1 y P2 PASS, P3 FAIL. El servidor rechazo `speed` 0.8 por `decimal_max_decimal_places_exceeded`: `JSONSerialization` lo escribe como `0.80000000000000004`. De ahi sale el criterio A11b.
- **Corrida 2** (`realtime-speed-marin-2026-10-01-run2-decimal.txt`), con la velocidad como `Decimal` de 2 decimales: **P1, P2 y P3 PASS**. A 1.4 el audio dura 0.706 veces lo de 1.0 por caracter; a 0.8 dura mas que a 1.0 (0.0694 contra 0.0632 s/caracter).
- **Informativos:**
  - un update a media respuesta (6a) se acepta, pero no cambia la respuesta en curso: sale a la velocidad anterior. Confirma que la velocidad se aplica entre respuestas y que esperar a `response.done` (A3) es lo correcto;
  - un update despues de `response.cancel` (6b) se acepta;
  - 1.6 se rechaza (`decimal_above_max_value`, maximo 1.5), igual que el rango de A7.
- Gate del PR-5: **cumplido**.

## 5. Plan TDD (primero RED)

Rutas despues de #71: el target `CompanionTests` ya no existe.

**Core:** `Tests/CompanionCoreTests/ConversationSpeedTests.swift`
- `conversationSpeedStartsAtBaseFactorOne`
- `realtimeClampsTo025Through15`
- `openAITTSClampsTo025Through40`
- `elevenLabsClampsTo07Through12`
- `factorQuantizesToFiveHundredths`
- `parseFactorRejectsBoolStringMissingNaNAndNonPositive`
- `setSpeechSpeedHasStableWireNameInBothLanguages`
- `setSpeechSpeedDescriptionCarriesCurrentFactor`
- `setSpeechSpeedEncodesStrictForChat`
- `toolOutputNamesAppliedValueLimitAndOneShortPhrase`
- `pacingNoteIsNilAtBase`

**Services, bocas:** `Tests/CompanionServicesTests/MouthSpeechSpeedTests.swift`
- `openAIRequestCarriesBaseTimesFactor`
- `openAICacheKeyUnchangedAtBaseAndChangesOtherwise`
- `elevenLabsOmitsVoiceSettingsAtBase`
- `elevenLabsSendsClampedVoiceSettingsSpeed`
- `elevenLabsCacheKeyUnchangedAtBaseAndChangesOtherwise`

**Services, clasico:** `Tests/CompanionServicesTests/ClassicSpeechSpeedTests.swift`, con `makeVoiceHarness` de `Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift`.
- `classicOffersSetSpeechSpeedWithoutJobs`
- `classicSpeedToolSetsFactorAndSaysOneConfirmation`
- `classicInvalidFactorChangesNothing`
- `hangUpResetsConversationSpeed`
- `startResetsConversationSpeed`
- `holdsKeepSpeedUntilHangUp` (depende de Q1)
- `classicSpeedToolNeverTouchesUserDefaults`
- `speedSourcesNeverMentionUserDefaultsOrVoiceProfile`

**Realtime:** `Tests/CompanionIntegrationTests/RealtimeSpeechSpeedTests.swift`, con el patron de `VoiceReconnectTests`.
- `realtimeDeclaresSetSpeechSpeedWithoutJobs`
- `speedToolDefersUpdateUntilResponseDone`
- `speedToolWithNoActiveResponseSendsUpdateBeforeCreate`
- `preemptingTurnFlushesOwedSpeedBeforeCreate`
- `speedToolClampsRealtimeAndReportsLimit`
- `reconnectResendsLiveConversationSpeed` (regresion de la linea 212)
- `reconnectKeepsPacingNoteInInstructions`
- `hangUpThenStartOpensAtBaseSpeed`
- `realtimeSpeedToolNeverTouchesUserDefaults`

**Deben seguir en verde sin editarse:**
- `VoiceConfigBridgeTests` y `VoiceReconnectTests` (Integration);
- `ElevenLabsTTSTests` y `MouthStyleAndMarksTests` (Services);
- `SettingsParityTests` (UI).

## 6. Restricciones y PRs (en orden)

Reglas para todos los PR:
- Comentarios solo con el POR QUE.
- Sin dependencias nuevas.
- Sin tocar configs raiz.
- `CHANGELOG.md` en espanol y con fecha, en cada PR.
- El brief APROBADO va en cada rama.
- Ediciones solo con Edit/Write.
- Cada PR se puede mergear solo.

| PR | Archivos | Depende de |
|---|---|---|
| PR-1 Prueba en vivo | probe, evidencia, esta spec (resultado), CHANGELOG (4) | nada |
| PR-2 Core | `ConversationSpeed.swift`, `ToolSpec+SpeechSpeed.swift`, `ConversationSpeedBox.swift` (sin cablear), tests, CHANGELOG (5) | nada |
| PR-3 Bocas | `OpenAITTS.swift`, `ElevenLabsTTS.swift`, tests, CHANGELOG (4) | PR-2 |
| PR-4 Clasico y app | `ClassicRuntime.swift`, `VoiceSession.swift`, `CompanionMainVoice.swift`, tests, CHANGELOG (5) | PR-2, PR-3 |
| PR-5 Realtime | `RealtimeRuntime.swift`, `VoiceSession.swift` (una linea), tests, CHANGELOG (4) | PR-1 en PASS, PR-4 |

Fuera de alcance:
- AVSpeech;
- el chat escrito fuera de la sesion de voz;
- volver a poner un control de velocidad en Ajustes;
- reconectar `VoiceSession.setSpeed`.

## 7. Riesgos y preguntas abiertas

**Q1 (bloquea la firma).** El FN siempre es clasico (`VoiceSession+Hold.swift:104`) y no pasa por `start()` ni por `hangUp()`.
- **Default de esta spec:** la velocidad sobrevive entre holds hasta `hangUp()`, `start()` o cerrar la app.
- **Alternativa:** cada hold que arranca desde reposo vuelve a la base. Cuesta una linea en `beginHold` y un test.

**Riesgos y mitigaciones:**
- **El servidor rechaza o ignora la velocidad.** Lo cubren la tarea 0 y su gate.
- **`speed` solo cambia la reproduccion del audio ya generado.** La nota de ritmo va en la salida de la tool y en las instrucciones.
- **Doble frase:** el modelo dice algo antes de llamar a la tool. La descripcion de la tool lo prohibe; si aparece en vivo, se filtra con `Acknowledgement.isNeeded`.
- **ElevenLabs `voice_settings` podria cambiar el timbre.** Solo se manda fuera de la base, y Karen lo escucha en A12.
- **Carrera en la clave de cache:** un cambio cae entre la clave y la peticion. Se acepta con `HACK:`; disparador: que aparezca en vivo, y entonces se lee el factor una sola vez por frase.
- **El router N1, apagado por defecto, podria interceptar "habla mas rapido".** Con el router encendido, se verifica `passThrough` en A12.
- **Sin verificar:** que la velocidad no altere el transcript. Lo registra el probe, pero no bloquea.
