# Roadmap

## Estado

| Wave | Nombre | Estado | Hito |
|---|---|---|---|
| 0 | Scaffold | CERRADA (2026-08-20) | Paquete compila, gates verdes |
| 1 | Core de dominio | CERRADA (2026-08-20) | Logica pura 100% testeada |
| 2 | Chat vertical | CERRADA (2026-08-20) | **App usable solo con una API key** |
| 3 | Voz | APROBADO / EN CURSO | **Conversacion por voz con barge-in** |
| 4 | Delegacion | CERRADA (4a y 4b) | **Especialista integrado sin instalar nada** |
| 5 | Producto | CERRADA (5a-5e) | **Distribuible open source** |
| 6 | Paridad y craft | 6a CERRADA; 6c CERRADA; 6b EN CURSO | **Iguala o supera al prototipo en uso diario** |
| 7 | Delegacion de verdad | CERRADA (7a y 7b, 2026-08-21) | **"Crea un archivo" por voz termina en archivo real** |
| 8 | Cabos sueltos | CERRADA (2026-08-22) | **Nada probado se queda sin cablear; ningun doc miente** |
| 9 | Que la use alguien que no seas tu | EN CURSO | **Un desconocido instala, pega su key y conversa** |
| 9b | Base local, nube opcional | APROBADO / EN CURSO | **Un desconocido conversa sin pegar ninguna key** |
| 9c | Procesos y rendimiento | APROBADO / EN CURSO | **Nada que Companion lanza sobrevive a Companion** |
| 9d | Lo que se ve y lo que se recuerda | CERRADA (2026-08-24) | **El modelo deja de creerse autor del informe del especialista** |
| 9g | Ciclo de vida del encargo | CERRADA (2026-08-24) | **Puedes parar lo que no pediste** |
| 9h | Los limites: alcance, ritmo y memoria | CERRADA (2026-08-24); default REVOCADO en 9i | **El especialista deja de tener tu home por defecto** |
| 9i | Voz hibrida: el oido transcribe, el modelo habla | ENTREGADA (2026-08-25) | **"Crea un archivo" por voz termina en archivo real, en el escritorio real** |
| 10 | El loop usuario → app → sistema (mapa `AI_Research/AIResearch/COMPANION-MAP.md`) | 10b ENTREGADA (2026-09-05); 10a ENTREGADA (2026-09-05, con permisos de spec 28); 10c ENTREGADA (2026-09-05, con la puerta de `open_url`) | **"Abre Safari" por voz abre Safari, sin hoja y sin encargo; nada de lo que el modelo pide se pierde** |
| 11 | Skills y knowledge (Agent Skills, spec 12/13 del corpus) | 11a ENTREGADA (2026-09-06, `docs/specs/wave-11a-skills.md`); 11b y 11c pendientes | **"Enséñale a Companion cómo…" queda en un archivo que la próxima sesión lee sola** |
| 12 | El HUD (spec de producto `~/Desktop/relay-hud-spec/`, fuera del repo) | 12a ENTREGADA (2026-09-06, `docs/specs/wave-12a-reductor-de-sesion.md`); 12b ENTREGADA (2026-09-06, `docs/specs/wave-12b-hold-fn-island.md`, revisiones cerradas); 12c ENTREGADA (2026-09-06, `docs/specs/wave-12c-parciales-metricas-precalentar.md`); 12d ENTREGADA (2026-09-06, `docs/specs/wave-12d-contratos-del-hud.md`: el libro de puertas `conformance/hud-gates.json`, revisiones cerradas); 12e ENTREGADA (`docs/specs/wave-12e-dictado-en-el-campo.md`: dictar en el campo enfocado de otra app con la misma tecla, revisiones cerradas; §11 recoge lo que enseñó la prueba en vivo). Queda de la spec de producto la acción por Accesibilidad. Pendiente de Karen: conceder Monitoreo de entrada (nunca se pidió: sin fila en TCC) y encender Accesibilidad (denegada), y decidir si el modo por defecto sigue siendo Automático o pasa a Hablar con Companion. D8 (socket caliente en boot) se decide con las líneas `voice timeline:` que ahora deja cada hold. Deuda cerrada en 12e para el oído (`ear:` ya solo cuenta caracteres); sigue abierta para `VoiceAudit.logTurn()`, que escribe la transcripción literal del turno hablado (no del dictado) en el log | **Mantener FN y hablar, sin abrir la ventana** |
| DM0 | Línea base y arnés del modelo de decisión (`docs/specs/wave-dm0-linea-base-decision.md`; discovery en `docs/research/decision-model/`) | EN CURSO (2026-09-22): `TurnTimeline` mide `commit→tool` y `tool→done`; `ordenes.jsonl` 171 filas (4 reales) con test; gates verdes. Pendiente de Karen: 30 holds → `baseline-2026-09.md`, reclasificar reales hasta ≥60 % | **Saber cuánto tarda hoy "abre Safari" y contra qué órdenes se medirá el modelo de decisión** |
| DM1 | Router: decidir barato, escalar poco, aprobar solo lo irreversible (`docs/specs/wave-dm1-router.md`) | EN CURSO (2026-09-22): **DM1a hecha** — Core puro (`Decision`, `Candidates`, `Plan`, `Arbitration`), 16 tests dm1, reviews APPROVE; DM1b (adapters) espera DM0 cerrada, DM1c (cableado) espera hold + oído | **"Abre Safari" sin tool call del modelo fuerte y sin hoja; lo irreversible confirma por voz** |

