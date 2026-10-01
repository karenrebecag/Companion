# Reference Brief: velocidad de voz por conversacion ("habla mas rapido / mas lento")

Slug: velocidad-de-voz-por-conversacion | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Decision de Karen (2026-10-01): opcion (c), tool `set_speech_speed` mas instruccion de ritmo; "conversacion" = una sesion de voz (de start() a hangUp()), la siguiente arranca en la base; al cambiar, una frase corta dicha ya a la nueva velocidad; R8 de ajuste-en-la-isla NO cubre este valor en memoria (no es un ajuste guardado) y asi queda escrito; la verificacion en vivo de gpt-realtime/marin se hace dentro del spec. Implementacion por spec supervisado por el orquestador. [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Karen (chat 2026-10-01) quiere que "habla mas rapido / mas lento" funcione como en la voz de ChatGPT: el modelo entiende el pedido y ajusta dentro de la conversacion, como cambio local de esa conversacion y no como ajuste persistente de la app.

Decisiones:
- D1. Mecanismo: (a) solo instruccion al modelo, (b) parametro por conversacion que fija una tool del modelo (por ejemplo `set_speech_speed(factor)`), o (c) ambos.
- D2. Alcance y reinicio: que cuenta como "conversacion" (sesion de voz entre start y hangUp, o el hilo de chat) y cuando vuelve la velocidad a la base.
- D3. Confirmacion: si el modelo dice "listo" o confirma de otra forma.
- D4. Relacion con la regla R8 propuesta en ajuste-en-la-isla (ninguna tool del modelo escribe un ajuste).

## 2. Estado actual

- Settings > Voz quito a proposito la velocidad en la wave 16g; queda en `VoiceProfile.settings` con su valor actual [repo:Sources/CompanionUI/Settings/SettingsVoiceSection.swift:4]
- Un test de paridad exige que `settings.voice.speed` no vuelva a la UI de ajustes [repo:Tests/CompanionUITests/SettingsParityTests.swift:41]
- La velocidad persistida se lee de UserDefaults con la clave `companion.voice.speed` [repo:Sources/CompanionUI/Settings/UserPreferences.swift:195]
- El getter de `VoiceProfile.settings` usa 1.0 si no hay valor guardado [repo:Sources/CompanionUI/Settings/UserPreferences.swift:248]
- El setter de `VoiceProfile.settings` escribe la velocidad en UserDefaults: cualquier camino que pase por ahi la vuelve persistente [repo:Sources/CompanionUI/Settings/UserPreferences.swift:264]
- `VoiceSettings.speedRange` es 0.25...1.5 y el valor se recorta al asignarlo [repo:Sources/CompanionCore/Platform/Config.swift:207]
- La voz por defecto es `.marin` y la velocidad por defecto 1.0 [repo:Sources/CompanionCore/Platform/Config.swift:229]
- El modelo realtime es `gpt-realtime` [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:24]
- El `session.update` inicial pone `speed` dentro de `audio.output` [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:94]
- Ya existe `speedUpdate`, un `session.update` minimo que solo toca `audio.output.speed` [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:166]
- El runtime arma el `session.update` con `config.voice.speed`, es decir, el valor persistido [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:212]
- La voz solo se manda en el primer update de cada conexion (`voiceSent`), la velocidad en todos [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:189]
- `resetConnection()` vacia el update pendiente y `voiceSent`; una reconexion vuelve a construir el update desde Config [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:121]
- `VoiceSession.setSpeed` manda `speedUpdate` solo si el pipeline es realtime y la sesion no esta idle ni en error; no guarda el valor [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:339]
- El protocolo documenta que la velocidad se aplica a mitad de sesion [repo:Sources/CompanionCore/Voice/VoicePorts.swift:140]
- `VoiceViewModel.setSpeed` existe pero no tiene llamadores en Sources tras quitar el control de Settings [repo:Sources/CompanionUI/Voice/VoiceViewModel.swift:65]
- La sesion de voz empieza en `start()` y termina en `hangUp()` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:352]
- El tests cubre que el update caliente lleva la velocidad nueva y no toca la voz [repo:Tests/CompanionTests/VoiceConfigBridgeTests.swift:242]
- Las tools de la sesion realtime se declaran en el mismo `session.update` (parentSpecs, delegate, approvals) [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:205]
- Pipeline clasico: la boca es ElevenLabs, `gpt-4o-mini-tts` o AVSpeech segun claves [repo:Sources/CompanionCore/Voice/VoiceStack.swift:90]
- `OpenAITTSClient` guarda la velocidad como `let` fijada al construirse, por defecto 1.1 [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:9]
- La app construye la boca OpenAI una vez, sin pasar velocidad, asi que usa 1.1 siempre [repo:Sources/CompanionApp/CompanionMainVoice.swift:57]
- El cuerpo de la peticion a `/v1/audio/speech` manda `speed` e `instructions` [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:97]
- La clave de cache de frases incluye la velocidad, asi que otra velocidad no reutiliza audio cacheado [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:41]
- La peticion a ElevenLabs no manda `voice_settings`: hoy no hay control de velocidad en ese camino [repo:Sources/CompanionServices/Voice/Mouth/ElevenLabsTTS.swift:105]
- ElevenLabs lee la voz por closure en cada peticion, patron reutilizable para una velocidad viva [repo:Sources/CompanionServices/Voice/Mouth/ElevenLabsTTS.swift:25]
- El brief ajuste-en-la-isla propone R8: ninguna tool del modelo ni del puente escribe ningun ajuste [repo:docs/research/ajuste-en-la-isla.md:7]
Contextos: app (pipeline realtime y pipeline clasico), swift test (fakes de VoicePorts y transporte), sin CLI ni previews que toquen la velocidad.

