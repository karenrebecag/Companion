# Reference Brief: carrera de datos en ClassicRuntime entre submit y speak

Slug: classic-runtime-submit-speak | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

Decision de Karen (2026-09-30): D1 C1+B (estado por turno + Mutex para steerPending, leftoverHeard y pressedContext); D2 serializar turnos en un PR aparte despues de C2; D3 Mutex. [KAREN:chat 2026-09-30 via orquestador]

## 1. Pregunta y decisiones abiertas

TSan reporta una carrera en produccion: `ClassicRuntime.submit` escribe `cardThisTurn` (ClassicRuntime.swift:285) y `ClassicRuntime.speak` lo lee (ClassicRuntime+Mouth.swift:138), ambos en hilos de trabajo de GCD, mientras corre `backgroundJobRuntimeTests`. Hay que decidir como sacar el estado compartido de la carrera sin romper el corte por pulsacion.

Decisiones:

- D1. Que mecanismo elimina la carrera: (A) confinar el turno clasico al actor `VoiceSession` (`nonisolated(nonsending)` mas un Task que herede el actor), (B) poner bajo lock (`Mutex`, SE-0433) los campos compartidos, (C) reestructurar: el estado de cada turno vive en el turno y no en el runtime, o una combinacion.
- D2. Si los turnos clasicos deben serializarse (el turno nuevo espera a que termine el cortado), lo que exige tocar `VoiceSession+Steer.swift` (coordinacion con la otra sesion).
- D3. Que test en rojo lo prueba bajo `swift test --sanitize=thread`.

Restricciones dadas por la orquestacion: sin cambiar `Package.swift`; el corte por pulsacion debe seguir funcionando; coherencia con la decision B1 ya mergeada para RealtimeRuntime; no proponer cambios en `VoiceSession+Pumps.swift`, `RealtimeRuntime.swift`, `ContextBlock.swift`, `SpeechFilter.swift`, `SessionMachine.swift`, `TurnContext.swift`, IslandState/IslandEvents ni los Localizable.strings; avisar cualquier cambio en `VoiceSession+Steer.swift`.

Se reutiliza el brief APROBADO `voz-reconexion-aislamiento` (mismas versiones, swift-tools=6.2) para SE-0338, SE-0461 y el antiejemplo de addTask; este brief no los vuelve a investigar desde cero, pero cada cita de abajo se releyo en este run.

## 2. Estado actual

Contextos: `swift test` local en paralelo (Swift Testing), `swift test --sanitize=thread` local, CI con `--no-parallel` y sin TSan, la app empaquetada (`scripts/bundle.sh release`, sintetizador y reconocedor de idioma reales), modo clasico frente a modo realtime.

### Hallazgo central, verificado con sonda en Swift 6.3.3

- La hipotesis de la orquestacion es cierta solo a medias: el Task `[weak self]` no hereda el actor, pero aunque lo heredara, `submit` correria igual fuera del actor porque es un metodo async no aislado de una clase (SE-0338) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- La carrera reportada no es submit contra el actor: es entre dos tareas no estructuradas que comparten el mismo `ClassicRuntime`, ambas fuera del actor [repo:docs/research/evidence/tsan-classicruntime-submit-speak.txt:20]
- El reporte muestra las dos pilas en hilos de GCD y la memoria en el bloque de 648 bytes del runtime creado por `VoiceSession.init` [repo:docs/research/evidence/tsan-classicruntime-submit-speak.txt:13]

### Quien crea las tareas

- `ClassicRuntime` es `final class @unchecked Sendable` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:6]
- Su comentario afirma que los puertos estan "safely isolated by exclusive access in VoiceSession", y la sonda muestra que no es asi [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:5]
- `startClassicTurn` cancela el turno anterior y crea uno nuevo sin esperar a que el anterior termine [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- El turno corre en `Task { [weak self] in ... await self.classic.submit(...) }` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:22]
- `.submitUtterance` del bucle de turnos llama a `startClassicTurn` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:68]
- El aviso de fin de un job corre en otra tarea, `announceTask = Task { await classic.announce(...) }`, que no captura `self` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:74]
- Una pulsacion nueva llama a `cutAnnouncement` en `beginHold`, que cancela `announceTask` sin esperarlo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:62]
- `cutAnnouncement` hace `announceTask?.cancel()` y suelta la referencia [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:80]
- `announce` escribe `cardThisTurn` del runtime antes de hablar [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:15]
- `announce` llama a `say`, que termina en `speak`, el lector de `cardThisTurn` del reporte [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:18]
- `speak` lee `cardThisTurn` sin lock y no comprueba cancelacion antes de leer [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:138]