## Foco actual

### Las manos para Claude Code (Wave 17, cerrada en código 2026-09-28)

Companion presta sus manos (`look`/`click`/`type_text`/`open_app`…) a una sesión de Claude Code
por un socket Unix local + shim MCP (`companion-mcp`, repo hermano). Mismo runner, mismas hojas,
cero palabras dichas: lo sensible pide permiso; presupuesto 30 escrituras/min por proceso; la voz
de Karen pausa el puente; chip "Manos: Claude Code" y "Detener manos" en isla y menú; ajuste
*Prestar las manos a otros agentes* apagado por defecto. Una hoja por sesión (nunca se recuerda:
revisión de seguridad). Falta la prueba en vivo (`wave-17-puente-mcp.md` §7); después, 17-4 (el
especialista con el mismo shim en vez de `osascript`).

### Vista, click y UX (16a–16e cerradas, 2026-09-25)

`look`/`click`/`scroll`/`menu`/`see` sobre Accesibilidad como el helper de Incredible; el
especialista en modo `auto` sin hojas. Falta la prueba en vivo de Karen (§7 de la spec 16).
16c–16e UX/UI con paridad de Incredible CERRADA 2026-09-25 (`wave-16c-ux-como-incredible.md` §9); falta la prueba en vivo de Karen.
16g Ajustes con barra lateral, buscador, Vocabulario y Memoria CERRADA 2026-09-25 (`wave-16g-ajustes-como-incredible.md` §8). 16f notch y motion CERRADA EN CÓDIGO 2026-09-25 (`wave-16f-notch-y-motion.md` §8); falta verificación en vivo y la grabación comparada. 16h (conversación) en BORRADOR. 16i (isla útil) APROBADA; 16i-1 CERRADA EN CÓDIGO 2026-09-25 (`wave-16i-isla-util.md` §13), falta verificación en vivo; siguen 16i-2 a 16i-5. 16j (ventana como Incredible) APROBADA por dirección; 16j-1 y 16j-2 CERRADAS EN CÓDIGO 2026-09-25 (spec §10); siguen 16j-3 (tareas vivas) y 16k (Apps con Pipedream): 16k APROBADA, 16k-0 (función en repo aparte `companion-apps`) CERRADA EN CÓDIGO 2026-09-25, sin desplegar; 16k-1 (página Apps) CERRADA EN CÓDIGO 2026-09-25 (spec §8); 16k-2 (conectar/desconectar) CERRADA 2026-09-28 (spec §9: panel con acciones agrupadas, modal con poll auditado 3s×40+150s, Tus apps y desconectar con confirmación; falta E2E en vivo de Karen con la función desplegada); siguen 16k-3 (por voz) y 16k-4 (MCP propio).

