# Reference Brief: serializar los turnos clasicos (el turno nuevo espera al cortado)

Slug: classic-turn-serialize | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Decision de Karen (2026-10-01): Q1 = R1, una espera inyectable de 2 s para toda causa de corte; Q2 = P1' (compuerta de generacion en cutTurn que descarta las escrituras tardias del turno atascado), cubierta por un ADR corto junto con holdGeneration, armGeneration y realtimeGeneration; Q3 aceptado: un turno cortado antes de que sus palabras lleguen al modelo no deja rastro (pulsacion, barge-in y stop). [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Seguimiento (2026-10-01): la pregunta de Karen sobre plazo, vencimiento y rastro del turno cortado (si deben variar segun la causa: pulsacion, red, herramienta atascada o stop) se responde en `docs/research/interrupciones-por-causa.md`.

El brief `classic-runtime-submit-speak` ya decidio D2 (serializar turnos clasicos en un PR aparte) y la opcion C2 de su seccion 5 (el turno nuevo espera `previous.value` antes de empezar, patron de LiveKit). Este brief no repite el analisis de la carrera de datos; responde solo lo que aquel dejo abierto. Tras #68 (estado por turno en `TurnMouth`, y `steerPending`, `leftoverHeard`, `pressedContext` bajo un `Mutex`) queda una carrera de ORDEN: el `cutTurn` del turno cortado pone `steerPending = true` despues de que el turno nuevo ya lo tomo, y la nota de corte llega un turno tarde.

Decisiones:

- Q1. Si la espera del turno nuevo lleva plazo, y que pasa al vencer: empezar igual, perder la nota, u otra cosa. Cuanto tarda hoy un turno cortado en llegar a su primer punto de cancelacion, a mitad de stream y a mitad de herramienta.
- Q2. Si el turno nuevo debe esperar tambien `announceTask` o basta con cancelarlo.
- Q3. Forma: cadena de tareas, cola serie o AsyncStream de turnos, o candado de turno en el actor.
- Q4. Latencia anadida a la respuesta siguiente en el caso comun.
- Q5. Test en rojo determinista.

## 2. Estado actual

Contextos: app empaquetada en modo clasico (sintetizador `SpeechSynthesis` y oido reales), app en modo realtime, `swift test` local (Swift Testing, paralelo), CI (`swift test --no-parallel`, sin TSan), `swift test --sanitize=thread` local, sondas de este run en una copia del repo en el scratchpad.

### Decision previa que este brief hereda

- Karen decidio D2: serializar turnos en un PR aparte despues de C1+B [repo:docs/research/classic-runtime-submit-speak.md:7]
- C2 se describio como "el turno nuevo espera previous.value (y el aviso)", con el coste de que una herramienta lenta no cancelable lo retrasa [repo:docs/research/classic-runtime-submit-speak.md:143]
- El test de carrera de #68 acepta a proposito que la nota llegue tarde: "the note rode once, or is still pending" [repo:Tests/CompanionTests/ClassicRuntimeRaceTests.swift:217]

### Quien crea, corta y espera el turno