### Donde se cancela (corte por pulsacion)

- `.cancelAgentOutput` en modo clasico llama a `cancelClassicTurn` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:74]
- `cancelClassicTurn` cancela `classicTurnTask`, corta el aviso y para el sintetizador [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:32]
- La cancelacion es cooperativa: `submit` la comprueba con `Task.isCancelled` dentro del bucle de rondas y antes de cada efecto [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:299]
- `take` deja de decir frases cuando el turno esta cancelado [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:247]
- `cutTurn` enhebra lo dicho y deja `steerPending = true` para el turno siguiente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:423]

### Campos mutables compartidos por `submit` y el camino de la boca, y quien los toca (ninguno esta bajo lock)

| Campo | Escritores | Lectores | Contexto de ejecucion |
|---|---|---|---|
| `cardThisTurn` | submit 285, absorb, announce | speak | tarea del turno y tarea del aviso, ambas en el executor generico [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:59] |
| `cardThisTurn` en rondas de herramientas | `absorb` lo pone en true | speak | tarea del turno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:36] |
| `effectLines` | submit 287, absorb | `sayMissingEffects` | tarea del turno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:156] |
| `unverifiedTyped` | submit 286, absorb | `act`, `actAcknowledging` | tarea del turno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:34] |
| `owedLines` | submit 288, `handleJobTool` | submit 401 | tarea del turno [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:517] |
| `turnTranscripts` | submit 224 | `cutTurn`, fin de submit, `respond` | tarea del turno vieja y nueva [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:224] |
| `steerPending` | submit 247, `cutTurn` | submit 246 | turno cortado y turno siguiente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:246] |
| `leftoverHeard` | actor en Pumps, submit 209 | submit 208 | actor y tarea del turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:387] |
| `pressedContext` | actor en fanOut, senseVoice | senseVoice | actor y tarea del turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+FanOut.swift:22] |

### Lo que SI esta bajo lock hoy en el pipeline clasico

- `ClassicEarOwnership` guarda la generacion del oido y la parada en vuelo detras de un `NSLock` [repo:Sources/CompanionServices/Voice/Classic/ClassicEarOwnership.swift:8]
- Su comentario ya dice que los metodos async de `ClassicRuntime` corren fuera del actor y que el sanitizador lo encontro (code review 2026-09-24) [repo:Sources/CompanionServices/Voice/Classic/ClassicEarOwnership.swift:4]
- `ClassicHoldAudio` protege los buffers de audio del hold con otro `NSLock` por la misma razon [repo:Sources/CompanionServices/Voice/Classic/ClassicHoldAudio.swift:10]
- `StallTimer` del primer corte usa su propio `NSLock` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:15]
- `actAcknowledging` ya evita una carrera interna: la ronda devuelve lo aprendido y se absorbe despues de que terminan los dos competidores [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:92]
- `TurnMouth` ya es estado por turno pasado como `inout`, con `budget.cardShown` dentro [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:93]

### Campos de cableado (no son parte de esta carrera)

- `parentTools`, `events`, `sensor`, `screen`, `onDelegate` y similares se asignan una vez en `VoiceSession.init` antes de crear ninguna tarea [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:253]
- `decide` se asigna desde la raiz de composicion con `attachDecision`, una vez [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Decision.swift:14]

### Tests y contextos

