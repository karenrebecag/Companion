# Reference Brief: division de VoiceSession (actor de voz)

Slug: voicesession-division | Nivel: deep | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE
Decision de Karen (2026-09-30): structs puros en Core, un solo actor, sin actores nuevos; `NonisolatedNonsendingByDefault` se evalua aparte.

## 1. Pregunta y decisiones abiertas

Pregunta: VoiceSession (Sources/CompanionServices/Voice/Session/, un actor de ~2180 lineas repartido en 14 archivos VoiceSession*) fue marcado por la auditoria como el siguiente refactor estructural. Hay que partirlo, y como. Encargo delegado por Karen al orquestador ("haste cargo de las specs para siguientes pasos"); no hay discovery.

Entrada fija, no se redisena aqui: el arreglo en curso de la worktree companion-next-voice-reconnect cambia `reconnectRealtimeSession` y el aislamiento de `RealtimeRuntime`. Este brief lo trata como precondicion.

Bloque D1 - Partir o no, y en que forma: (1) un actor con colaboradores propios por concern, (2) varios actores que se comunican, (3) extraer logica pura a Core y dejar VoiceSession como ejecutor de efectos.

Bloque D2 - Aislamiento de los colaboradores: clases `@unchecked Sendable` con metodos async (hoy), `nonisolated(nonsending)` de SE-0461, parametros `isolated` de SE-0313, o actores propios.

Bloque D3 - Camino de audio en tiempo real: cuantos saltos de actor admite el pump de frames y que cuesta cada uno.

Bloque D4 - Testabilidad: que pasa con el harness (`makeVoiceHarness`, `ScriptedVoiceTransport` y demas fakes) y con los ~150 accesos de los tests a estado interno del actor.

Bloque D5 - Secuencia: en que orden y con que tamano de entrega, dado el arreglo de reconexion en vuelo.

## 2. Estado actual

Contextos: app enviada en modo realtime (socket OpenAI, pumps de eventos/frames/parciales/turnos del oido/drenado/niveles/voz); app enviada en modo clasico (ClassicRuntime, sintetizador, anuncios de trabajos); `swift test` con `makeVoiceHarness` y los fakes Scripted* (harness `@MainActor`, `@testable`); CI en GitHub Actions macos-26 via `scripts/gates.sh` con `swift test --no-parallel`. No hay previews ni CLI que construyan VoiceSession.

### Medicion de tamano y forma- VoiceSession es un `package actor` que conforma `VoiceControlling` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:4]
- Los 14 archivos VoiceSession* de Session/ suman 2180 lineas con los tres auxiliares; el principal tiene 374 y el mayor, Pumps, 387 [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:1]
- Hay una extension mas fuera de la carpeta, `attachTranscriptLog`, en el oido [repo:Sources/CompanionServices/Voice/Ear/TranscriptDebugLog.swift:120]
- El bloque de propiedades almacenadas va de la linea 5 a la 177 y declara 76 miembros `var`/`let`, 12 de ellos handles `Task<...>` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:33]
- El gate de tamano de CI es por archivo (warn >400, fail >800), por eso partir en extensiones lo satisface sin reducir el estado del actor [repo:scripts/gates.sh:45]
- Cada extension declara en su comentario que se partio por el gate de 400/800 lineas y que el actor, no el nivel de acceso, mantiene el estado en un solo hilo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:4]