- `startClassicTurn` cancela el turno anterior y crea el nuevo sin esperarlo [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- El turno corre en `Task { [weak self] in ... }`, fuera del actor [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- `cancelClassicTurn` cancela y ademas suelta la referencia (`classicTurnTask = nil`) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:33]
- `awaitClassicTurn` (costura de test) espera solo `classicTurnTask?.value` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:43]
- `.submitUtterance` llama a `startClassicTurn`; `.cancelAgentOutput` en clasico llama a `cancelClassicTurn` y en realtime a `realtime.cancelAgent()` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:71]
- Una pulsacion entra por `beginHold`, que primero corta el aviso [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:62]
- Despues aplica `.holdPressed`, que emite `.cancelAgentOutput` y corta el turno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:104]
- Y despues lanza `fanOut()`, que deja un `pressedContext` nuevo para la pulsacion nueva [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:117]
- `startClassicTurn` es sincrona en el actor: leer, cancelar y reasignar `classicTurnTask` ocurre sin ningun `await` en medio [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:16]
- Teardown no toca `classicTurnTask` ni `announceTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Teardown.swift:10]

### Orden dentro de `submit` (lo que el turno nuevo comparte con el cortado)

- `submit` toma primero las palabras: `takeLeftoverHeard()` o `finalTranscript()` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:238]
- El oido real espera hasta 0.5 s su final al parar [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:127]
- En clasico cada frame del mic va al oido mientras no se pare, este o no apretada la tecla [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:238]
- La cola de 0.3 s tras soltar existe a proposito para la ultima silaba: el oido despues de soltar esta acotado por diseno [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:184]
- La nota se consume en `takeSteerPending()` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:277]
- Luego el router opcional (`decide`) [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:278]
- Luego `senseVoice`, que toma `pressedContext` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:508]
- Luego `thread.appendUser(heard, ...)` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:291]
- El primer `.firstSentence` emite `.beginSpeechStream` [repo:Sources/CompanionCore/Session/TurnMachine.swift:347]
- `.beginSpeechStream` llama a `synthesizer.begin()` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:88]
- `SpeechSynthesis.begin()` hace `halt(resetSpoken: true)`: borra lo dicho y reabre la cola [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:143]
- `cutTurn` lee `synthesizer.spokenSoFar()`, enhebra el parcial y al final pone `steerPending = true` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:450]
- `spokenSoFar` devuelve lo que el sintetizador lleva dicho desde su ultimo `begin` [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:136]
- Entre `onHeard` y el bucle del stream no hay ningun `Task.isCancelled`: un turno cortado mientras su oido terminaba sigue por `decide`, `senseVoice` y `appendUser` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:258]

### Puntos de cancelacion del turno cortado (Q1)

- A mitad de stream: el bucle comprueba `Task.isCancelled` en cada evento [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:326]
- Y despues del stream [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:365]
- `take` corta entre frases [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:260]
- Cancelar el stream de `mouthEvents` cancela su reenvio y el temporizador [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:63]
- Los proveedores de chat reales cancelan su peticion al terminar el stream [repo:Sources/CompanionServices/Chat/ChatProviderClient.swift:91]
- A mitad de herramienta: `actRound` solo mira la cancelacion ENTRE llamadas; la llamada en curso a `parentTools.execute` no se interrumpe [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Act.swift:58]
- `actAcknowledging` envuelve la ronda en un `withTaskGroup`, que no termina hasta que acaba `actRound` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:70]
- Despues de la ronda hay un punto de cancelacion explicito [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:413]
- La hoja de aprobacion si es cancelable (`withTaskCancellationHandler`) [repo:Sources/CompanionServices/Approvals/Approvals.swift:44]
- `find_places` "cerca de mi" pide la ubicacion con `prompting: true` [repo:Sources/CompanionServices/Tools/NativeToolRunner.swift:338]
- Esa ubicacion espera permiso hasta 30 s, fix hasta 10 s y geocodificacion hasta 10 s, con continuaciones que no miran la cancelacion [repo:Sources/CompanionServices/Perception/CoreLocationCity.swift:67]
- `open_app` espera a `workspace.openApplication`, sin plazo propio [repo:Sources/CompanionServices/Tools/ParentToolRunner.swift:201]
- El router local llama `gate.plan` dentro de `decide`; no se comprobo si es cancelable [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Decision.swift:50]

### El aviso de un job (Q2)

- `announceTask = Task { await classic.announce(...) }` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:74]
- `cutAnnouncement` cancela y suelta la referencia [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:81]
- `announce` usa su propio `TurnMouth` desde #68 [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:15]
- El resumen del aviso nunca se enhebra en el hilo [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:28]
- `announce` no toca `steerPending` ni `thread`; solo el sintetizador y el chat sin herramientas [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:33]
- `announce` llama `synthesizer.begin()` y dice la linea fija sin mirar antes la cancelacion [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:12]
- `enqueue` descarta todo mientras el sintetizador esta parado, y `begin()` lo reabre [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:157]
- En realtime el aviso va al servidor y no crea `announceTask` [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift:30]

### Reglas y tests que condicionan la forma

- Regla de arquitectura: la cancelacion es estructurada (`Task.cancel()`), no contadores de generacion [repo:docs/ARCHITECTURE.md:79]
- Las esperas del runtime ya son inyectables para tests (`firstCutWait`, `slowToolWait`) [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:120]
- `GatedParentTools.execute` espera en una continuacion que ignora la cancelacion: modela la herramienta lenta no cancelable [repo:Tests/CompanionTests/SteerTests.swift:359]
- `makeVoiceHarness` acepta `parentTools`, `sensor` y `key: nil` (clasico) [repo:Tests/CompanionTests/VoiceSessionFakes.swift:31]
- `ScriptedSynth.spokenSoFar` devuelve `spoken`, fijable desde el test [repo:Tests/CompanionTests/VoiceSessionFakes.swift:455]
- `awaitClassicTurn` se usa en 24 sitios de test, por ejemplo [repo:Tests/CompanionTests/BackgroundJobRuntimeTests.swift:683]
- En CI los tests corren con `--no-parallel` [repo:scripts/gates.sh:266]

### Sondas de este run (scratchpad, fuera del repo; swiftc 6.3.3)

- Sonda A1: un waiter cancelado sobre `previous.value` vuelve cuando `previous` termina (305 ms y 301 ms con `previous` sordo 300 ms), no al cancelarse [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:43]
- Sonda A2: un "timeout" de 50 ms con `withTaskGroup` (un hijo espera `previous.value`, otro duerme) vuelve a los 304 ms: no acota nada [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Ack.swift:70]
- Sonda A3: una carrera no estructurada que reanuda una continuacion una sola vez vuelve a los 50-55 ms [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:20]
- Sonda A4: cabeza atascada 200 ms y cinco arranques cada 10 ms con la cadena: solo corren la cabeza y el ultimo (`[0, 5]`), todo termina a los 207-211 ms [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- Sonda A5: 200 arranques encadenados con la cabeza ya terminada: peor caso 0 ms entre arranque y fin [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- Sonda B (copia del repo en dfd3aeb, test nuevo a nivel `VoiceSession`): con el codigo de hoy, 3 de 3 rojo; el turno 2 llega al chat con el turno 1 bloqueado, sin nota, y el hilo queda `user:abre Safari, user:mejor Notes, assistant:Vale, Notes., assistant:Abro Safari.` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:447]
- Sonda C (misma copia con la cadena de la seccion 7, sin plazo): 3 de 3 verde en 1.02 s, hilo en orden `user, assistant parcial, user, assistant` y nota en el turno 2 [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:277]
- Sonda C: la suite completa (1639 tests) pasa con la cadena; el unico fallo, `packageContents21cTests`, es del entorno (la copia no tiene `.git`) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:31]

## 3. Fuentes primarias

- Stdlib Swift 6.2: leer `value` de una `Task` que no lanza "espera a que termine"; no hay vuelta temprana por cancelacion del que espera [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/Task.swift#L242-L249@swift-6.2]
- Stdlib Swift 6.2: cancelar no detiene funciones que no miran la cancelacion; corren hasta el final [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/Task.swift#L209-L216@swift-6.2]
- SE-0304: la cancelacion es cooperativa y no tiene efecto hasta que algo la comprueba [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L394@swift-5.5]
- SE-0304: un hijo de un grupo no sobrevive a su ambito; si no termino, se espera implicitamente al salir [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L286-L289@swift-5.5]
- Stdlib Swift 6.2: si se cancela la tarea que itera un `AsyncThrowingStream` mientras `next()` espera, el stream termina y `next()` devuelve nil [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/AsyncThrowingStream.swift#L412-L415@swift-6.2]
- Stdlib Swift 6.2: en una tarea ya cancelada, el manejador de `withTaskCancellationHandler` corre antes de la operacion [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/TaskCancellation.swift#L44-L46@swift-6.2]
- Python asyncio (contraste con las referencias en Python): `wait_for` cancela lo esperado al vencer, y `Task.cancel` inyecta `CancelledError` en el siguiente ciclo del bucle [doc:https://docs.python.org/3/library/asyncio-task.html@python-3.14]

## 4. Implementaciones de referencia

- LiveKit Agents (LiveKit Inc., framework de agentes de voz en produccion, main activo el 2026-09-30): al cerrar un turno de usuario, interrumpe la respuesta en curso y la espera (`await current_speech.interrupt(...)`) antes de generar la siguiente [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L2774-L2786@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: esperar un `SpeechHandle` es esperar a que termine su reproduccion [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L257-L262@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: la espera tras interrumpir tiene plazo, `INTERRUPTION_TIMEOUT = 5.0` s [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L16@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: al vencer, registra un error, cancela las tareas de la respuesta y la da por terminada para que siga la siguiente [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L284-L304@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: el planificador salta las respuestas ya interrumpidas en cola y espera la generacion de cada una antes de la siguiente [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L2007-L2038@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- LiveKit: `wait_if_not_interrupted` espera unos futuros salvo que llegue la interrupcion, sin cancelarlos (los envuelve en `shield`) [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L274-L282@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Pipecat (Daily, framework de agentes de voz, main activo el 2026-10-01): `cancel_task` cancela y espera la tarea con plazo opcional, y al vencer solo registra un aviso y sigue [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/utils/asyncio/task_manager.py#L246-L254@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- Pipecat: el plazo por defecto es 1 s, "para evitar congelaciones de librerias que se tragan CancelledError" [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/utils/base_object.py#L154-L159@da37523d8692f13649ccf1b3a90ccc223a17d69b]
- groue/Semaphore (Gwendal Roue, autor de GRDB; 630 estrellas, ultimo commit 2024-07): semaforo async en Swift con `waitUnlessCancelled`, la forma de un candado de turno cuya espera si se puede cancelar [ref:https://github.com/groue/Semaphore/blob/2543679282aa6f6c8ecf2138acd613ed20790bc2/Sources/Semaphore/AsyncSemaphore.swift#L141-L149@2543679282aa6f6c8ecf2138acd613ed20790bc2]

## 5. Opciones

Forma (Q3):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| F1. Cadena con espera al inicio de la tarea: `Task { await previous?.value; ...; submit }` | Solo toca `VoiceSession+Steer.swift`; ultimo gana por construccion (sonda A4) | Retrasa `finalTranscript`: mientras espera a una herramienta atascada el oido sigue oyendo despues de soltar, y esas palabras entran en la frase | baja | No |
| F2. Cadena con la espera DENTRO de `submit`, despues de tomar las palabras y antes de `takeSteerPending` (parametro `after previous`) | El oido para a su hora; la espera se solapa con el final del oido (hasta 0.5 s); ordena nota, hilo y sintetizador; un turno cortado durante su oido sale ahi mismo antes de `decide`/`senseVoice`; sondeada: rojo a verde y 1639 tests verdes | Cambia la firma de `submit` y toca dos archivos; la espera en si no es cancelable (sonda A1) | baja-media | Recomendada |
| F3. Cola serie o AsyncStream de turnos con un consumidor de larga vida | Patron del planificador de LiveKit | Nueva tarea de larga vida que Teardown no conoce; hay que saltar peticiones viejas a mano; sigue haciendo falta el handle para cancelar | media-alta | No |
| F4. Candado de turno en el actor (semaforo async) | Espera cancelable (`waitUnlessCancelled`) | FIFO, no "ultimo gana"; un `return` temprano sin liberar (submit tiene mas de 12) bloquea para siempre; dependencia nueva o codigo propio | media | No |

Plazo y vencimiento (Q1):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| P0. Sin plazo | Orden siempre correcto; lo mas simple | Silencio hasta 50 s si el turno cortado esta en `find_places` cerca de mi | baja | No por defecto |
| P1. Plazo y, al vencer, empezar igual y registrar | Lo hacen LiveKit (5 s) y Pipecat (1 s) | En Swift el viejo sigue vivo: su `cutTurn` tardio enhebra fuera de orden, deja la nota para el turno de despues, y lee `spokenSoFar` del turno NUEVO (tras su `begin`) | media | Base recomendada |
| P2. P1 mas nota sacada del handle: al vencer, el turno nuevo marca `interrupted` el mismo porque su antecesor fue cortado | La nota llega a tiempo aunque venza | El `cutTurn` tardio vuelve a poner `steerPending`: dos notas, salvo que el flag deje de existir y la nota viaje como dato del antecesor | media | A decidir por Karen |
| P3. Al vencer, perder la nota | Simple | El modelo repite lo cortado: lo que 15b-11 queria evitar | baja | No |

Aviso (Q2):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| N1. Cancelar el aviso, no esperarlo | `announce` no toca hilo ni nota; llega a un punto de cancelacion en milisegundos (chat cancelable, sin herramientas) | Un `begin`/`enqueue` tardio del aviso cancelado puede sonar; carrera aviso contra `stop`, no contra el turno | baja | Recomendada |
| N2. Esperar tambien `announceTask` | Cierra el `enqueue` tardio contra el `begin` del turno nuevo | Hay que conservar el handle en `cutAnnouncement`; no arregla la carrera aviso contra `stop`, que ocurre durante el hold | baja-media | Opcional |

## 6. Evidencia en contra

- Lo mas fuerte contra F2: la espera de `previous.value` no se puede cancelar, asi que una tercera pulsacion no libera al turno 2 que espera al 1 [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/stdlib/public/Concurrency/Task.swift#L242-L249@swift-6.2]
- Se acepta: el turno 2 cancelado sale sin efectos al despertar (`if Task.isCancelled { return }` tras la espera), y la sonda A4 muestra que solo corre el ultimo y la cadena se deshace al terminar la cabeza [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:17]
- Contra F2 sin plazo: una herramienta de ubicacion puede tener al turno cortado 50 s sin punto de cancelacion, y la respuesta siguiente esperaria eso [repo:Sources/CompanionServices/Perception/CoreLocationCity.swift:67]
- Por eso las dos referencias de voz acotan la espera (5 s y 1 s) [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L16@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Pero copiar su vencimiento no da lo mismo en Swift: en Python cancelar inyecta `CancelledError` en el siguiente `await`; en Swift el `execute` atascado sigue y su `cutTurn` tardio llega despues [doc:https://docs.python.org/3/library/asyncio-task.html@python-3.14]
- Y el `cutTurn` tardio leeria lo dicho por el turno NUEVO, porque `begin()` del nuevo borro lo dicho por el viejo [repo:Sources/CompanionServices/Voice/Mouth/SpeechSynthesis.swift:143]
- Se resuelve en parte: con P1 o P2, el vencimiento queda como camino raro y registrado; la decision de cuanto vale el plazo y que hacer con la nota es de Karen (seccion 9) [repo:docs/research/classic-runtime-submit-speak.md:7]
- Contra cualquier plazo con `withTaskGroup`: la sonda A2 vuelve a los 304 ms con un plazo de 50 ms, porque el grupo espera a su hijo [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L286-L289@swift-5.5]
- Se resuelve con una carrera no estructurada que reanuda una continuacion una sola vez (sonda A3, 50-55 ms), el equivalente de `wait_if_not_interrupted` de LiveKit [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/speech_handle.py#L274-L282@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Contra F2 frente a F1: F1 toca un solo archivo; se descarta porque deja el oido abierto despues de soltar mientras espera, y el oido de clasico recibe cada frame del mic [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:238]

## 7. Ejemplares y anti-ejemplos

- Bien hecho: interrumpir y esperar la respuesta anterior antes de la siguiente, como LiveKit en el turno de usuario [ref:https://github.com/livekit/agents/blob/d251b89e61fe5f8ba78e0b39b501d91b0856a2d0/livekit-agents/livekit/agents/voice/agent_activity.py#L2774-L2786@d251b89e61fe5f8ba78e0b39b501d91b0856a2d0]
- Forma sondeada (sonda C) de F2 sin plazo: el handle sobrevive al corte y `submit` espera justo antes de la nota [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:31]

```swift
// VoiceSession+Steer.swift
func startClassicTurn(config: Config) {
    let previous = classicTurnTask          // the cut one, kept by cancelClassicTurn
    previous?.cancel()
    ...
    classicTurnTask = Task { [weak self] in
        guard let self else { return }
        await self.classic.submit(config: config, endsHold: endsHold, pressed: pressed,
                                  after: previous) { event in await self.apply(event) }
    }
}
func cancelClassicTurn() async {
    classicTurnTask?.cancel()               // no `= nil`: the next turn waits on it
    ...
}