- `backgroundJobRuntimeTests` es un solo `@Test` que corre en secuencia todos los casos del archivo, incluidos los de `restingWithJob` [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:13]
- `restingWithJob` deja la voz en reposo con un job en curso; sus casos hacen sonar el aviso y luego pulsan [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:558]
- Un test existente lee `runtime.effectLines` y `runtime.cardThisTurn` directamente: la opcion C lo obliga a cambiar [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:551]
- `ScriptedSynth` guarda su cola tras un `NSLock`, lo que ordena (happens-before) a quien lo use y puede ocultar la carrera en un test [repo:Tests/CompanionTests/VoiceSessionFakes.swift:446]
- En CI los tests corren con `--no-parallel` y sin TSan [repo:scripts/gates.sh:245]
- El gate de TSan quedo diferido a un PR aparte por decision de Karen registrada en el brief anterior [repo:docs/research/voz-reconexion-aislamiento.md:270]
- Modo realtime: `jobAnnounce` encola el aviso para el servidor y no crea `announceTask`, asi que la carrera es solo del modo clasico [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:30]
- La regla de arquitectura dice que la cancelacion es estructurada (`Task.cancel()`), no contadores de generacion [repo:docs/ARCHITECTURE.md:79]
- B1 ya mergeado: los metodos async de RealtimeRuntime llevan `nonisolated(nonsending)` [repo:Sources/CompanionServices/Voice/Realtime/RealtimeRuntime.swift:130]
- El target es macOS 26, asi que `Mutex` (macOS 15+) esta disponible sin tocar `Package.swift` [repo:Package.swift:9]

### Sondas de este run (scratchpad de la sesion, fuera del repo)

- Sonda 1 (swiftc 6.3.3, actor con executor de cola propia): en `Task { [weak self] in }` el cuerpo corre fuera del actor; con captura fuerte de `self` corre en el actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- Sonda 1: un metodo async plano de la clase corre fuera del actor incluso llamado desde un Task aislado; uno `nonisolated(nonsending)` corre en el actor solo si el llamador esta aislado [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:200]
- Sonda 1: un Task que no captura `self` (la forma de `announceTask`) corre fuera del actor aunque llame un metodo nonsending [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:74]
- Sonda 2 (TSan, forma minima): aviso y turno en dos Task desde un actor dan la carrera 5 de 5; con `nonisolated(nonsending)` solo sigue rojo; con nonsending mas Task aislado, o con `Mutex`, queda limpio [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:285]
- Sonda 3 (copia del repo, test nuevo con fakes sin lock): aviso y turno concurrentes reproducen el reporte exacto, escritura en ClassicRuntime.swift:285 contra lectura en ClassicRuntime+Mouth.swift:138, 4 de 4 corridas [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:138]
- Sonda 3: turno cortado y turno siguiente concurrentes dan carreras en 224, 246-247 y 286-288 (turnTranscripts, steerPending y los arrays por turno) [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:224]
- Sonda 4 (copia parcheada: `cardThisTurn` movido a `TurnMouth`): la carrera aviso-turno desaparece 3 de 3, y las suites ConversationQuality, backgroundJobRuntimeTests, MouthJSON y TranscriptDebug (175 tests) pasan bajo TSan sin avisos [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:15]
- Sonda 4: las carreras entre turno cortado y turno siguiente siguen ahi, como se esperaba, porque ese parche solo movio `cardThisTurn` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:423]

## 3. Fuentes primarias