### Responsabilidades por archivo- VoiceSession.swift: estado, init que cablea runtimes, guards y closures de delegacion, y la API publica start/hangUp/interrupt/toggleMute/setSpeed [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:179]
- TurnLoop: `apply(event)` llama al reductor puro `machine.handle` y `perform(effects)` ejecuta cada TurnEffect [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:33]
- Pumps: siete tareas que leen streams (transporte, mic, parciales, turnos del oido, drenado, niveles, sintetizador) y la reconexion [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:10]
- RealtimeOpen: abrir mic, player y socket, arrancar el oido en paralelo, esperar ready por sondeo de 5 ms y armar el watchdog de silencio [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:11]
- Hold: presion provisional, confirmacion, rebote, cola de liberacion de 300 ms y descarte, con `holdGeneration` como guard de reentrada [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:61]
- Commit: fin del turno de usuario, dictado al campo enfocado o envio al agente con contexto sensado [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Commit.swift:13]
- Approvals: libro de permisos (job y MCP), palabras de la ultima pulsacion, frente de la hoja y admision del si hablado [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:164]
- Announcements: cola de avisos de fin de trabajo, candado de un aviso a la vez, descarte por antiguedad y publicacion de `.announcing` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:51]
- Decision, FanOut, Steer, Teardown y Timeline son extensiones de 32 a 70 lineas: puerta de decision local, precalentado al pulsar, tarea cancelable del turno clasico, cierre con nota de memoria y reloj del hold [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Decision.swift:14]
- VoiceJobBridge ya vive fuera del actor como enum con una funcion estatica que corre el trabajo y reporta por closures [repo:Sources/CompanionServices/Voice/Session/VoiceJobBridge.swift:6]

### Estado que cruza extensiones (acoplamiento medido con grep por nombre)- `machine` (TurnMachine) lo leen 9 de los 15 archivos; `eventBox` 7; `timeline` 8 [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:12]
- La admision del si hablado lee `timeline.pressed` (reloj del hold) y `machine.snapshot.pipeline` en la misma funcion sincrona [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:155]
- La cola de avisos consulta `livePendingApproval` del libro de permisos para no preguntar algo ya contestado [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:63]
- `heardThisHold` lo escriben Approvals, Hold y TurnLoop [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:76]
- `voiceClosed` lo escriben el archivo principal, Hold, Teardown y TurnLoop [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:43]

### Lo que ya es puro y vive en Core- TurnMachine es un struct Sendable con `mutating func handle(_:at:) -> [TurnEffect]` [repo:Sources/CompanionCore/Session/TurnMachine.swift:17]
- SessionMachine es el segundo reductor, con `mutating func handle(_ event: SessionEvent) -> [SessionEffect]` [repo:Sources/CompanionCore/Session/SessionMachine.swift:57]
- La arquitectura declara el patron: reductor de valor `handle(event) -> [Effect]` y un runtime en Services que ejecuta efectos [repo:docs/ARCHITECTURE.md:60]
- Ya estan en Core: TurnTimeline, SpokenYes, AnnouncementGap, EchoGuard, TranscriptEndpointer, RealtimeGate y DictationRouter [repo:Sources/CompanionCore/Session/Acknowledgement.swift:52]
- Un HACK en el actor ya nombra el destino de parte del libro de permisos: la lista FIFO de 64 ids cerrados pasa a la cola del reductor cuando una fuente reuse ids [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:96]

### Lo que no es puro y no puede serlo- Los pumps consumen AsyncStreams de puertos y hacen `await` por frame a `mic.hasEchoCancellation`, `audit.hear`, `classic.flushEarlyAudio` y `transcriber.append` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:190]
- Commit espera 250 ms con `Task.sleep` para que el ultimo parcial asiente antes de leerlo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Commit.swift:27]
- `release()` guarda `holdGeneration`, suspende en `mic.receivedBuffer` y descarta si otra pulsacion llego en ese hueco [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:176]

### Aislamiento de los colaboradores actuales- RealtimeRuntime es `final class ... @unchecked Sendable` y su comentario afirma que esta aislada por acceso exclusivo desde VoiceSession [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:6]
- ClassicRuntime repite la forma y la misma afirmacion [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:6]
- VoiceAudit tambien es `@unchecked Sendable` y dice llamarse solo desde el contexto del actor [repo:Sources/CompanionServices/Voice/Ear/VoiceAudit.swift:15]
- `RealtimeRuntime.handle` es un metodo `async` de clase no aislada y muta `agentSpeech` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:254]
- El pump de turnos del oido lee `realtime.agentSpeech` desde el actor para el filtro de eco [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:103]
- El turno clasico corre en `Task { [weak self] in ... await self.classic.submit(...) }` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- Package.swift no declara `enableUpcomingFeature` ni `swiftSettings` para CompanionServices; solo UI y App fijan `defaultIsolation(MainActor.self)` [repo:Package.swift:25]