### Boca y manos (15f y 15g cerradas, 2026-09-25)

15f cerrada: ElevenLabs Ana María (180–210 ms al primer byte), tubería de frases,
JSON nunca hablado (eco descartado / propuesta con sí), filtro de fugas de
razonamiento, anuncio del encargo con palabras propias, y el hallazgo crítico
de seguridad del cache de `URLSession` (claves y cuerpos en disco desde antes
de 15c) corregido. Pendiente de Karen: rotar OpenAI/Cerebras/ElevenLabs y
revocar Groq; borrar `~/Library/Caches/com.karen.companion/`.

15g (manos): `type_text`, `press_key`, `focus_window`, `read_focused` por
Accesibilidad a la app delante, sin subagente ni AppleScript; prompt "actuar,
nunca instruir"; visión que no bloquea. Cerrada tras la revisión (seguridad
BLOCK → corregido): campos de contraseña por subrol, escribir/Return atados a lo
dicho y a la app de cuando se habló, apps de comandos ampliadas, portapapeles
ocultado por gestores fuera del contexto. Falta la prueba en vivo de 15f+15g
junta (§7 de 15g y §6 de 15f). Siguiente, con OK de Karen: waves de UX.

### Oído completo y sin Groq (15d + 15e, 2026-09-24)

**Síntoma:** "sigue siendo lento de a madre, no escucha bien". Estudio de
Incredible (trazas, binario, docs): no es más rápida en números (5,1 s), pero
oye la frase entera (mic a +3 ms, cola de 300 ms) y da feedback inmediato.

**Causa:** perdíamos ~0,5 s de frase al inicio (umbral tap/hold + arranque) y
la última sílaba al soltar; Groq Whisper remoto 500–750 ms y su gpt-oss con
tope de 8k tokens/min metía backoffs de 8–24 s.

**Hecho:** mic al key-down (solo lo local y reversible; captura de pantalla,
fan-out y cortar una respuesta esperan al umbral de 250 ms), cola de 300 ms,
oído Apple `SpeechAnalyzer` on-device (spike: 54 ms p50; WhisperKit 430 ms y
pierde clips < 1 s), Groq eliminado de todo, cerebro Cerebras → gpt-4o-mini,
plataforma macOS 26, modo depuración de transcripts opt-in.