## 3. Fuentes primarias

- Realtime: `speed` es multiplo de la velocidad original, 1.0 por defecto, minimo 0.25, maximo 1.5 [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Realtime: `speed` solo se puede cambiar entre turnos del modelo, no con una respuesta en curso [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Realtime: `speed` es un ajuste de posproceso sobre el audio ya generado, y tambien se puede pedir al modelo que hable mas rapido o mas lento [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Realtime: en `session.update` solo se actualizan los campos presentes [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Realtime: la voz no se puede cambiar una vez que el modelo respondio con audio; la mayoria de las demas propiedades si [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- Realtime: el flujo de function calling termina con un item `function_call_output` y un `response.create` [doc:https://developers.openai.com/api/docs/guides/realtime-conversations@2026-10-01]
- Guia de prompting realtime: `speed` cambia la velocidad de reproduccion, no como compone el modelo; para sonar mas rapido hay que agregar instrucciones de ritmo [doc:https://developers.openai.com/api/docs/guides/realtime-models-prompting@2026-10-01]
- La misma guia muestra el ejemplo de ritmo con `gpt-realtime-1.5`, no con `gpt-realtime` [doc:https://developers.openai.com/api/docs/guides/realtime-models-prompting@2026-10-01]
- OpenAI TTS (`/v1/audio/speech`): `speed` de 0.25 a 4.0, 1.0 por defecto; `instructions` no funciona con tts-1 ni tts-1-hd [doc:https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create@2026-10-01]
- ElevenLabs stream: `voice_settings` reemplaza los ajustes guardados de la voz solo para esa peticion [doc:https://elevenlabs.io/docs/api-reference/text-to-speech/stream@2026-10-01]
- ElevenLabs: velocidad 1.0 por defecto, minimo 0.7, maximo 1.2; los extremos pueden degradar la calidad [doc:https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices@2026-10-01]

## 4. Implementaciones de referencia

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| (a) Solo instruccion | Cero codigo en realtime; el modelo recompone el ritmo, que la guia de OpenAI dice que es lo que realmente suena mas rapido | No es determinista ni medible; se pierde si el contexto se recorta o la sesion se reconecta con historial sembrado; en el pipeline clasico no hace nada, porque el cerebro escribe texto y la velocidad la pone el TTS | baja | No sola |
| (b) Parametro por conversacion via tool | Determinista, con limites y reinicio claros; sirve a los dos pipelines; reutiliza `speedUpdate` | El parametro es posproceso: acelera la reproduccion pero no el ritmo compuesto; agrega una tool y estado en memoria | media | Parte de (c) |
| (c) Ambos | La tool fija el parametro y el modelo ademas ajusta su ritmo, que es lo que la doc de OpenAI describe como complementario | Dos mecanismos que pueden sumarse de mas si no se acota el factor | media | Recomendada |

Detalle de (c), como opciones para la spec, no como decision:
- Alcance: un valor en memoria de `VoiceSession` (o del runtime), inicializado desde la base persistida al `start()` y descartado en `hangUp()`; nunca pasa por el setter de `VoiceProfile.settings`.
- Reinicio: al colgar y en sesion nueva; la reconexion dentro de la misma sesion debe reenviar el valor vivo, no el persistido.
- Rango: recortar al rango del proveedor activo (realtime 0.25-1.5, ElevenLabs 0.7-1.2, OpenAI TTS 0.25-4.0); un factor sobre la base evita depender de la base 1.1 del TTS.
- Confirmacion: la tool devuelve el valor aplicado y el modelo responde corto; como el cambio aplica entre turnos, esa respuesta ya sale a la nueva velocidad.
- R8: un valor de conversacion en memoria no es un ajuste guardado; la spec lo dice explicitamente, y Karen confirma que R8 no lo cubre.

## 6. Evidencia en contra

- Contra (c): OpenAI documenta que basta pedirlo al modelo, asi que una tool puede ser sobreingenieria en realtime [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Se resuelve porque el pipeline clasico no tiene modelo que componga audio: sin parametro, "mas lento" no tiene efecto ahi [repo:Sources/CompanionApp/CompanionMainVoice.swift:57]
- Se acepta que en realtime la sola tool no basta: el parametro es posproceso, por eso (c) mantiene tambien la instruccion de ritmo [doc:https://developers.openai.com/api/docs/guides/realtime-models-prompting@2026-10-01]

## 7. Ejemplares y anti-ejemplos

- Bien: un `session.update` que solo lleva `audio.output.speed`, sin voz ni turn detection, como el que ya existe [repo:Sources/CompanionCore/Voice/RealtimeCodec.swift:166]
- Anti-ejemplo: aplicar la velocidad de la conversacion escribiendo `VoiceProfile.settings`, que la persiste en UserDefaults [repo:Sources/CompanionUI/Settings/UserPreferences.swift:264]

## 8. Trampas

- Mandar `speedUpdate` con una respuesta en curso no la cambia: aplica solo entre turnos [doc:https://developers.openai.com/api/reference/resources/realtime/client-events@2026-10-01]
- Una reconexion reconstruye el update con `config.voice.speed` y borraria la velocidad de la conversacion [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:212]
- `setSpeed` hoy no hace nada en el pipeline clasico ni en idle: no sirve tal cual para la tool [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:342]
- La boca OpenAI fija la velocidad al construirse: hace falta leerla por peticion, como la voz de ElevenLabs [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:13]
- Cada velocidad distinta crea otra clave de cache de frases, asi que los avisos precalentados no se reutilizan a otra velocidad [repo:Sources/CompanionServices/Voice/Mouth/OpenAITTS.swift:41]
- ElevenLabs rechaza o degrada fuera de 0.7-1.2: un factor pensado para realtime (hasta 1.5) hay que recortarlo [doc:https://elevenlabs.io/docs/overview/capabilities/text-to-speech/best-practices@2026-10-01]
- Contexto swift test: los fakes registran `setSpeed` pero no simulan el servidor, asi que un test verde no prueba que OpenAI acepte el cambio [repo:Tests/CompanionCoreTestSupport/VoicePortFakes.swift:97]

## 9. Incertidumbre

- ASSUMPTION: ChatGPT Advanced Voice ajusta la velocidad solo siguiendo la instruccion, por conversacion; help.openai.com dio 403 y no hay pagina oficial leida en esta corrida. prueba: leer la FAQ de voz de help.openai.com desde un navegador y citar la frase exacta.
- ASSUMPTION: `gpt-realtime` con la voz `marin` acepta `audio.output.speed` a mitad de sesion; la referencia no restringe por modelo ni voz, pero solo se verifico con fakes. prueba: sesion real, mandar `speedUpdate(1.3)` entre turnos y comprobar que no llega un evento `error` y que la duracion del audio baja.
- ASSUMPTION: `gpt-realtime` sigue instrucciones de ritmo como el ejemplo de `gpt-realtime-1.5` de la guia. prueba: tres pedidos "habla mas rapido" en una sesion real y medir palabras por segundo antes y despues.
- ASSUMPTION: el `speed` de realtime no cambia el transcript, porque es posproceso del audio. prueba: comparar `response.output_audio_transcript.done` con y sin speed 1.4 para el mismo prompt.
- ASSUMPTION: la boca AVSpeech (fallback sin claves) necesita su propio mapeo de velocidad; no se leyo documentacion de Apple en esta corrida. prueba: leer la referencia de AVSpeechUtterance.rate y probar un factor 1.2.
- [NEEDS CLARIFICATION: "conversacion" es la sesion de voz entre start y hangUp, o el hilo de chat que sobrevive a varios holds?]
- [NEEDS CLARIFICATION: confirmas que R8 de ajuste-en-la-isla no cubre un valor en memoria de la conversacion que la tool fija y que nunca se guarda?]
- [NEEDS CLARIFICATION: tras el cambio, el modelo confirma con una frase corta ("asi?") o solo sigue hablando a la nueva velocidad?]

## 10. Checklist de estandar

- [ ] Pedir "mas rapido" o "mas lento" cambia la velocidad en la conversacion activa en ambos pipelines (realtime y clasico).
- [ ] El cambio no escribe `companion.voice.speed` ni ninguna clave de UserDefaults; un test lo comprueba leyendo la clave antes y despues.
- [ ] Al colgar, la siguiente sesion arranca con la velocidad base persistida.
- [ ] Una reconexion dentro de la misma sesion conserva la velocidad de la conversacion.
- [ ] El factor se recorta al rango del proveedor activo: 0.25-1.5 realtime, 0.7-1.2 ElevenLabs, 0.25-4.0 OpenAI TTS.
- [ ] El update de velocidad en realtime solo lleva `audio.output.speed` y se manda entre turnos, nunca con una respuesta en curso.
- [ ] Settings sigue sin control de velocidad (SettingsParityTests intacto).
- [ ] La spec declara explicitamente que el valor de conversacion no es un ajuste guardado respecto de R8.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Realtime client events (session.update, audio.output.speed) | OpenAI | 2026-10-01 | 2026-10-01 | high |
| 2 | Realtime conversations guide | OpenAI | 2026-10-01 | 2026-10-01 | high |
| 3 | Realtime models prompting guide | OpenAI | 2026-10-01 | 2026-10-01 | high |
| 4 | Create speech (audio/speech) | OpenAI | 2026-10-01 | 2026-10-01 | high |
| 5 | Text to speech stream (voice_settings) | ElevenLabs | 2026-10-01 | 2026-10-01 | high |
| 6 | Text to speech, speed setting | ElevenLabs | 2026-10-01 | 2026-10-01 | high |