### Reconexion (entrada, no se redisena)- `pumpEvents` llama a `reconnectRealtimeSession` desde dentro de la propia tarea `eventTask` cuando el stream termina en listening o speaking [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:140]
- `reconnectRealtimeSession` reabre el transporte y llama a `startPumps`, que solo crea el pump de eventos si `eventTask == nil` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:160]
- La worktree companion-next-voice-reconnect esta en 08cd9cb sin cambios en el arbol al momento de esta lectura, asi que el diff del arreglo no se pudo leer [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:147]

### Llamadores- La raiz de composicion construye la unica instancia de la app [repo:Sources/CompanionApp/CompanionMainVoice.swift:112]
- La UI la ve solo por el protocolo `VoiceControlling` (SessionModel y VoiceViewModel) [repo:Sources/CompanionUI/Voice/SessionModel.swift:18]
- El protocolo expone hold/release/discard/interrupt/approvalClosed/approvalFront y los streams snapshots/levels [repo:Sources/CompanionCore/Voice/VoicePorts.swift:139]
- La raiz ademas llama `attachDecision` y `attachTranscriptLog` en Tasks sueltas tras construirla [repo:Sources/CompanionApp/CompanionMainVoice.swift:153]

### Tests y CI- El harness `VoiceHarness` agrupa la sesion con ScriptedVoiceTransport, ScriptedMic, ScriptedPlayer, ScriptedTranscriber, ScriptedSynth y demas [repo:Tests/CompanionTests/VoiceSessionFakes.swift:10]
- `makeVoiceHarness` es `@MainActor` y es la unica forma en que los tests construyen la sesion [repo:Tests/CompanionTests/VoiceSessionFakes.swift:30]
- ScriptedVoiceTransport reusa una sola `StreamBox`; `simulateStreamEnd` la termina [repo:Tests/CompanionTests/VoiceSessionFakes.swift:153]
- `ScriptedMic.receivedBufferDelay` es, segun su propio comentario, la unica forma de meter una llamada en los puntos de suspension de la sesion [repo:Tests/CompanionTests/VoiceSessionFakes.swift:220]
- Un test de carrera usa ese retraso para meter un `hold()` dentro del `release()` en vuelo [repo:Tests/CompanionTests/HoldVoiceTests.swift:238]
- 20 archivos de test leen estado interno de la sesion (timeline, pendingApproval, parkedAnnouncements, noteHeard, apply, classic, audit...) [repo:Tests/CompanionTests/Approvals16q1Round2Tests.swift:97]
- CI corre `swift test --no-parallel` cuando `CI=true` [repo:scripts/gates.sh:245]
- El workflow corre en macos-26 y solo invoca gates.sh [repo:.github/workflows/ci.yml:15]
- Un incidente documentado: una sonda de Accesibilidad colgada en la pulsacion congelaba el actor de voz entero, y se saco a una Task.detached [repo:docs/REFERENCE.md:343]

## 3. Fuentes primarias