**Medido en vivo (22 holds de Karen):** `release→earFinal` p50 360 ms (con
la cola); transcripts largos y complejos completos; `release→audio` p50 1,65 s
= cola 300 + oído 60 + cerebro 570 + boca 730. **Lo que queda:** la boca
(TTS p50 730 ms, p90 1,4 s) y dos defectos de habla: el modelo pronuncia
el JSON de `delegate` cuando lo escribe como texto en vez de llamar a la
tool (4 de 22 turnos) y a veces lee su razonamiento en inglés ("We need to
answer..."). Siguiente wave: 15f (boca + nunca leer JSON ni razonamiento).
Después, las waves UX de `docs/research/ux-incredible-vs-companion.md`.

### El carril del trabajo (2026-08-24)

**Sintoma:** Karen pidio "cines cerca de Reforma" y la app contesto "no puedo
buscar en la web" — con Claude Code instalado y pagado al lado.

**Causa, en dos capas.**

1. `web_search` era un munon: devolvia siempre "not available: requires
   configured search provider API key". Y aun asi se anunciaba al modelo,
   porque `nativeToolSpecs()` publicaba `NativeTool.allCases` sin filtrar, y
   `ChatPrompt.delegateRule` prometia "Y BUSQUEDA EN INTERNET" sin condicion.
   Anunciar una tool rota es PEOR que no tenerla: **captura la intencion y
   luego se muere**, asi que el modelo reporto que no podia en vez de buscar
   otra via. `find_places`, que resolvia el caso con MapKit, nunca se intento.
2. `ExecutorProvider` corria el encargo en **lo que dijera el desplegable**, y
   su default es `.native`. El prototipo no hacia eso: `workExecutor(
   claudeInstalled:)` mandaba el trabajo a claude si estaba instalado,
   ELIGIERAS LO QUE ELIGIERAS para conversar, y lo decia en la linea de estado.

**Arreglado.**

- `availableTools` filtra: una tool sin respaldo configurado no se ofrece.
- La promesa de internet en el prompt es condicional.
- `ExecutorCapability` + `WorkRouting`: el carril de charla y el de trabajo son
  elecciones distintas, y el trabajo va al especialista detectado.
- El desvio se registra: un ruteo invisible es la app decidiendo a tus espaldas.

**Un error mio que cazo un test.** Rankee los carriles contando capacidades.
Parecia principiado y era falso: native tiene `.places` y un CLI tiene `.web`,
empatan a tres, y el empate dejaba el trabajo en el carril mas debil — el bug
exacto que el ruteo existe para arreglar. Se ranking por tipo, como el
prototipo, con el vendor fuera.

**Sobre Brave.** Se implemento `web_search` de verdad (Brave: indice propio, la
latencia mas baja de las APIs de agentes, lo que decide en un producto de voz).
Pero **no es la respuesta principal**: para un Mac con Claude Code la busqueda
ya esta pagada. Queda como ultimo recurso para la persona base de 9b, que no
tiene ningun carril con web — y por eso su clave es secundaria y su tool no se
anuncia sin ella.



### Auditoria contra documentacion (2026-08-24)

Se reviso lo que este codigo asume de APIs ajenas. Dos defectos, arreglados;
tres cosas verificadas que estaban bien, anotadas para no volver a mirarlas.

**Arreglado — `temperature` cableado.** `ChatSSEAttempt` mandaba
`"temperature": 0.7` siempre. Los modelos de razonamiento (serie o, GPT-5) no
lo ignoran: devuelven 400 con `unsupported_value`. Hoy no molestaba porque el
default es `gpt-4o`, pero **9b-3 existe para que el usuario elija el modelo**,
asi que era una bomba con fecha. Ahora el campo viaja solo si el descriptor
eligio uno Y el modelo lo acepta (`ChatParameters`, puro y probado). La
heuristica por nombre lleva `HACK:` con su gatillo: leer el cuerpo del error
del proveedor en vez de adivinar por la cadena.

**Arreglado — el llavero prometia lo que no cumplia.** `KeychainSecretStore`
ponia `kSecAttrAccessible` y `kSecAttrSynchronizable: false` bajo un
comentario que decia "sobrevive al bloqueo, no sale de esta Mac". Apple
documenta que `kSecAttrAccessible` **no es relevante en el keychain de
archivo**, que es el que `SecItem` usa en macOS por defecto — y la inspeccion
del item de Karen lo confirmo: vive en `login.keychain-db`. El atributo no
hacia nada. Se quitaron los dos atributos muertos y el comentario dice ahora lo
que de verdad pasa, con el gatillo de migrar al data-protection keychain
cuando exista la cuenta de Developer (exige Team ID).

**Verificado y correcto, para no re-auditarlo:**

- Realtime: `wss://api.openai.com/v1/realtime?model=gpt-realtime` con solo
  `Authorization` y SIN la cabecera `OpenAI-Beta: realtime=v1`. Es exactamente
  la forma GA; la cabecera era de la beta y hay que quitarla.
- `max_tokens`: deprecado a favor de `max_completion_tokens` y rechazado por la
  serie o. No lo mandamos, asi que no aplica.
- `SFSpeechRecognizer`: **no** esta deprecado. El SDK 26.5 ya trae
  `SpeechTranscriber`, pero migrar es la deuda post-v1 que ya estaba anotada,
  no un defecto.



### Hallazgos de la captura de Karen (2026-08-24)

Una captura de uso real destapo cuatro cosas. Dos ya estan arregladas con test
en rojo primero; dos quedan anotadas con su causa medida.

**Arreglado.**

1. **"No hay conexion a internet" con la red perfecta.**
   `VoiceFailureMapping` mandaba `ChatError.noProvider` a `.networkUnavailable`.
   `noProvider` es la escalera de proveedores agotada, no la red caida: mandaba
   al usuario a arreglar lo que no estaba roto. `TurnFailure.noProviders` — la
   respuesta correcta — ya existia en la enum y nadie la usaba para esto.
2. **Un fallo, dos mensajes, dos redacciones.** `VoiceSession` escribia el
   fallo al hilo con texto cableado en Services (`ClassicRuntime.status`) y
   `VoiceViewModel` lo escribia otra vez desde el catalogo. El usuario leia dos
   bugs donde habia uno. Ahora hay un solo dueno, y es el que pasa por el
   catalogo de idiomas; `ClassicRuntime.status` se fue entera. Ojo al detalle
   que casi cuesta un hueco: la ruta de RECUPERACION emite el fallo sin poner
   el estado en `.error`, asi que la condicion de la UI paso a mirar el cambio
   de fallo y no el estado.

**Anotado, con causa medida.**

3. ~~Los widgets no pueden aparecer.~~ **RETIRADO (2026-08-24): era falso.**
   `Escalation.executorRole` SI ensena la sintaxis de tarjetas al especialista
   — vive en `EscalationCopy.swift`, y el grep original miro `ChatPrompt.swift`
   y `Escalation.swift`. Las tarjetas estan cableadas de punta a punta. Que no
   salgan en una respuesta concreta es correcto cuando esa respuesta no tiene
   ni lugares ni imagenes. Queda como recordatorio de que un grep que no
   encuentra algo no prueba que no exista.
4. **Dos cadenas monolingues sobrevivientes de Wave 9.**
   `VoiceAttachmentCopy.caption` (prompt al modelo, solo espanol: un usuario en
   ingles recibe una instruccion en espanol) y `ChatViewModelJobs:125`
   ("Error en el encargo: …", copy de usuario fuera del catalogo). El gate no
   las ve porque ninguna es un `Text(...)`.

**Sin confirmar:** el resultado del especialista salio DOS veces en el hilo,
una con un espacio comido ("escritorio.Si") y otra limpia. Las dos rutas de
encargo (`runJob` y `VoiceJobBridge`) anaden el resultado una sola vez cada
una, asi que no reproduje la causa. Hace falta el log de esa sesion.



**Wave 9b arrancada (2026-08-22).** Spec APROBADO en
`docs/specs/wave-9b-base-local.md`, ADR 006 en `DECISIONS.md`. La wave nace de
medir el codigo en vez del deseo: la escalera de proveedores YA degradaba sola
sin key, y el muro real eran tres lineas de `ChatViewModel` mas un tag de
Ollama escrito a mano que ningun Mac tiene instalado.

Entregado — **9b-1 PR 1, el cable**:

- `LocalModels.swift` (Core, puro): escalones de RAM con umbrales que caen
  ENTRE configuraciones que Apple vende, y la regla de que modelo local elegir
  (excluir embeddings, respetar lo guardado, el mayor que quepa, desempate
  determinista).
- `OllamaModelScan.swift` (Services, read-only, ADR 004): lee `/api/tags` y
  distingue cuatro estados. El cuarto es el que faltaba: **binario instalado
  con el daemon apagado no es lo mismo que no tener Ollama**, y decirle
  "instalalo" a quien ya lo tiene es falso.
- `LocalCatalog`: Ollama entra al catalogo SOLO con un tag que el daemon tiene.
  Sin scan, no se ofrece.
- El orden de la escalera NO cambia en este PR: hacerlo ahora moveria a Ollama
  por delante de OpenAI para quien ya tiene key. Eso es de 9b-3, donde el
  usuario lo ve y lo decide.

Entregado — **9b-1 PR 2, el muro** (2026-08-23):

- `StartupState` en Core: `premium` / `probing` / `base([LocalPath])` / `none`.
  Cuatro estados y no un Bool, que es lo que evita que la raiz pinte el hilo y
  se lo lleve de vuelta.
- Con clave, **el sondeo ni se lanza**: el arranque premium no paga por
  preguntarle a un daemon que no le importa.
- `acceptLocalBase(_:)` abre la app sin salir a la red — el camino local jamas
  llama a `verify` contra OpenAI, que es la forma de bug que Wave 9 ya cerro en
  el guardia de forma de la clave.
- Un camino guardado se acepta solo en el siguiente arranque **solo si el
  sondeo lo vio vivo en ESE arranque**: un modelo borrado entre sesiones no
  desbloquea una app que no puede hablar.
- `changeKey()` deja de encarcelar a quien ya hablaba en local. Aviso honesto:
  esa funcion **hoy no la llama nadie en Sources** — su boton vive en el panel
  de 9b-3. Se arregla ahora porque la semantica es la correcta, pero es codigo
  probado y sin invocar hasta esa pieza.
- `ProviderPreference` (UserDefaults) y `StoredConfigProvider` dejando de pasar
  `chat: .default`: la preferencia por fin llega al router.
- Onboarding reescrito a tres caminos, con copy nuevo en los dos catalogos. El
  boton "Continuar" estaba **hardcodeado en espanol** desde Wave 9; ahora pasa
  por el catalogo.

Entregado — **9b-3, el motor** (2026-08-23), y su prerrequisito:

- `CachingSecretStore`: decorador en la raiz de composicion. El bucle de
  routing pedia la misma clave dos veces por proveedor y la voz otra vez al
  abrir sesion — de tres a cinco lecturas del llavero por mensaje, que con el
  ACL desajustado son otros tantos dialogos de contrasena. Ahora es una por
  clave. Los fallos NO se cachean: un llavero bloqueado suele ser temporal y
  recordar el "no" condenaria la sesion.
- `ChatSettings.preferredProviderName` sustituido por `providerOrder: [String]`
  (ids, no nombres: el nombre es copy y se puede reescribir).
- **Ausente no significa apagado.** Un proveedor que el usuario nunca vio no
  puede nacer apagado, porque no hay como encenderlo hasta que exista el panel.
- `ProviderDescriptor.openRouter`: la enum `SecretKey` tenia el caso desde
  siempre y le faltaba el descriptor, que era justo lo que hacia inalcanzable
  esa fila.
- Aceptar la base local **pone esa fila primero**: quien elige hablar con su
  propio Mac no la quiere de respaldo.

Pendiente: la UI del panel de 9b-3, el contador de procesos de 9c-3,
9b-4 (descarga opcional por `POST /api/pull`), 9b-2 (Apple FM, tras su puerta
de evidencia de 4096 tokens).

## Foco anterior

**Wave 9 en curso.** El grueso salio en la release 0.10.0 (2026-08-22):
idioma de UI y de prompts, nombre del producto, ruta de instalacion sin
compilar y el primer DMG publicado. La auditoria del flujo completo hecha
ese mismo dia midio que tan cerrado esta el circuito, dimension por
dimension:

| Dimension | Estado |
|---|---|
| Mecanica (build, tests, gates, TurnMachine) | SOLIDO |
| Release y trazabilidad (DMG, tag, CHANGELOG, licencias) | CERRADO |
| Voz vs especialista: la voz nunca inventa un final feliz | PARCIAL |
| Idioma | CERRADO |
| Onboarding en frio | ABIERTO |
| README como puerta de entrada | PARCIAL |

Cerrado despues de esa medicion:

- **El idioma manda en todo el plano de voz.** El reconocedor escucha en el
  idioma del usuario, el permiso se pregunta en ese idioma y la voz de
  respaldo sin red contesta en el. Los tres puntos donde se decidia un locale
  a mano derivan ahora de `AppLanguage`, unica fuente.
- **Un encargo que falla dice por que.** Los ejecutores de CLI devolvian una
  salida vacia y la voz rellenaba el hueco con un reloj que nunca corrio.
- **Un permiso negado se reporta como permiso**, no como sintesis rota.
- **Lo imposible se responde sin red**: un pegado que no puede ser una clave
  ya no cuesta un viaje a OpenAI para volver culpando a la clave.

Lo que sigue abierto, en orden:

1. **La guia de Gatekeeper no viaja con el DMG**: quien solo descarga se
   queda sin ella justo cuando la necesita, y en macOS 15+ no hay clic
   derecho que lo salve.
2. **El acuse hablado no llega al pipeline clasico.** El ADR 005 zanjo que el
   encargo no habla por su cuenta y que la voz solo acusa; en clasico no hay
   modelo que genere ese acuse, asi que el encargo termina en silencio. Se
   podria decir por el sintetizador, que ahi si acepta texto arbitrario.
   Decision pendiente.
3. **La delegacion no se descubre sola.** Es la capacidad mas diferenciada y
   la menos obvia: un desconocido puede usar Companion como chat con voz y no
   tocar nunca al especialista. Mejor tarjeta y mejores pasos no ensenan que
   se puede pedir.
4. **Cambiar el idioma no alcanza a una sesion de voz ya abierta**, como
   tampoco la alcanzan la voz ni la velocidad: se aplica en la siguiente.
5. **README sin captura y sin video**: la narrativa de producto ya esta
   (que problema resuelve, para quien, por que se reconstruyo), pero de un
   producto visual no se ve un solo pixel antes de compilarlo.

Dos hallazgos de aquella auditoria no sobrevivieron a la verificacion contra
el codigo, y quedan anotados para que nadie los persiga otra vez: el circuito
de anuncios **si** tiene tests (`VoiceJobCircuitTests` cubre que el anuncio
sale al escuchar y que espera su turno mientras el agente habla), y un
llavero rechazado **no** pierde la clave: se queda en el campo y el boton la
reintenta.

Y lo que solo Karen puede cerrar: repetir la prueba manual de delegacion
("crea un archivo prueba1.md en mi escritorio"), el veredicto visual del
design system (criterio de done de 6b, programa atomico en
`docs/specs/ds/`), y despues notarizar o las ideas post-v1.


## Brecha con el prototipo (medida 2026-08-22)

| | Prototipo | Rebuild |
|---|---|---|
| Sources | 15.307 lineas | 18.125 |
| Tests | 1.228 lineas | 14.838 |
| Dependencias | Pow, livekit-ui, Orb (vendoreados), Mapbox, Hermes (Python) | RiveRuntime.xcframework |

La medicion del 2026-08-21 ("~10.600 contra 15.300, cero dependencias
externas") quedo obsoleta en un dia y en dos sentidos: el rebuild ya es mas
grande que el prototipo en codigo fuente, y tiene una dependencia binaria
(ADR 003, atribuida y fijada por checksum en `NOTICE.md`). Es la unica, y
sumar otra exige otro ADR.

Los cuatro puntos de dolor de aquella medicion estan **cerrados**: menu de
aplicacion (Cmd+C/V/X), adjuntos con arrastre, actualizaciones contra
GitHub Releases, y el pulido (avisos, sonido al pensar, sintaxis resaltada,
ajustes de fin de turno). Lo que queda vive en Wave 8 y en el programa DS.

Fuera por decision, no por olvido: handoff a terminal de Hermes (ADR 001),
Sparkle (ADR 002). El mapa pasa de Mapbox a MapKit: menos personalizable,
sin token ni WebView.

## Deuda consciente (con trigger)

- Firma ad-hoc: los permisos TCC de microfono se re-piden en cada rebuild.
  Identidad estable "Companion Dev" -> Wave 5.

- Notarizacion: notarytool ya esta disponible (Xcode instalado); falta la
  cuenta de Apple Developer -> decision de Karen, no bloqueo tecnico.

## Despues de v1 (ideas, sin compromiso)

- Transporte WebRTC (AEC3 por software) — **trigger probado 2026-08-21**: en
  la Mac de Karen VPIO no inicializa (-10875); era el camino primario del
  prototipo por esta exacta razon. Primera candidata post-v1.
- SpeechAnalyzer (macOS 26) como STT local de proxima generacion.
- Servidores MCP como fuente de tools extra del NativeExecutor.