- SE-0338 (Swift 5.7): una funcion async no aislada corre en un executor generico sin actor y, al entrar, libera el actor de donde venia [doc:https://github.com/swiftlang/swift-evolution/blob/60444bd1f5a9b76b8a67f780f62dd1fb1872e670/proposals/0338-clarify-execution-non-actor-async.md#L32@swift-5.7]
- SE-0304: un Task creado dentro de una funcion de actor hereda el contexto del actor y su cierre queda aislado a el [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L482@swift-5.5]
- SE-0304: la cancelacion es cooperativa y no tiene efecto hasta que algo la comprueba [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L394@swift-5.5]
- SE-0420 (Swift 6.0): el cierre de `Task {}` hereda el aislamiento de un parametro `isolated` (incluido el `self` del actor) solo si lo captura fuertemente [doc:https://github.com/swiftlang/swift-evolution/blob/3a5614025e4877118f48e719acb71361bad54d11/proposals/0420-inheritance-of-actor-isolation.md#L214@swift-6.0]
- SE-0420: tambien hereda si captura un binding no opcional del parametro aislado; una captura `weak` no es ninguna de las dos cosas [doc:https://github.com/swiftlang/swift-evolution/blob/3a5614025e4877118f48e719acb71361bad54d11/proposals/0420-inheritance-of-actor-isolation.md#L221@swift-6.0]
- SE-0461 (Swift 6.2): una funcion `nonisolated(nonsending)` siempre corre en el actor del llamador [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L266@swift-6.2]
- SE-0461: los Task no estructurados creados en funciones no aisladas, nonsending incluidas, nunca corren en un actor salvo que se diga explicitamente [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L410@swift-6.2]
- SE-0433 (Swift 6.0): los actores intercalan tareas en cada `await`; `Mutex` es la alternativa cuando el estado debe protegerse sin pasar por un actor [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L15@swift-6.0]
- SE-0433: `withLock` es seguro en codigo async porque no hay punto de suspension dentro del cierre [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L309@swift-6.0]
- SE-0433: `Mutex` vive detras de `import Synchronization` a proposito, como marca de sincronizacion manual [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L351@swift-6.0]
- Stdlib release/6.2: `Mutex` es `~Copyable` y esta marcado `@available(SwiftStdlib 6.0, *)` [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Synchronization/Mutex/Mutex.swift#L34-L37@swift-6.2]
- Stdlib release/6.2: `SwiftStdlib 6.0` equivale a macOS 15.0 [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/utils/availability-macros.def#L46@swift-6.2]
- Stdlib Swift 6.2: los cierres de `TaskGroup.addTask` son `sending` e `@isolated(any)`, asi que no heredan el actor [doc:https://github.com/swiftlang/swift/blob/6f3099b564595b0b8075c06e472c140d2ca97d2d/stdlib/public/Concurrency/TaskGroup+addTask.swift.gyb#L43@swift-6.2]
- Clang ThreadSanitizer: el `exitcode` por defecto cuando hay un reporte es 66 y `halt_on_error` es falso por defecto [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@llvm-main-2026-09-30]
- google/sanitizers: `history_size` por defecto 2 controla cuantos accesos previos recuerda cada hilo, por eso una carrera puede no reportarse si el acceso viejo salio de la historia [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]

## 4. Implementaciones de referencia

- LiveKit Agents (LiveKit Inc., framework de agentes de voz en produccion, main activo): cada respuesta hablada es un `SpeechHandle` propio con su estado (items de chat, futuro de interrupcion), no estado global del agente [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L33-L60@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit Agents: el planificador autoriza una respuesta y espera a que termine su generacion antes de pasar a la siguiente, y salta las que ya fueron interrumpidas [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L2007-L2038@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- openai-agents-python (SDK oficial de OpenAI): `RunState` guarda el estado de una corrida y advierte que dos estados restaurados no deben reanudarse a la vez sobre la misma sesion [ref:https://github.com/openai/openai-agents-python/blob/28e9f4fca26dd1c7e679398b87182868ecfad714/src/agents/run_state.py#L790-L802@28e9f4fca26dd1c7e679398b87182868ecfad714]
- swift-async-algorithms (Apple): el canal multiproductor guarda TODO su estado mutable en un `Mutex<_StateMachine>` y solo lo toca dentro de `withLock` [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Sources/AsyncAlgorithms/MultiProducerSingleConsumerChannel/MultiProducerSingleConsumerAsyncChannel+Internal.swift#L114-L135@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- swift-concurrency-extras (Point-Free, independiente de Apple, muy usado en apps Swift): `LockIsolated` envuelve un valor mutable con un lock y lo expone solo a traves de el [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/Sources/ConcurrencyExtras/LockIsolated.swift#L3-L20@5fa253428866f2360c3754e88537f700ed2656b5]
- swift-nio (Apple) adopta `nonisolated(nonsending)` como sustituto de `isolated (any Actor)? = #isolation`, la base de B1 [ref:https://github.com/apple/swift-nio/blob/21de5f08c1a166a6dd293d0e587ad977bf8dac5d/Sources/NIOCore/AsyncAwaitSupport.swift#L25-L45@21de5f08c1a166a6dd293d0e587ad977bf8dac5d]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Confinar al actor: `nonisolated(nonsending)` en los metodos async de ClassicRuntime y Tasks que hereden el actor | Coherente con B1; sin locks; el compilador asume el aislamiento | Exige tocar `VoiceSession+Steer.swift` (captura `[weak self]`) y `VoiceSession+Announcements.swift` (Task sin `self`); no basta con nonsending solo (sonda 2); deja la intercalacion logica en cada `await` (el aviso viejo lee el flag del turno nuevo); mueve al actor el trabajo de CPU de la boca (filtro, reconocedor de idioma por frase), que compite con el pump de frames | media | No como fix de esta carrera |
| A2. Parametro `isolated (any Actor)? = #isolation` (SE-0313/0420) | Funciona desde Swift 6.0 | Mismos cambios en Steer y Announcements que A; el brief anterior ya lo descarto frente a nonsending | media | No |
| B. Locks (`Mutex` o `NSLock`) sobre todos los campos compartidos | Cambio solo en ClassicRuntime*; mismo patron que ClassicEarOwnership y ClassicHoldAudio | Cura TSan pero no la logica: el aviso viejo sigue leyendo el flag que el turno nuevo reseteo; un lock por campo no hace atomico leer-y-limpiar si no se diseña asi | baja | Solo para lo que de verdad cruza tareas |
| C1. Estado del turno en el turno: `cardThisTurn` a `TurnMouth`; `effectLines`, `unverifiedTyped`, `owedLines`, `turnTranscripts` a un valor por turno pasado `inout` | Elimina la causa: dos tareas ya no comparten lo que es de una; sin locks para eso; el aviso y el turno quedan independientes por construccion; sondeado en verde para `cardThisTurn` | Cambia firmas internas (`absorb`, `handleJobTool`, `sayMissingEffects`, `cutTurn`) y un test que lee campos del runtime | media | Recomendada |
| C1+B. C1 mas `Mutex` para los campos que si cruzan tareas: `steerPending`, `leftoverHeard`, `pressedContext`, con leer-y-limpiar atomico | Cierra todas las carreras de la tabla de la seccion 2 sin tocar Steer, Pumps, FanOut ni Package.swift (propiedades computadas conservan los nombres que usan Pumps y FanOut) | Diverge de B1 en mecanismo; `steerPending` puede seguir llegando un turno tarde si el turno cortado termina despues de que el nuevo lo leyo | media | Recomendada |
| C2. Serializar turnos: el turno nuevo espera `previous.value` (y el aviso) antes de empezar | Ordena tambien `steerPending` y el hilo; patron de LiveKit | Toca `VoiceSession+Steer.swift`; el turno nuevo espera a que el viejo llegue a un punto de cancelacion (una herramienta lenta no cancelable lo retrasa) | media | Opcional, PR aparte coordinado |

## 6. Evidencia en contra

- Contra C1+B: B1 eligio `nonisolated(nonsending)` para RealtimeRuntime y Karen lo aprobo; elegir locks aqui da dos mecanismos para dos runtimes hermanos [repo:docs/research/voz-reconexion-aislamiento.md:9]
- Se resuelve: RealtimeRuntime se llama desde el actor y se espera ahi, mientras el turno clasico corre a proposito en su propia tarea para que una pulsacion lo pueda cortar, asi que su concurrencia con el actor es de diseño [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:4]
- Y el propio pipeline clasico ya resolvio sus dos carreras anteriores con locks y no con aislamiento [repo:Sources/CompanionServices/Voice/Classic/ClassicHoldAudio.swift:5]
- Contra C1+B: A es mas chico en lineas por metodo (una anotacion), pero no basta solo: la sonda 2 sigue roja con nonsending si el Task no hereda el actor [doc:https://github.com/swiftlang/swift-evolution/blob/fb22d3ef93429b0ef6f53f5124d75c160df400cc/proposals/0461-async-function-isolation.md#L410@swift-6.2]
- Contra A, ademas: aun con todo en el actor, las tareas se intercalan en cada `await`, asi que el aviso viejo leeria el `cardThisTurn` que el turno nuevo acaba de resetear: sin carrera de datos, con el mismo error logico [doc:https://github.com/swiftlang/swift-evolution/blob/f4c21d268a68b860dfab4cfed32357eca8249f3e/proposals/0433-mutex.md#L15@swift-6.0]
- Contra C1+B: queda abierta la carrera logica de orden de `steerPending` entre turno cortado y turno nuevo; se acepta y va a la seccion 9 como decision de Karen (C2) [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:246]
- Contra cualquier opcion basada en TSan: TSan es dinamico y depende del intercalado; un verde en una corrida no prueba ausencia de carrera [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@llvm-main-2026-09-30]
- Se mitiga con un test que fuerza el solapamiento real sin locks compartidos (seccion 7) y corre varias iteraciones; en la sonda 3 dio rojo 4 de 4 [repo:docs/research/evidence/tsan-classicruntime-submit-speak.txt:3]

## 7. Ejemplares y anti-ejemplos

- Bien hecho en este repo: `TurnMouth` ya es el estado de un turno pasado como `inout`; `cardThisTurn` encaja ahi junto a `budget.cardShown` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:86]
- Bien hecho en este repo: `actRound` devuelve lo aprendido en vez de escribir el estado del runtime desde una tarea hija [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:4]
- Estado bajo `Mutex` y tocado solo en `withLock`, como el canal de swift-async-algorithms [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Sources/AsyncAlgorithms/MultiProducerSingleConsumerChannel/MultiProducerSingleConsumerAsyncChannel+Internal.swift#L114-L135@13713a4ffdee8abd929f92568ee9462a46ae26e0]

```swift
// Forma del cruce entre tareas: leer y limpiar en un solo paso, sin await dentro.
private let crossing = Mutex(Crossing())   // steerPending, leftoverHeard, pressedContext
func takeSteer() -> Bool { crossing.withLock { s in defer { s.steerPending = false }; return s.steerPending } }
```

- Anti-ejemplo: estado de un turno guardado en el objeto que comparten dos tareas, escrito por una y leido por otra [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:15]
- Anti-ejemplo: un Task `[weak self]` dentro del actor no hereda el actor, aunque luego haga `guard let self` [doc:https://github.com/swiftlang/swift-evolution/blob/3a5614025e4877118f48e719acb71361bad54d11/proposals/0420-inheritance-of-actor-isolation.md#L214@swift-6.0]
- Anti-ejemplo: un `NSLock` al lado de un `var` deja leer el `var` sin lock; un `Mutex` guarda el valor dentro y no lo permite [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Synchronization/Mutex/Mutex.swift#L34-L37@swift-6.2]
- Test en rojo, forma sondeada (archivo nuevo de test, no toca archivos de la otra sesion): fakes sin lock y dos tareas sueltas, como las crea `VoiceSession` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:74]

```swift
// SilentSynth y StatelessChat: sin locks, o el lock ordena las tareas y TSan no ve nada.
// languageRecognizer = FakeRecognizer() para no pasar por NaturalLanguage.
@Test func aNoticeAndATurnRunApart() async {
    for _ in 0 ..< 50 {
        let runtime = raceRig()   // chat que devuelve ~200 frases
        let notice = Task.detached { await runtime.announce(JobAnnouncement(
            goal: "restaurantes", outcome: .done(result: "Hay tres."), language: .es, hasCard: true)) }
        let turn = Task.detached { await runtime.submit(config: Config(language: .es)) { _ in } }
        await notice.value; await turn.value
    }
}
@Test func aCutTurnAndTheNextRunApart() async {
    for _ in 0 ..< 20 {
        let runtime = raceRig()
        let old = Task.detached { await runtime.submit(config: Config(language: .es)) { _ in } }
        old.cancel()
        let next = Task.detached { await runtime.submit(config: Config(language: .es)) { _ in } }
        await old.value; await next.value
    }
}
```

- Oraculo: Swift Testing marca los tests como pasados aun con carrera; lo rojo es el codigo de salida distinto de cero del proceso y las lineas `WARNING: ThreadSanitizer` con marcos de ClassicRuntime [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@llvm-main-2026-09-30]
- Comando: `swift test --sanitize=thread --jobs 6 --filter ClassicRuntimeRace`, y como red de regresion las suites de voz clasica `ConversationQuality|backgroundJobRuntimeTests|MouthJSON|TranscriptDebug` bajo TSan [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:13]

## 8. Trampas

- Un fake con lock (por ejemplo `ScriptedSynth` o `ScriptedChat` con `@Guarded`) crea happens-before entre las dos tareas y el test queda verde con el bug: la primera version de la sonda 3 con esos fakes no reporto nada [repo:Tests/CompanionTests/VoiceSessionFakes.swift:446]
- TSan suprime reportes repetidos de una misma direccion; `steerPending` y `cardThisTurn` son bytes vecinos y en la sonda un reporte de uno oculto el del otro: arreglar uno puede destapar el siguiente [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:56]
- Los dos tests de la sonda corriendo en paralelo en el mismo proceso tambien comparten esa supresion; conviene filtrarlos por separado al diagnosticar [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]
- Si se elige A, un test que llame al runtime desde `Task.detached` o `addTask` no prueba nada: nonsending corre en el executor del llamador, y ahi no hay actor; el test tendria que pasar por `VoiceSession` [doc:https://github.com/swiftlang/swift/blob/6f3099b564595b0b8075c06e472c140d2ca97d2d/stdlib/public/Concurrency/TaskGroup+addTask.swift.gyb#L43@swift-6.2]
- Si se elige A, `announceTask` tambien debe heredar el actor; hoy no captura `self` y la sonda 1 muestra que ese Task corre fuera del actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:73]
- `withLock` no puede contener un `await`; `senseVoice` hoy lee `pressedContext` y luego hace `await pressedContext.value`: la toma tiene que ser un paso sincrono separado del await [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:482]
- `leftoverHeard` y `pressedContext` se asignan desde `VoiceSession+Pumps.swift` y `VoiceSession+FanOut.swift`; para no tocarlos, el fix debe conservar esos nombres como propiedades computadas con `get`/`set` sobre el `Mutex` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:387]
- Contexto `swift test`: el reporte original aparecio dentro de `backgroundJobRuntimeTests`, que no es el unico test que ejercita la ruta; sin TSan esa suite queda verde con o sin fix [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:13]
- Contexto TSan: es dinamico; el rojo del test nuevo es de alta probabilidad (4 de 4) y no determinista en sentido estricto [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@llvm-main-2026-09-30]
- Contexto CI `--no-parallel` sin TSan: el test nuevo pasa siempre en CI y solo protege cuando alguien corre TSan local, hasta que exista el gate diferido [repo:scripts/gates.sh:245]
- Contexto app empaquetada: con el sintetizador y `NaturalLanguageRecognizer` reales las dos tareas duran mas y el solapamiento es mas probable que en los tests; la recomendacion no cambia nada de ese camino salvo donde vive el estado [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:93]
- Contexto modo realtime: el aviso no usa `ClassicRuntime.announce`, asi que el fix no cambia ese modo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:30]
- Contexto modo clasico: el corte por pulsacion sigue igual con C1+B porque no cambia quien crea ni quien cancela `classicTurnTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:32]
- El comentario de `ClassicRuntime` que habla de acceso exclusivo en VoiceSession es falso hoy y debe corregirse junto con el fix, o el siguiente lector vuelve a confiar en el [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:4]
- El test que lee `runtime.effectLines` y `runtime.cardThisTurn` debe reescribirse contra el valor por turno, sin perder su intencion (la ronda no escribe estado desde la tarea hija) [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:551]

## 9. Incertidumbre

- ASSUMPTION: con C1+B completo, `aCutTurnAndTheNextRunApart` queda limpio bajo TSan. prueba: aplicar el fix entero, correr `swift test --sanitize=thread --jobs 6 --filter ClassicRuntimeRace` tres veces y ver salida 0 sin `WARNING: ThreadSanitizer`
- ASSUMPTION: el orden de `steerPending` entre turno cortado y turno nuevo casi nunca se invierte en la app, porque el turno nuevo espera primero el final del oido (hasta 0.5 s). prueba: test con un `spokenSoFar` del sintetizador que tarda 1 s en el turno cortado y afirmar si la nota `<steer>` llega al turno siguiente o al de despues
- ASSUMPTION: no hay otros lectores concurrentes de campos de cableado (`decide`, `transcripts`) porque se asignan una vez al arrancar antes de la primera pulsacion. prueba: TSan sobre la app empaquetada, pulsar en los primeros segundos tras abrirla
- ASSUMPTION: el compilador de CI acepta `import Synchronization` y `Mutex` igual que el local 6.3.3 (la sonda 2 compilo `Mutex` sin tocar Package.swift). prueba: el paso "Show toolchain" del primer run de CI con el fix y que `gates.sh` compile
- ASSUMPTION: mover el CPU de la boca al actor (opcion A) retrasaria el pump de frames; no se midio. prueba: solo si se elige A, medir el intervalo entre frames del mic durante una respuesta larga con y sin A
- [NEEDS CLARIFICATION: D1. La recomendacion es C1+B (estado del turno en el turno, `Mutex` para lo que cruza tareas), que diverge del mecanismo de B1. Karen elige si acepta esa divergencia o prefiere A, que exige tocar `VoiceSession+Steer.swift` y `VoiceSession+Announcements.swift`.]
- [NEEDS CLARIFICATION: D2. Serializar turnos (C2, el turno nuevo espera al cortado) cierra el orden de `steerPending` pero toca `VoiceSession+Steer.swift`, que la otra sesion pide coordinar. Karen decide si va en este PR, en uno aparte coordinado, o no va.]
- [NEEDS CLARIFICATION: Mutex frente a NSLock. El repo usa `NSLock` en 57 sitios de Services y `Mutex` en ninguno; `Mutex` impide por tipo leer sin lock. Karen elige si este fix estrena `Mutex` o sigue la convencion de ClassicEarOwnership.]

## 10. Checklist de estandar

- [ ] `cardThisTurn`, `effectLines`, `unverifiedTyped`, `owedLines` y `turnTranscripts` dejan de ser propiedades del runtime y viven en un valor por turno (TurnMouth o un estado de turno pasado `inout`)
- [ ] `announce` fija la tarjeta en su propio `TurnMouth` y no escribe nada del runtime
- [ ] `steerPending`, `leftoverHeard` y `pressedContext` viven en un unico `Mutex` (o lock unico) y se leen-y-limpian en un solo paso, sin `await` dentro del lock
- [ ] `VoiceSession+Pumps.swift`, `VoiceSession+FanOut.swift`, `VoiceSession+Steer.swift`, `RealtimeRuntime.swift` y `Package.swift` no cambian
- [ ] Un archivo de test nuevo con `aNoticeAndATurnRunApart` y `aCutTurnAndTheNextRunApart`, con fakes sin lock, sale distinto de cero bajo TSan antes del fix (registrar la salida en el PR)
- [ ] El mismo filtro sale 0 y sin `WARNING: ThreadSanitizer` en tres corridas despues del fix
- [ ] Las suites `ConversationQuality|backgroundJobRuntimeTests|MouthJSON|TranscriptDebug` pasan bajo TSan sin avisos despues del fix
- [ ] `swift test` normal (y `scripts/gates.sh`) sigue verde
- [ ] Una pulsacion a mitad de turno sigue cortando: el test existente de corte del turno clasico sigue verde sin cambios
- [ ] El comentario de `ClassicRuntime` sobre "exclusive access in VoiceSession" se corrige para decir donde corre de verdad

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0338 ejecucion de async no aisladas | Swift Evolution | Swift 5.7, 60444bd | 2026-09-30 | high |
| 2 | SE-0304 structured concurrency | Swift Evolution | Swift 5.5, 3055902 | 2026-09-30 | high |
| 3 | SE-0420 herencia de aislamiento | Swift Evolution | Swift 6.0, 3a56140 | 2026-09-30 | high |
| 4 | SE-0461 nonisolated(nonsending) | Swift Evolution | Swift 6.2, fb22d3e | 2026-09-30 | high |
| 5 | SE-0433 Mutex | Swift Evolution | Swift 6.0, f4c21d2 | 2026-09-30 | high |
| 6 | Mutex.swift y availability-macros.def | swiftlang/swift | release/6.2, 635acfa | 2026-09-30 | high |
| 7 | TaskGroup+addTask.swift.gyb | swiftlang/swift | release/6.2, 6f3099b | 2026-09-30 | high |
| 8 | ThreadSanitizer | LLVM/Clang | main, sin version | 2026-09-30 | high |
| 9 | ThreadSanitizerFlags | google/sanitizers wiki | sin version | 2026-09-30 | medium |
| 10 | LiveKit Agents speech_handle.py y agent_activity.py | LiveKit | d251b89 | 2026-09-30 | high |
| 11 | openai-agents-python run_state.py | OpenAI | 28e9f4f | 2026-09-30 | medium |
| 12 | swift-async-algorithms MPSC channel internal | Apple | 13713a4 | 2026-09-30 | high |
| 13 | swift-concurrency-extras LockIsolated.swift | Point-Free | 5fa2534 | 2026-09-30 | high |
| 14 | swift-nio AsyncAwaitSupport.swift | Apple | 21de5f0 | 2026-09-30 | high |
| 15 | Sondas 1-4 de este run (swiftc 6.3.3, swift test --sanitize=thread sobre copia del repo) | propio | 2026-09-30 | 2026-09-30 | high |