// ClassicRuntime.submit, after the words are in and the empty-hold branch:
await previous?.value                       // P1/P2 replace this with a bounded wait
if Task.isCancelled { return }              // a cut turn that never reached the model leaves no trace
let interrupted = takeSteerPending()
```

- Espera acotada sin grupo (sonda A3): dos tareas sueltas reanudan una continuacion una sola vez; el antecesor no se cancela ni se espera al vencer [ref:https://github.com/pipecat-ai/pipecat/blob/da37523d8692f13649ccf1b3a90ccc223a17d69b/src/pipecat/utils/asyncio/task_manager.py#L246-L254@da37523d8692f13649ccf1b3a90ccc223a17d69b]

```swift
// Shape only; the plazo comes from an injectable wait, like slowToolWait.
let once = Mutex(false)
await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
    let resume: @Sendable () -> Void = {
        if once.withLock({ fired in defer { fired = true }; return !fired }) { done.resume() }
    }
    Task { await previous.value; resume() }
    Task { await deadline(); resume() }
}
```

- Anti-ejemplo: un plazo con `withTaskGroup` alrededor de `previous.value`; el grupo espera al hijo y el plazo no corta nada (sonda A2) [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L286-L289@swift-5.5]
- Anti-ejemplo: la cadena con `cancelClassicTurn` tal como esta; al soltar el handle, el turno siguiente encuentra `nil` y no espera a nadie [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:33]
- Test en rojo (sonda B, 3 de 3 rojo hoy, 3 de 3 verde con la forma de arriba), en un archivo de test nuevo con los fakes que ya existen [repo:Tests/CompanionTests/SteerTests.swift:350]

```swift
@Test @MainActor func aCutTurnStuckInAToolStillSteersTheNextTurn() async {
    let tools = GatedParentTools()                  // execute ignores cancellation
    let h = makeVoiceHarness(key: nil, language: .es, parentTools: tools,
                             sensor: FakeContextSensor(TurnContext(source: .voice)))
    h.chat.rounds = [[.toolCalls([ToolCallRef(id: "c1", name: "open_app",
                                              arguments: #"{"name":"Safari"}"#)])],
                     [.text("Vale, Notes.")]]
    h.transcriber.stoppedText = "abre Safari"
    await h.session.hold(); await pumpUntil("1") { h.watch.latest.state == .listening }
    await h.session.release()
    await tools.waitUntilBlocked()                  // turn 1 is inside the tool
    h.synth.spoken = "Abro Safari."
    await h.session.hold(); await pumpUntil("2") { h.watch.latest.state == .listening }
    h.transcriber.stoppedText = "mejor Notes"
    await h.session.release()
    _ = await poll(1) { h.chat.histories.count >= 2 }   // today true: turn 2 ran ahead
    tools.release()                                  // only now can turn 1 reach cutTurn
    await h.session.awaitClassicTurn()
    _ = await poll(2) { h.thread.turns.contains { $0.content == "Abro Safari." } }
    let second = h.chat.histories.count >= 2 ? h.chat.histories[1].last { $0.role == .user } : nil
    #expect(second?.content.contains("<steer>") == true)
    let partial = h.thread.turns.firstIndex { $0.role == .assistant && $0.content == "Abro Safari." }
    let next = h.thread.turns.firstIndex { $0.role == .user && $0.content == "mejor Notes" }
    #expect(partial != nil && next != nil && partial! < next!)
}
// poll: like pumpUntil, but returns Bool instead of recording a failure.
```

- Por que es determinista: el gate de la herramienta solo se abre despues de mirar si el turno 2 llego al chat, asi que hoy el turno 1 no puede poner la nota antes; no depende del planificador [repo:Tests/CompanionTests/SteerTests.swift:359]
- Variante a mitad de stream (opcional): un sintetizador cuyo `spokenSoFar` espera un gate deja a `cutTurn` a medias; `RecordingSynth` y `Gate` de la suite de carrera sirven de base [repo:Tests/CompanionTests/ClassicRuntimeRaceTests.swift:48]

## 8. Trampas

- `cancelClassicTurn` pone `classicTurnTask = nil`; sin quitar eso, la cadena no encadena nada en el flujo real (pulsar corta antes de soltar) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:33]
- Al conservar el handle, `awaitClassicTurn` tras un corte espera tambien al turno cortado; un test que corte con un gate que nunca abre se colgaria (la sonda C no encontro ninguno en la suite actual) [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Steer.swift:43]
- El test de #68 que tolera la nota tardia sigue verde con la cadena porque llama a `submit` directo y sin `after`; no prueba el orden y no debe leerse como cobertura de este cambio [repo:Tests/CompanionTests/ClassicRuntimeRaceTests.swift:217]
- Esperar antes de `finalTranscript` (F1) deja el oido oyendo despues de soltar; la espera va despues de tomar las palabras [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Pumps.swift:238]
- El `if Task.isCancelled { return }` tras la espera cambia un caso de hoy: un turno cortado mientras su oido terminaba ya no enhebra sus palabras ni deja nota, y no roba el `pressedContext` de la pulsacion nueva [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:508]
- Sin ese retorno, el turno cortado durante su oido toma el `pressedContext` que `fanOut` acaba de crear para la pulsacion nueva; la cadena sola no lo evita porque ese turno corre durante el hold [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Hold.swift:117]
- Un plazo con `withTaskGroup` no acota una espera no cancelable (sonda A2) [doc:https://github.com/swiftlang/swift-evolution/blob/3055902c7da14d8d071ec926fc6c86801574cda4/proposals/0304-structured-concurrency.md#L286-L289@swift-5.5]
- Al vencer un plazo, el `cutTurn` tardio lee `spokenSoFar` despues del `begin()` del turno nuevo y enhebra como parcial lo que dijo el nuevo [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:445]
- El aviso cancelado puede llamar `synthesizer.begin()` despues del `stop()` de `cutAnnouncement` y reabrir la cola durante el hold; es una carrera aviso contra stop, previa a este cambio y fuera de su alcance [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Announce.swift:12]
- Contexto app clasica: el cambio solo actua cuando el turno anterior sigue vivo al llegar el nuevo a su nota; con corte a mitad de stream el viejo termina en milisegundos y el nuevo aun espera el oido [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:127]
- Contexto app realtime: `.cancelAgentOutput` va a `realtime.cancelAgent()` y el aviso no crea `announceTask`; nada de esto corre ahi [repo:Sources/CompanionServices/Voice/Session/VoiceSession+TurnLoop.swift:72]
- Contexto `swift test` y CI: el test nuevo es determinista por el gate y pasa igual con `--no-parallel`; su verde cuesta hasta el `poll` de 1 s, y si el plazo de P1/P2 es menor que ese `poll` el test vuelve a rojo: el plazo debe ser inyectable [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:120]
- Contexto TSan: la cadena no anade estado compartido nuevo, pero la espera acotada usa un `Mutex` y dos tareas sueltas que conviene pasar bajo `--sanitize=thread` [repo:Tests/CompanionTests/ClassicRuntimeRaceTests.swift:168]
- Teardown no cancela `classicTurnTask`; con el handle conservado, la sesion cerrada retiene el turno cortado hasta que acabe su herramienta [repo:Sources/CompanionServices/Voice/Session/VoiceSession+Teardown.swift:10]

## 9. Incertidumbre

- ASSUMPTION: la latencia anadida en el caso comun (corte a mitad de stream) es cero perceptible, porque el viejo llega a `cutTurn` en milisegundos y el nuevo aun espera la cola de 0.3 s y el final del oido. prueba: en la app empaquetada, log con marca de tiempo al entrar y salir de la espera durante 20 cortes a mitad de respuesta; esperar 0 ms en todos
- ASSUMPTION: `gate.plan` del router local no mira la cancelacion, asi que un turno cortado dentro de `decide` tarda lo que tarde el modelo local. prueba: test con un `decide` inyectado que duerme 2 s con `Task.sleep` y otro con una continuacion, cortar a los 100 ms y medir cuando vuelve `submit`
- ASSUMPTION: los turnos atascados de verdad son raros (herramientas que esperan permiso del sistema, ubicacion, apps que tardan en abrir). prueba: contar en logs de uso real cuantas esperas superan 1 s una vez instrumentada la espera
- ASSUMPTION: la cadena y la espera acotada quedan limpias bajo TSan. prueba: `swift test --sanitize=thread --jobs 6 --filter 'ClassicRuntimeRace|aCutTurnStuckInAToolStillSteersTheNextTurn|steerTests'` tres veces, salida 0 y sin `WARNING: ThreadSanitizer`
- [NEEDS CLARIFICATION: Q1 plazo. Recomendacion: plazo inyectable con valor por defecto entre 1 s (Pipecat) y 5 s (LiveKit). Karen elige el valor, o P0 (sin plazo, orden siempre correcto, silencio de hasta 50 s en el peor caso).]
- [NEEDS CLARIFICATION: Q1 vencimiento. P1 (empezar igual y registrar; la nota puede llegar un turno tarde y el parcial tardio puede ser el texto equivocado) o P2 (la nota viaja como dato del antecesor y desaparece el flag compartido; mas cambio en ClassicRuntime).]
- [NEEDS CLARIFICATION: un turno cortado antes de llegar al modelo (durante su oido) hoy enhebra sus palabras y deja nota; con F2 sale sin rastro. Karen confirma si ese es el comportamiento querido ("A cancelled hold's words belong to no one").]

## 10. Checklist de estandar

- [ ] `cancelClassicTurn` cancela `classicTurnTask` sin soltar la referencia, y `startClassicTurn` pasa el turno anterior al nuevo
- [ ] `submit` espera al turno anterior despues de tomar las palabras y antes de `takeSteerPending`, y sale sin efectos si al despertar esta cancelado
- [ ] Si hay plazo, es inyectable como `slowToolWait`, se implementa sin `withTaskGroup` y su vencimiento deja una linea en `Log.app`
- [ ] El test `aCutTurnStuckInAToolStillSteersTheNextTurn` (archivo de test nuevo) falla antes del cambio (registrar la salida en el PR) y pasa despues: nota en el turno 2 y parcial del turno 1 antes de las palabras del turno 2 en el hilo
- [ ] Un test con tres pulsaciones seguidas sobre una herramienta atascada comprueba que solo llega al chat el ultimo turno
- [ ] El modo realtime, `VoiceSession+Announcements.swift` y `Package.swift` no cambian
- [ ] `swift test` completo verde, y `ClassicRuntimeRace` mas el test nuevo limpios bajo `--sanitize=thread`
- [ ] El CHANGELOG nombra el cambio de comportamiento del turno cortado durante su oido

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Task.swift, AsyncThrowingStream.swift, TaskCancellation.swift | swiftlang/swift | release/6.2, 635acfa | 2026-10-01 | high |
| 2 | SE-0304 structured concurrency | Swift Evolution | Swift 5.5, 3055902 | 2026-10-01 | high |
| 3 | asyncio Coroutines and Tasks | Python Software Foundation | 3.14 | 2026-10-01 | high |
| 4 | LiveKit Agents agent_activity.py y speech_handle.py | LiveKit | d251b89 | 2026-10-01 | high |
| 5 | Pipecat task_manager.py y base_object.py | Daily (pipecat-ai) | da37523 | 2026-10-01 | high |
| 6 | groue/Semaphore AsyncSemaphore.swift | Gwendal Roue | 2543679 | 2026-10-01 | medium |
| 7 | Brief classic-runtime-submit-speak (D2 y C2) | propio | 2026-09-30 | 2026-10-01 | high |
| 8 | Sondas A1-A5 (swiftc 6.3.3) y B-C (copia del repo en dfd3aeb, swift test) | propio | 2026-10-01 | 2026-10-01 | high |