- Las funciones aisladas a un actor son reentrantes: al suspender, otro trabajo corre en el actor antes de reanudar (interleaving) [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- El estado aislado puede cambiar a traves de un await y el desarrollador no debe romper invariantes a traves de un await [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- La mitigacion propuesta: el codigo sincrono de un actor es una seccion critica y un await la interrumpe, asi que las actualizaciones de estado van en funciones sincronas [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- SE-0338: las funciones async no aisladas a un actor corren en un ejecutor generico y cambian de ejecutor en cada entrada, retorno y reanudacion [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@6.2]
- SE-0461, implementado en Swift 6.2: `nonisolated(nonsending)` corre siempre en el actor del llamador y `@concurrent` fija el comportamiento SE-0338 [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- SE-0461 advierte que adoptar la nueva semantica puede empeorar rendimiento del codigo que dependia de salir del actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- El flag `NonisolatedNonsendingByDefault` (Swift 6.2) hace que las async no aisladas corran en el actor del llamador; su modo `:migrate` agrega `@concurrent` para conservar la semantica actual [doc:https://github.com/swiftlang/swift/blob/main/userdocs/diagnostics/nonisolated-nonsending-by-default.md@6.2]
- El anuncio de Swift 6.2 presenta esa ejecucion en el contexto del llamador como feature futura opcional, con `@concurrent` para lo que debe correr en paralelo [doc:https://www.swift.org/blog/swift-6.2-released/@6.2]
- SE-0313: una funcion con un parametro `isolated` queda aislada a ese actor y accede a su estado de forma directa [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0313-actor-isolation-control.md@6.2]
- SE-0420: `isolated (any Actor)? = #isolation` hereda la aislacion del llamador y evita suspensiones entre ejecutores [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md@6.2]
- SE-0420 cita la regla de SE-0304: un closure de `Task` hereda la aislacion si captura fuertemente el parametro aislado, incluido el `self` implicito del actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md@6.2]
- WWDC21: saltar entre actores sin contencion no bloquea ni necesita otro hilo; saltar al main actor si exige un cambio de contexto [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@2021]
- WWDC21: por la reentrancia, un actor puede ejecutar trabajo en orden que no es estrictamente FIFO, priorizando lo de mayor prioridad [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@2021]

## 4. Implementaciones de referencia

- LiveKit client-sdk-swift (SDK oficial de LiveKit, 447 estrellas, push 2026-09-30): `Room` es una sola clase `@unchecked Sendable` repartida en `Room+Concern.swift` [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/Room.swift#L31@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- LiveKit guarda el estado de Room en un unico `StateSync<State>` protegido, no en actores por concern [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/Room.swift#L261@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- LiveKit si hace actor propio del cliente de senalizacion, que es un ciclo de vida de I/O separado (socket) [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/SignalClient.swift#L23@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- Ese actor descarta callbacks de un socket viejo comparando identidad (`_state.socket === socket`) tras cada entrada [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/SignalClient.swift#L349@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- LiveKit aisla WebRTC en un global actor `@RTC` sobre su propia cola porque sus llamadas bloquean y el pool cooperativo no crece [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/RTC.swift#L47@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- LiveKit deja el camino de envio por paquete `nonisolated` a proposito por ser sensible a latencia [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/RTC.swift#L51@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- swift-realtime-openai (m1guelpf, 435 estrellas, cliente Swift comunitario de la Realtime API; OpenAI no publica uno oficial en Swift): la sesion es `@MainActor @Observable` [ref:https://github.com/m1guelpf/swift-realtime-openai/blob/46f393d9e2e60724aadc30062f75ee73bbcdb8fc/Sources/UI/Conversation.swift#L12@46f393d9e2e60724aadc30062f75ee73bbcdb8fc]
- En ese cliente el manejo de eventos del servidor es sincrono (`func handleEvent(_:) throws`), sin await dentro [ref:https://github.com/m1guelpf/swift-realtime-openai/blob/46f393d9e2e60724aadc30062f75ee73bbcdb8fc/Sources/UI/Conversation.swift#L167@46f393d9e2e60724aadc30062f75ee73bbcdb8fc]
- Pipecat client iOS (pipecat-ai, 26 estrellas, tools 5.5, referencia debil por escala): el cliente es `@MainActor` [ref:https://github.com/pipecat-ai/pipecat-client-ios/blob/ebf07b85ed99bfec27ae579c5b56430ec88eafdf/Sources/PipecatClientIOS/PipecatClient.swift#L8@ebf07b85ed99bfec27ae579c5b56430ec88eafdf]
- Pipecat delega medios y socket a un protocolo `Transport` intercambiable, tambien `@MainActor` [ref:https://github.com/pipecat-ai/pipecat-client-ios/blob/ebf07b85ed99bfec27ae579c5b56430ec88eafdf/Sources/PipecatClientIOS/transport/Transport.swift#L4@ebf07b85ed99bfec27ae579c5b56430ec88eafdf]
- TCA 1.26.2 (Point-Free, release 2026-08-28): el ejemplo de reconocimiento de voz tiene un reductor puro que devuelve `.run` y reenvia resultados con `send` [ref:https://github.com/pointfreeco/swift-composable-architecture/blob/377da4061db10d26337a71bb279c506bb951f50f/Examples/SpeechRecognition/SpeechRecognition/SpeechRecognition.swift#L47@377da4061db10d26337a71bb279c506bb951f50f]
- En ese ejemplo el motor de audio vive en un actor privado de la dependencia, y el reductor ve transcripciones, nunca frames [ref:https://github.com/pointfreeco/swift-composable-architecture/blob/377da4061db10d26337a71bb279c506bb951f50f/Examples/SpeechRecognition/SpeechRecognition/SpeechClient/Live.swift#L26@377da4061db10d26337a71bb279c506bb951f50f]
- TCA cancela efectos por identificador con `cancellable(id:cancelInFlight:)` en vez de guardar handles de Task [ref:https://github.com/pointfreeco/swift-composable-architecture/blob/377da4061db10d26337a71bb279c506bb951f50f/Sources/ComposableArchitecture/Effects/Cancellation.swift#L36@377da4061db10d26337a71bb279c506bb951f50f]

## 5. Opciones

D1 - forma de la division:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| (1) Un actor, colaboradores propios por concern (no actores) | Cero saltos nuevos; conserva el orden de los pumps; mismo patron que LiveKit Room | Si los colaboradores son clases con metodos async, heredan el problema SE-0338 de hoy | media | Si, como envoltorio de (3) |
| (2) Varios actores (transporte, trabajos, pump de audio) | Estado de cada uno encapsulado por el compilador | Cada lectura cruzada (timeline.pressed, pipeline, livePendingApproval) pasa a ser await: nuevos puntos de reentrada en la admision del si hablado; orden no FIFO entre actores; mas saltos por frame | alta | No |
| (3) Logica pura a Core (ledgers y reductores) + VoiceSession ejecutor de efectos | Tests sin fakes; decisiones de seguridad en seccion critica sincrona; ya es el patron de ARCHITECTURE.md | No reduce los pumps ni el I/O; migrar los tests que leen internals | media | Si, primero |
| No partir | Nada se mueve | 76 miembros y 12 Tasks en un actor; el gate por archivo no mide eso | baja | No |

D2 - aislamiento de colaboradores:

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| Structs de valor en Core, mutados sincronamente por el actor | Sin aislamiento que razonar; Sendable real | Solo sirve para lo puro | baja | Si para lo puro |
| Helpers con parametro `isolated VoiceSession` (SE-0313) | Corren en el actor, acceso sincrono, sin salto | Acopla el helper al tipo concreto del actor | baja | Si para pumps/I-O si se sacan del actor |
| `nonisolated(nonsending)` en metodos de los runtimes | Corren en el actor del llamador, quita el salto SE-0338 | Lo decide el arreglo de reconexion en vuelo | baja | Adoptar lo que fije ese arreglo |
| Flag `NonisolatedNonsendingByDefault` en CompanionServices | Arregla todas las async no aisladas del target | Cambia Package.swift (config raiz, bloqueada para agentes) y puede sacar trabajo lento al actor | media | Decision de Karen, fuera de este refactor |
| Actores propios para RealtimeRuntime/ClassicRuntime | Estado protegido por compilador | Lecturas sincronas actuales (micEnabled, didBecomeReady, agentSpeech) se vuelven await | alta | No |

D3/D4/D5 se resuelven en secciones 7-10.

## 6. Evidencia en contra

- Contra (3): el grueso de las lineas son pumps e I/O, no decisiones; sacar ledgers a Core reduce quiza 300-400 lineas y el actor sigue con los 12 handles de Task [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:10]
- Se acepta: el riesgo que motiva el refactor es de correccion (reentrada, carreras, admision de permisos), y esa logica es justo la que (3) mueve a secciones criticas sincronas [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]
- Contra (3): los tests leen estado interno (pendingApproval, parkedAnnouncements, heardThisHold) y moverlo rompe ~150 referencias en 20 archivos [repo:Tests/CompanionTests/Approvals16q1Round2Tests.swift:97]
- Se resuelve con propiedades computadas de reenvio en el actor durante la migracion, y retirandolas cuando cada test tenga su version pura en Core [repo:Tests/CompanionTests/VoiceSessionFakes.swift:10]
- A favor de (2), su argumento mas fuerte: un actor unico serializa todo, y ya hubo un congelamiento del actor de voz por una llamada bloqueante [repo:docs/REFERENCE.md:343]
- Se rechaza igual: ese incidente se arreglo sacando la llamada bloqueante a una Task.detached, que es lo que LiveKit hace con `@RTC`; no hizo falta partir el estado [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/RTC.swift#L47@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- A favor de (2): TCA si pone el audio en un actor propio [ref:https://github.com/pointfreeco/swift-composable-architecture/blob/377da4061db10d26337a71bb279c506bb951f50f/Examples/SpeechRecognition/SpeechRecognition/SpeechClient/Live.swift#L26@377da4061db10d26337a71bb279c506bb951f50f]
- Aqui no aplica tal cual: ese actor es el adaptador (equivalente a MicCapture, que ya esta fuera del actor), y el reductor no recibe frames; en Companion el pump de frames decide barge-in y compuerta de eco con el estado del turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:207]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, seccion critica: `commitTimeline` y `markTool` son sincronos y comparan generaciones sin await de por medio [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Timeline.swift:21]
- Bien hecho, guard tras suspension: `release()` captura `holdGeneration`, suspende y compara antes de seguir [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:178]
- El mismo patron en LiveKit: comprobar identidad del socket al entrar, antes de tocar estado [ref:https://github.com/livekit/client-sdk-swift/blob/404f4a133f514fc589b68ab6e6f0e39c763c480d/Sources/LiveKit/Core/SignalClient.swift#L344@404f4a133f514fc589b68ab6e6f0e39c763c480d]
- Bien hecho, eventos del servidor sin await dentro del manejador, lo que elimina la reentrada en el reductor [ref:https://github.com/m1guelpf/swift-realtime-openai/blob/46f393d9e2e60724aadc30062f75ee73bbcdb8fc/Sources/UI/Conversation.swift#L167@46f393d9e2e60724aadc30062f75ee73bbcdb8fc]
- Bien hecho, reductor puro en Core que el actor muta sincronamente y cuyo resultado ejecuta despues [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:33]
- Anti-ejemplo: `noteMCPApproval` agrega a la lista, hace `await mcpGuard.decide` (60 s) y recien despues relee la lista para saber si sigue viva; es correcto hoy porque relee, pero cada await nuevo en esta zona pide lo mismo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Approvals.swift:32]
- Anti-ejemplo: la afirmacion "aislada por acceso exclusivo en VoiceSession" en una clase `@unchecked Sendable` cuyos metodos async, sin anotacion, corren en el ejecutor generico segun SE-0338 [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:5]
- Anti-ejemplo: `waitForReady` sondea `realtime.didBecomeReady` cada 5 ms en vez de esperar un evento; partirlo en otro actor convertiria cada sondeo en un salto [repo:Sources/CompanionServices/Voice/Session/VoiceSession+RealtimeOpen.swift:133]

### Forma recomendada (fragmento ilustrativo, no codigo existente)
```swift
// Core: puro, Sendable, testeable sin fakes.
package struct ApprovalLedger: Sendable, Equatable {
    package mutating func armed(_ request: ApprovalRequest, at now: TimeInterval)
    package mutating func closed(requestId: String)
    package mutating func heard(_ text: String, pressed: TimeInterval?, holdPressed: TimeInterval?)
    package mutating func answer(_ approved: Bool, pipeline: VoicePipeline?,
                                 holdPressed: TimeInterval?, now: TimeInterval) -> SpokenApprovalDecision
}
// Services: el actor muta sincronamente y ejecuta el efecto despues.
let decision = approvals.answer(approved, pipeline: machine.snapshot.pipeline,
                                holdPressed: timeline.pressed, now: now())
```

## 8. Trampas

### Por contexto de ejecucion- App realtime: cualquier colaborador nuevo en el camino de frames que sea actor propio agrega un salto por frame (tap de 2048 muestras) y rompe el orden entre el pump de frames y el pump de eventos, que hoy serializa un solo actor [repo:Sources/CompanionServices/Voice/Audio/MicCapture.swift:173]
- App realtime: sin contencion el salto es barato, pero con contencion la reentrancia no garantiza FIFO entre trabajos del actor [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@2021]
- App clasico: `classic.submit` corre en una Task con captura debil de self; por la regla de SE-0304 citada en SE-0420 esa Task no hereda el actor, y el metodo no aislado corre en el ejecutor generico mientras el actor sigue tocando `classic.holdAudio` y `classic.pressedContext` [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md@6.2]
- App ambos modos: la misma forma afecta a `realtime.handle`, que muta `agentSpeech` mientras el actor, suspendido en ese await, puede correr `pumpEarTurns` que lo lee [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:126]
- swift test: mover estado fuera del actor cambia los puntos de suspension, y el test de carrera que usa `receivedBufferDelay` depende de que el hueco exista exactamente en `mic.receivedBuffer` [repo:Tests/CompanionTests/HoldVoiceTests.swift:239]
- swift test: el harness es `@MainActor`; un colaborador nuevo aislado a otro actor obliga a awaits nuevos en los tests y cambia el orden observado por `SnapWatch` [repo:Tests/CompanionTests/VoiceSessionFakes.swift:30]
- CI: `--no-parallel` oculta carreras entre tests pero no carreras dentro de una sesion; un refactor que introduzca una carrera intra-sesion puede pasar en CI y fallar en la app [repo:scripts/gates.sh:245]
- CI: el gate de 800 lineas es por archivo y `try?` esta prohibido en Core y Services; un ledger nuevo en Core hereda la prohibicion [repo:scripts/gates.sh:54]

### Generales- Activar `NonisolatedNonsendingByDefault` en todo el target mueve al actor trabajo que hoy sale de el (p. ej. sensado, inyeccion); SE-0461 advierte regresiones de rendimiento en ese caso [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- Tocar `reconnectRealtimeSession`, `pumpEvents` o el aislamiento de RealtimeRuntime antes de que se integre el arreglo de reconexion produce un conflicto sobre las mismas lineas [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:119]
- Mover `closedApprovals` al SessionMachine (UI, MainActor) haria que la admision del si hablado espere al MainActor: un salto con cambio de contexto y un punto de reentrada en codigo de seguridad [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:98]
- Las closures de delegacion del init capturan `[weak self]` y lanzan Tasks sin orden entre si (noteApproval y askApprovalAloud); el test de ronda 2 existe por esa carrera y cualquier colaborador nuevo debe conservar el FIFO de ids cerrados [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:295]

## 9. Incertidumbre

- ASSUMPTION: la Task del turno clasico y `realtime.handle` corren de verdad fuera del actor y hay acceso concurrente a ClassicRuntime/RealtimeRuntime. prueba: agregar temporalmente `dispatchPrecondition`/`assertIsolated` o correr `swift test --sanitize=thread --filter Voice` sobre main y ver si TSan reporta en `agentSpeech` o `holdAudio`.
- ASSUMPTION: `nonisolated(nonsending)` se puede escribir por metodo en Swift 6.2 sin activar el flag del target. prueba: compilar un metodo `nonisolated(nonsending) func f() async` en CompanionServices con el toolchain de CI (macos-26).
- ASSUMPTION: el costo de un salto de actor sin contencion es despreciable frente al periodo de un buffer de 2048 muestras (unos 43 ms a 48 kHz). prueba: medir con `ContinuousClock` el tiempo por iteracion de `pumpFrames` antes y despues de cada paso, en un hold real, y registrarlo en la linea de timeline.
- ASSUMPTION: extraer ApprovalLedger, AnnouncementQueue y HoldGate reduce el actor en 300-400 lineas; no se midio funcion por funcion. prueba: contar las lineas de Approvals.swift, Announcements.swift y Hold.swift que no contienen `await` ni I/O.
- ASSUMPTION: el arreglo de reconexion hara que el pump de eventos se recree tras reabrir el socket y fijara el aislamiento de RealtimeRuntime; su diff no existia en la worktree al leerla. prueba: leer el diff de fix/voice-reconnect cuando se abra el PR y actualizar D2 con lo que decida.
- Las referencias oficiales de OpenAI para Realtime son JavaScript (openai-realtime-console); no se leyo su codigo y no hay cliente Swift oficial que citar.
- [NEEDS CLARIFICATION: activar `NonisolatedNonsendingByDefault` en CompanionServices es un cambio de Package.swift (config raiz); Karen decide si se evalua aparte o si el refactor se queda con anotaciones por metodo.]

## 10. Checklist de estandar

- [ ] El refactor empieza despues de integrar fix/voice-reconnect y no modifica `reconnectRealtimeSession`, `pumpEvents` ni el aislamiento de RealtimeRuntime mas alla de lo que ese arreglo fije.
- [ ] No se crea ningun `actor` nuevo en Voice/Session; VoiceSession sigue siendo el unico dominio de aislamiento del turno.
- [ ] Cada cluster extraido (ApprovalLedger, AnnouncementQueue, HoldGate) es un struct `Sendable` en CompanionCore, sin imports de frameworks ni `async`, con tests unitarios propios que no usan el harness de voz.
- [ ] Toda mutacion de un ledger y la decision que depende de ella ocurren en una funcion sincrona del actor, sin `await` entre leer y escribir.
- [ ] Todo `await` que quede en codigo de permisos va seguido de una revalidacion (id vivo, generacion de hold) antes de mutar o emitir.
- [ ] El camino de `pumpFrames` no gana ningun salto de actor nuevo; se registra el tiempo por frame antes y despues.
- [ ] Los tests existentes siguen verdes sin editarse en el primer paso; el actor expone propiedades computadas de reenvio para los internals que leen los tests, retiradas en un paso posterior.
- [ ] El test de carrera con `receivedBufferDelay` sigue pasando y cubre el mismo hueco.
- [ ] `scripts/gates.sh` en verde con `CI=true` (`--no-parallel`), sin `try?` nuevo en Core o Services.
- [ ] Una entrega por cluster, de 3 a 5 archivos cada una.
- [ ] Ningun cambio a Package.swift en este refactor.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0306 Actors | Swift Evolution | Swift 5.5, vigente en 6.2 | 2026-09-30 | high |
| 2 | SE-0338 Clarify the Execution of Non-Actor-Isolated Async Functions | Swift Evolution | Swift 5.7 | 2026-09-30 | high |
| 3 | SE-0461 Run nonisolated async functions on the caller's actor by default | Swift Evolution | Swift 6.2 | 2026-09-30 | high |
| 4 | NonisolatedNonsendingByDefault (userdocs) | swiftlang/swift | Swift 6.2 | 2026-09-30 | high |
| 5 | Swift 6.2 Released | swift.org | 2025-09-15 | 2026-09-30 | high |
| 6 | SE-0313 Improved control over actor isolation | Swift Evolution | Swift 5.5 | 2026-09-30 | high |
| 7 | SE-0420 Inheritance of actor isolation | Swift Evolution | Swift 6.0 | 2026-09-30 | high |
| 8 | Swift concurrency: Behind the scenes (WWDC21 10254) | Apple | 2021 | 2026-09-30 | medium |
| 9 | livekit/client-sdk-swift | LiveKit | 404f4a1 | 2026-09-30 | high |
| 10 | m1guelpf/swift-realtime-openai | comunidad | 46f393d | 2026-09-30 | medium |
| 11 | pipecat-ai/pipecat-client-ios | Pipecat | ebf07b8 | 2026-09-30 | low |
| 12 | pointfreeco/swift-composable-architecture | Point-Free | 1.26.2 (377da40) | 2026-09-30 | high |
| 13 | Codigo de companion-next | proyecto | 08cd9cb | 2026-09-30 | high |
