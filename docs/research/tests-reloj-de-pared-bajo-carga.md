# Reference Brief: dos tests con tope de reloj de pared que caen bajo carga (DecisionGate y BrowserChannel)

Slug: tests-reloj-de-pared-bajo-carga | Nivel: quick | Fecha: 2026-10-02 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-02 ESCALATE

## 1. Pregunta y decisiones abiertas

Cambio: sacar el reloj de pared de dos tests de `Tests/CompanionServicesTests` que fallan en toda corrida completa de `swift test` en esta Mac con load average ~57 y pasan siempre sueltos (`docs/inventario-flakes.md`, filas 40 y 41, familia "reloj"). Solo tests; ningun cambio de producto en este brief salvo que Karen elija una opcion que lo pida.

Extiende `tests-orden-no-prometido` y `tests-espera-sin-hilo` (APROBADOS): esperar el estado observable, no un proxy de tiempo.

Test 1, `dm1cGateTimesOutWithinBudgetWhenTheProviderIsSlow` (`DecisionGateTests.swift:210`, cae en `:227`, `elapsed < 1`; bajo carga 1,48 a 5,26 s). Preguntas: que espera el gate despues de vencer el budget; si el tope de 1 s mide la garantia del producto o el scheduling del test; como se afirma "vuelve por el budget" sin umbral de reloj; y si la garantia del producto se sostiene bajo carga (bug de producto o no).

Test 2, `aHelloInsideTheDeadlineIsNotClosedLater` (`BrowserChannelTests.swift:163`, cae en `:169`, la PREMISA `Date() - started < 1` con `helloDeadline` de 1 s). Pregunta: como probar "una sesion autenticada sobrevive al timer del hello" sin depender de que el hello llegue dentro de una ventana de 1 s de reloj de pared.

Decisiones: (a) forma del test 1; (b) forma del test 2; (c) si se abre aparte un cambio de producto para que `DecisionGate.plan` no espere al perdedor (forma de `ScreenSight.race`), que es una decision de Karen, no de este arreglo.

Respuesta corta. Test 1: familia reloj, con espera estructurada: tras el budget, el gate espera a que el proveedor lento observe la cancelacion y termine, y eso pide dos o tres saltos mas de planificacion en un pool hambriento; el tope de 1 s mide scheduling, no la garantia. Recomendado: proveedor que solo termina si lo cancelan, afirmar el resultado `.timedOut` y que el proveedor vio la cancelacion, sin umbral de tiempo. Test 2: familia reloj; la premisa de 1 s es redundante, porque la respuesta `ok:true` del hello ya prueba que la autenticacion corrio antes de cualquier cierre por deadline. Recomendado: borrar la premisa de tiempo y afirmar la premisa observable (`ok:true` y `presence.connected`).

## 2. Estado actual

- `DecisionGate.plan` lanza el trabajo (N1 y N2) en un `Task` no estructurado [repo:Sources/CompanionServices/Decision/DecisionGate.swift:98]
- Y lo corre contra el budget con `race`, devolviendo `.passThrough(.timedOut)` si gana el reloj [repo:Sources/CompanionServices/Decision/DecisionGate.swift:103]
- El comentario promete que un proveedor lento "never blocks the turn — it just loses the race" [repo:Sources/CompanionServices/Decision/DecisionGate.swift:90]
- `race` usa `withTaskGroup`; el primer hijo solo hace `await task.value` [repo:Sources/CompanionServices/Decision/DecisionGate.swift:274]
- El segundo hijo duerme `wait` con `Task.sleep` y devuelve nil [repo:Sources/CompanionServices/Decision/DecisionGate.swift:277]
- Al salir del cuerpo, el `defer` cancela el grupo y el `Task` de trabajo [repo:Sources/CompanionServices/Decision/DecisionGate.swift:283]
- El cuerpo devuelve el primer valor que llega del grupo [repo:Sources/CompanionServices/Decision/DecisionGate.swift:287]
- `Plan.compose` pregunta al proveedor dos veces seguidas, adelante y al reves [repo:Sources/CompanionCore/Decision/Plan.swift:208]
- Si alguna de las dos es nil devuelve un plan `.arbitrate` [repo:Sources/CompanionCore/Decision/Plan.swift:211]
- Un `.arbitrate` hace que `route` llame al arbitro antes de terminar [repo:Sources/CompanionServices/Decision/DecisionGate.swift:218]
- El proveedor del test duerme 5 s con `try? await Task.sleep` y devuelve nil [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:213]
- El test arma el gate con budget de 80 ms [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:222]
- Y exige `.timedOut` y `elapsed < 1` medido con `Date()` alrededor de `plan` [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:227]
- En la app, el proveedor es `OllamaDecisionProvider` [repo:Sources/CompanionApp/CompanionMainVoice.swift:79]
- Con `PassThroughArbiter` como arbitro [repo:Sources/CompanionApp/CompanionMainVoice.swift:84]
- Y el budget sale de la config [repo:Sources/CompanionApp/CompanionMainVoice.swift:93]
- El budget por defecto es 2 s, con la meta "commit→decision < 1.5s" [repo:Sources/CompanionCore/Platform/Config.swift:297]
- `OllamaDecisionProvider` espera la respuesta HTTP con `try await transport.data` [repo:Sources/CompanionServices/Decision/OllamaDecisionProvider.swift:51]
- El transporte llama a `URLSession.data(for:)` async [repo:Sources/CompanionServices/Chat/ChatTransport.swift:56]
- `ScreenSight.race` ya documenta en el repo el mismo problema: `withTaskGroup` espera a todo hijo y un hijo que solo espera `task.value` no nota la cancelacion [repo:Sources/CompanionServices/Perception/ScreenSight.swift:256]
- Y lo resuelve con una continuacion que reanuda el primero que llega, sin esperar al perdedor [repo:Sources/CompanionServices/Perception/ScreenSight.swift:262]
- `CompanionServices` declara su propio protocolo `Clock`, que tapa al `Clock` de la libreria estandar dentro del modulo [repo:Sources/CompanionServices/Approvals/Approvals.swift:4]
- `TestGate.wait` usa `withCheckedContinuation` sin manejador de cancelacion [repo:Tests/CompanionTestKit/TestKitFakes.swift:19]
- `BrowserChannel.attach` arranca el timer del hello como `Task` que duerme `helloDeadline` y luego llama a `helloDeadlineElapsed` [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:75]
- Un hello valido cancela ese timer [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:86]
- `authenticate` marca `authenticated` antes de publicar la presencia [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:134]
- Publica la presencia antes de mandar `helloOK` [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:135]
- Y manda `helloOK` por la conexion [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:136]
- `helloDeadlineElapsed` no cierra nada si la sesion ya esta autenticada [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:150]
- `BridgeConnection.send` no escribe nada si la conexion ya esta cerrada [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:287]
- `close` marca cerrada la conexion bajo lock y de forma sincrona [repo:Sources/CompanionServices/Bridge/BridgeListener.swift:291]
- El rig del test adjunta cada conexion al canal desde un `Task.detached` [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:53]
- `browserConnected` manda el hello y exige que la respuesta contenga `ok:true` [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:81]
- Y luego sondea `presence.connected` con `browserWaitFor` [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:82]
- `browserWaitFor` sondea con reloj de pared cada 5 ms hasta su timeout [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:67]
- El test toma `started` antes de conectar [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:166]
- Y exige como premisa que conectar y el hello tarden menos de 1 s [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:169]
- Despues vigila 1,5 s que la presencia no caiga [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:171]
- El cliente POSIX del test tiene un `SO_RCVTIMEO` de 2 s [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:376]
- La casa ya registro que `.timeLimit` no aborta un test colgado [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:118]
- Inventario: el test 2 fallo 26 veces bajo carga y en un gates con load 50 [repo:docs/inventario-flakes.md:40]
- Inventario: el test 1 fallo 20 veces bajo carga [repo:docs/inventario-flakes.md:41]
Contextos: (1) `swift test` local en paralelo en la Mac de Karen, cargada (load ~57), donde caen; (2) job `gates` de CI en macos-26, en serie; (3) job TSan, en serie y mas lento; (4) la app empaquetada, donde `DecisionGate.plan` corre en cada turno del hold clasico con el proveedor de Ollama y `BrowserChannel` atiende la extension; las opciones recomendadas solo tocan tests y no cambian la app.

## 3. Fuentes primarias

- Swift 6.3.3, `TaskGroup`: un grupo "*always* waits for all child tasks to complete"; los `with...TaskGroup` no vuelven hasta que todo hijo termino [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskGroup.swift#L280@swift-6.3.3-RELEASE]
- El mismo archivo: aunque el cuerpo devuelva el primer resultado, "the group automatically waits for all the remaining tasks before returning" [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskGroup.swift#L285@swift-6.3.3-RELEASE]
- `Task.cancel`: la cancelacion es cooperativa; una funcion que no la comprueba "will run to completion normally" [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Task.swift#L207@swift-6.3.3-RELEASE]
- `Task.value` (sin error): si la tarea no termino, acceder "waits for it to complete"; no menciona reaccionar a la cancelacion de quien espera [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Task.swift#L242@swift-6.3.3-RELEASE]
- `Task.sleep(for:)`: si la tarea se cancela antes de tiempo lanza `CancellationError`, y no bloquea el hilo [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskSleepDuration.swift#L230@swift-6.3.3-RELEASE]
- La implementacion instala un manejador de cancelacion que reanuda la continuacion lanzando `CancellationError`; reanudar es encolar trabajo, no correrlo en el acto [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskSleepDuration.swift#L90@swift-6.3.3-RELEASE]
- `Clock`: dormir "resumes the calling task after a given deadline has been met or passed"; no hay cota superior [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Clock.swift#L23@swift-6.3.3-RELEASE]
- SE-0329 propone un reloj manual "useful for testing", que avanza el tiempo de forma determinista, y lo deja fuera de la libreria [doc:https://github.com/swiftlang/swift-evolution/blob/c8078eda3849e1af3273f93f572a8ea9834b06dc/proposals/0329-clock-instant-duration.md#L384@Swift-5.7]
- swift-testing: `.timeLimit` marca el test como fallido y cancela su tarea cuando se pasa [doc:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Testing.docc/LimitingExecutionTime.md#L39@swift-6.3.3-RELEASE]
- swift-testing aplica una granularidad de un minuto a los limites de tiempo; no sirve para afirmar 80 ms ni 1 s [doc:https://github.com/swiftlang/swift-testing/blob/48d727cc1cf4eda667c858c501495f1018f69d21/Sources/Testing/Testing.docc/LimitingExecutionTime.md#L47@swift-6.3.3-RELEASE]
- WWDC21 "Use async/await with URLSession": "Swift concurrency's cancellation works with URLSession async methods" [doc:https://developer.apple.com/videos/play/wwdc2021/10095/@WWDC21]
- Respuesta (1a), que espera el gate tras el budget: el grupo no vuelve hasta que el hijo `await task.value` termina, y ese hijo no reacciona a la cancelacion del grupo, asi que espera a que el `Task` de trabajo termine [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskGroup.swift#L285@swift-6.3.3-RELEASE]
- El `Task` de trabajo termina porque el `defer` lo cancela y el `Task.sleep` del proveedor lanza; pero eso pide que el runtime planifique al proveedor, despues al `route` que llama al arbitro, y despues al hijo que espera `task.value` [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskSleepDuration.swift#L90@swift-6.3.3-RELEASE]
- Respuesta (1b), que mide el tope de 1 s: la suma de esos saltos mas el del propio reloj de 80 ms y el regreso al test; ningun documento de Swift acota en tiempo de pared cuando se reanuda una tarea, asi que el tope mide planificacion bajo carga, no la garantia [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Clock.swift#L23@swift-6.3.3-RELEASE]
- Respuesta (1c), garantia del producto: con el proveedor real la espera extra es corta, porque `URLSession` async honra la cancelacion; con un proveedor o arbitro que no la honre, `plan` duraria lo que dure el perdedor, contra lo que promete el comentario. Es un riesgo latente, no un bug observado. La cancelacion es cooperativa [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Task.swift#L207@swift-6.3.3-RELEASE]; que `URLSession` la honre en el acto es un supuesto de la seccion 9, con su prueba
- Respuesta (1d), bajo un pool hambriento ningun diseno cumple el budget en tiempo de pared: hasta el hijo que duerme 80 ms necesita un hilo para reanudar [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/Clock.swift#L23@swift-6.3.3-RELEASE]
- Respuesta (2), por que sobra la premisa: el `ok:true` solo sale si `authenticate` corrio con la conexion abierta, y desde ese momento `helloDeadlineElapsed` ya no cierra; la premisa observable es esa respuesta, no un tiempo. Es logica del repo, no de un documento de Swift [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:150]

## 4. Implementaciones de referencia

- swift-async-algorithms (Apple, 3712 estrellas, actividad hoy): sus tests prueban la cancelacion de un `sleep` guardando el error en un estado protegido y afirmando `is CancellationError`, la idea de "probar que el perdedor fue cancelado" de la opcion 1-A [ref:https://github.com/apple/swift-async-algorithms/blob/d9c26817af0127680e7c5efa1bdf11e83a2ec27b/Tests/AsyncAlgorithmsTests/TestManualClock.swift#L36@d9c2681]
- El mismo repo trae un `ManualClock` de test que materializa el reloj manual de SE-0329 [ref:https://github.com/apple/swift-async-algorithms/blob/d9c26817af0127680e7c5efa1bdf11e83a2ec27b/Tests/AsyncAlgorithmsTests/Support/ManualClock.swift#L14@d9c2681]
- swift-clocks (Point-Free, 343 estrellas, base de la familia TCA): inyectar `any Clock<Duration>` y usar `TestClock` en tests es su patron documentado para timers y timeouts [ref:https://github.com/pointfreeco/swift-clocks/blob/82440fa0a8b1c381a6d1e8e0fc7bbba53ec63204/README.md#L93@82440fa]
- Pero su `advance` llama a `Task.megaYield()` antes y despues de despertar a cada durmiente para dejar correr a las tareas despertadas [ref:https://github.com/pointfreeco/swift-clocks/blob/82440fa0a8b1c381a6d1e8e0fc7bbba53ec63204/Sources/Clocks/TestClock.swift#L168@82440fa]
- Y `megaYield` se documenta como algo que hace los tests async "less flakey", no deterministas: 20 cesiones por defecto [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/Sources/ConcurrencyExtras/Task.swift#L7@5fa2534]

## 5. Opciones

Test 1 (`DecisionGate`):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| 1-A. Proveedor que duerme acotado (10 s) y registra si lo cancelaron; se afirma `.timedOut` y que vio la cancelacion; se borra `elapsed < 1` | Sin reloj; prueba el hecho (gano el budget y el perdedor fue cancelado); solo test; determinista con el `race` actual, que espera al perdedor antes de volver | No mide que el budget sea 80 ms y no 79; si alguien cambia `race` para no esperar al perdedor, la bandera puede llegar tarde (trampa, seccion 8) | baja, ~10 lineas | Si |
| 1-B. Inyectar un reloj (`any _Concurrency.Clock<Duration>`) en `DecisionGate` y avanzar un reloj manual | Patron documentado (SE-0329, swift-clocks); permite afirmar "no vence antes del budget" | Cambia la API del producto; hay que escribir un reloj manual o agregar dependencia (bloqueada); tras `advance` el test igual espera a que corran las tareas despertadas (megaYield) | media, ~80 lineas | No ahora |
| 1-C. Subir el tope a 5 o 10 s | Una linea | Sigue siendo reloj; con 5,26 s observado ya caeria | baja | No |
| 1-D (producto, aparte). `race` con la forma de `ScreenSight` (reanuda el primero y cancela el trabajo sin esperarlo) | Cumple el comentario aunque el proveedor no coopere | Cambio de producto; deja trabajo vivo tras volver; no arregla el flake por si solo | media | Decide Karen |

Test 2 (`BrowserChannel`):

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| 2-A. Borrar la premisa de tiempo y afirmar la observable: `ok:true` (ya en el helper) y `presence.connected`; dejar la vigilancia de 1,5 s | Solo test; quita el falso rojo; la premisa nueva es exactamente el hecho que importa | La vigilancia sigue siendo de reloj: bajo carga extrema puede dar falso verde, nunca falso rojo; no ejercita la guarda de `:150` aparte de la cancelacion de `:86` | baja, ~3 lineas | Si |
| 2-B. Costura de timer inyectable en `BrowserChannel` (por defecto el `Task.sleep` actual); el test dispara el timer el mismo, despues del hello, espera a que vuelva y comprueba con un `send` que la sesion sigue viva | Determinista en las dos direcciones; ejercita la guarda de `:150`, que es la defensa para un timer ya vencido | Cambia la API del producto; diseno propio, sin precedente leido | media, ~25 lineas | Seguimiento si Karen quiere cubrir la guarda |
| 2-C. Inyectar un `Clock` y avanzar un reloj manual | Patron documentado | Tras avanzar no hay senal positiva de que `helloDeadlineElapsed` ya corrio; volveria a depender de cesiones o de esperar con reloj | media | No |
| 2-D. Subir la premisa a 5 s | Una linea | Sigue siendo reloj | baja | No |

## 6. Evidencia en contra

- Contra 1-A: no afirma nada cuantitativo del budget; un cambio que ignore `budget` y use otro plazo corto pasaria [repo:Sources/CompanionServices/Decision/DecisionGate.swift:103]
- Se acepta: el valor del budget llega intacto de la config y lo cubre la lectura; un plazo exacto solo se probaria con 1-B, y ese reloj manual de referencia depende de cesiones heuristicas [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/Sources/ConcurrencyExtras/Task.swift#L7@5fa2534]
- Contra 1-A: si el pool se queda sin hilos mas de 10 s, el proveedor gana y el resultado es `.failed`, un falso rojo; se acepta porque 10 s es el doble del peor caso observado (5,26 s) [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:227]
- Contra 1-A: la bandera de cancelacion es determinista solo porque `race` espera al perdedor; esa misma espera es el riesgo latente de 1-D [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskGroup.swift#L285@swift-6.3.3-RELEASE]
- Contra 2-A: tras quitar la premisa, la vigilancia solo detecta una regresion que quite a la vez la cancelacion de `:86` y la guarda de `:150`, y solo si el timer dispara dentro de la ventana [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:150]
- Se acepta para este arreglo: el inventario pide quitar el falso rojo; la cobertura determinista de la guarda es 2-B y pide cambio de API [repo:docs/inventario-flakes.md:40]
- Contra 2-A: el helper conserva un reloj de 2 s en el `SO_RCVTIMEO` del cliente; bajo carga peor que la observada, el `ok:true` podria no llegar a tiempo [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:376]
- Contra la tesis de 1b: 5,26 s se parece mucho a los 5 s del proveedor, lo que tambien encajaria con un reloj de 80 ms que no llego a correr antes de que el proveedor terminara solo; resuelto: los logs de gates descartan esa lectura (seccion 9), porque `:226` no cayo en ninguna corrida [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:213]

## 7. Ejemplares y anti-ejemplos

- Anti-ejemplo: tope de reloj de pared como proxy de "vuelve por el budget" [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:227]
- Anti-ejemplo: premisa de reloj de pared que el test no controla [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:169]
- Ejemplar externo: guardar el error de un `sleep` cancelado y afirmar `CancellationError` (sin su `fulfillment(timeout: 1.0)`, que es otro reloj) [ref:https://github.com/apple/swift-async-algorithms/blob/d9c26817af0127680e7c5efa1bdf11e83a2ec27b/Tests/AsyncAlgorithmsTests/TestManualClock.swift#L42@d9c2681]
- Ejemplar de la casa para 1-D: carrera que no espera al perdedor [repo:Sources/CompanionServices/Perception/ScreenSight.swift:262]
- Boceto 1-A, sin compilar, que reemplazaria el test de esta linea [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:210]

```swift
@Test func dm1cGateTimesOutWithinBudgetWhenTheProviderIsSlow() async {
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var cancelled: Bool { lock.withLock { value } }
        func markCancelled() { lock.withLock { value = true } }
    }
    // Long enough that only the budget can end plan(); bounded so a
    // regression that stops cancelling fails in ~20 s instead of hanging.
    struct SlowProvider: DecisionProvider {
        let seen: Seen
        func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
            do { try await Task.sleep(for: .seconds(10)) } catch { seen.markCancelled() }
            return nil
        }
    }
    let seen = Seen()
    let gate = DecisionGate(
        provider: SlowProvider(seen: seen),
        arbiter: FakeArbiter(result: nil),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() },
        budget: .milliseconds(80))
    let step = await gate.plan("abre Safari", canDelegate: false)
    expectEq(step, .passThrough(.timedOut), "el proveedor lento nunca decide a tiempo")
    expect(seen.cancelled, "el gate cancelo al proveedor que perdio la carrera")
}
```

- Boceto 2-A, sin compilar: se borran la linea de `started` y la premisa de tiempo, y la premisa pasa a ser el estado [repo:Tests/CompanionServicesTests/BrowserChannelTests.swift:163]

```swift
@Test func aHelloInsideTheDeadlineIsNotClosedLater() async throws {
    let rig = try makeBrowserRig(helloDeadline: .seconds(1))
    defer { rig.listener.stop() }
    // ok:true (checked inside the helper) is only written on an open
    // connection, and once authenticated the deadline handler closes nothing.
    let client = try await browserConnected(rig)
    defer { client.close() }
    expect(rig.presence.connected, "deadline: the hello authenticated (the premise of the test)")
    let outlived = await browserWaitFor(timeout: 1.5) { !rig.presence.connected }
    expect(!outlived, "deadline: an authenticated session outlives the hello timer")
}
```

## 8. Trampas

- Usar `try? await Task.sleep` y luego `Task.isCancelled` en vez de `catch`: tambien sirve, pero el `catch` deja explicito que se vio la cancelacion del sleep [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/TaskSleepDuration.swift#L230@swift-6.3.3-RELEASE]
- El proveedor se llama dos veces por `compose`; la segunda ve la tarea ya cancelada y su `sleep` lanza en el acto, asi que no alarga la espera [repo:Sources/CompanionCore/Decision/Plan.swift:209]
- Un proveedor de test que espere con `TestGate.wait` nunca veria la cancelacion: `plan` se colgaria, porque esa espera no tiene manejador [repo:Tests/CompanionTestKit/TestKitFakes.swift:19]
- No confiar en `.timeLimit` para cortar un cuelgue: su granularidad es un minuto y la casa ya vio que no aborta el test; por eso el proveedor duerme acotado [repo:Tests/CompanionIntegrationTests/DiagramTestKit.swift:118]
- Si se adopta 1-D, `plan` volveria antes de que el proveedor marque la bandera; el test tendria que esperar la bandera como estado (sondeo acotado), no leerla al volver [repo:Sources/CompanionServices/Perception/ScreenSight.swift:266]
- Con 1-B, `Clock` dentro de `CompanionServices` resuelve al protocolo propio de `Approvals`, no al de la libreria; hay que escribir `_Concurrency.Clock` [repo:Sources/CompanionServices/Approvals/Approvals.swift:4]
- 2-A depende de que `presence.set` ocurra antes de `helloOK`; si alguien invierte esas dos lineas, `presence.connected` podria leerse falso justo despues del `ok:true` [repo:Sources/CompanionServices/Browser/BrowserChannel.swift:135]
- Contexto (1), local cargado: con 1-A y 2-A no queda ninguna asercion de reloj que pueda dar falso rojo, salvo el `SO_RCVTIMEO` de 2 s del cliente y el plazo de 10 s del proveedor [repo:Tests/CompanionServicesTests/BridgeListenerTests.swift:376]
- Contexto (2), CI en serie: los dos bocetos no dependen del paralelismo; en serie el test 1 vuelve en el orden del budget [repo:Tests/CompanionServicesTests/DecisionGateTests.swift:210]
- Contexto (3), TSan: el boceto 1-A usa `NSLock` para la bandera, asi que no introduce una carrera de datos nueva, igual que `TestGate` [repo:Tests/CompanionTestKit/TestKitFakes.swift:7]
- Contexto (4), app: 1-A y 2-A no tocan producto; la espera al perdedor del gate sigue ahi y es la decision 1-D [repo:Sources/CompanionServices/Decision/DecisionGate.swift:274]

## 9. Incertidumbre

- Sonda de esta corrida, sin construir, en companion-next-self-qa-wiring (mismas fuentes de los dos archivos, verificado con diff), con load 14 a 58: sueltos, el test 1 paso en 0,086 s y el test 2 en 1,511 s (la ventana de vigilancia de 1,5 s domina).
- Clasificacion: los dos son familia reloj. El test 1 ademas mide una espera estructurada (el grupo espera al perdedor); no es main actor ni orden. El test 2 es una premisa de reloj redundante.
- Evidencia en contra, resumen: (a) 1-A no prueba el valor del budget, solo que gano el budget; (b) 1-A puede dar falso rojo si el pool queda sin hilos mas de 10 s; (c) 2-A deja una vigilancia de reloj que bajo carga da falso verde y no cubre la guarda de `:150` por separado; (d) el helper del navegador conserva un `SO_RCVTIMEO` de 2 s; (e) que el reloj de 80 ms no llegara a correr antes del proveedor queda descartado por los logs (ver abajo), pero el salto de ese reloj puede ser parte del tiempo extra (sin medir, ver el reparto abajo); (f) el reloj manual de referencia (swift-clocks) depende de `megaYield`, cesiones heuristicas que su autor llama "less flakey", no deterministas.
- Verificado por la sesion que encargo el brief, con los cinco logs de gates del 2026-10-02 (#108, #109 x2, #110 x2; el de 5,26 s es la segunda de #110): ninguno trae `DecisionGateTests.swift:226` ni el mensaje "el proveedor lento nunca decide a tiempo", asi que en todas solo cayo `:227` y el resultado fue `.timedOut`. Gano el budget: el tiempo extra vino despues, no de un reloj que no corrio.
- ASSUMPTION: el tiempo extra bajo carga se reparte entre el salto del reloj de 80 ms y los saltos de cancelacion del perdedor; no se instrumento. prueba: en una rama de sonda, registrar con `ContinuousClock` el instante en que vence el sleep del hijo, el `catch` del proveedor y la vuelta de `race`, y correr la suite completa con carga.
- ASSUMPTION: `URLSession.data(for:)` lanza en el acto si la tarea ya esta cancelada, asi que la segunda pregunta de `compose` no espera la red; WWDC21 dice que la cancelacion funciona, no cuanto tarda. prueba: test con `URLProtocol` que nunca responde, cancelar y medir que `answer` vuelve nil sin esperar los 4 s del timeout.
- ASSUMPTION: los bocetos compilan tal cual (`NSLock.withLock`, `FakeArbiter`, `Seen` anidada en una funcion de test). prueba: compilarlos en la rama del cambio; no se compilo aqui por la regla de no construir en la Mac compartida.
- ASSUMPTION: 1-A es rojo con la regresion que cuida y verde bajo carga. prueba: RED quitando `task.cancel()` del `defer` de `DecisionGate.swift:285` (el test debe fallar en `seen.cancelled` tras ~20 s); GREEN con el codigo actual y con `kill -STOP` de 1,5 s al proceso de tests en mitad de `plan`, que hoy hace caer `:227`.
- Objecion a 2-A, aceptada y no resuelta: si el proceso se detiene mas de 1 s entre `attach` y el hello, `helloDeadlineElapsed` y el manejo del hello quedan listos a la vez y su orden no es determinista; si gana el timer, el canal cierra y el `ok:true` del helper falla. 2-A quita la premisa de reloj del test, pero el plazo de 1 s del producto sigue siendo un reloj de pared en ese caso extremo; solo 2-B lo saca del test.
- ASSUMPTION: 2-A es verde bajo la misma pausa. prueba: `kill -STOP` de 1,2 s entre el connect y la respuesta del hello; el test viejo cae en `:169`, el nuevo pasa. Como RED de regresion, quitar a la vez `deadline.cancel()` de `:86` y `!authenticated` de `:150`: con la Mac en reposo el test debe fallar.
- Sin precedente leido: la costura de timer de 2-B (el test dispara el timer y espera su handler) es diseno propio; el precedente documentado es inyectar un `Clock` (SE-0329, swift-clocks), que para este caso no da senal positiva de que el handler ya corrio.
- [NEEDS CLARIFICATION: Karen, 1-D: el comentario de `DecisionGate.plan` promete que un proveedor lento "never blocks the turn", pero `race` espera a que el perdedor termine. Con Ollama hoy honra la cancelacion, asi que no hay bug observado. Se abre un cambio de producto aparte para darle la forma de `ScreenSight.race` (reanudar el primero y cancelar sin esperar), con RED "un proveedor que ignora la cancelacion igual devuelve `.timedOut`", o solo se corrige el comentario?]
- [NEEDS CLARIFICATION: Karen, 2-B: quieres cubrir de forma determinista la guarda de `BrowserChannel.swift:150` con una costura de timer en la API de `BrowserChannel`, que es diseno propio, o basta 2-A?]

## 10. Checklist de estandar

- [ ] Ninguno de los dos tests contiene una asercion sobre tiempo transcurrido (`Date()`, `elapsed`, `timeIntervalSince`).
- [ ] Test 1: el proveedor duerme acotado (10 s), marca la cancelacion en el `catch` del `sleep`, y el test afirma `.passThrough(.timedOut)` y que el proveedor vio la cancelacion.
- [ ] Test 1: RED documentado: sin `task.cancel()` en el `defer` de `race`, el test falla en la bandera de cancelacion.
- [ ] Test 2: la premisa es observable: `ok:true` del hello (en `browserConnected`) y `rig.presence.connected`; `started` desaparece.
- [ ] Test 2: RED documentado: sin la cancelacion de `:86` y sin la guarda de `:150`, el test falla con la Mac en reposo.
- [ ] Los dos tests pasan con una pausa `kill -STOP` de 1,2 a 1,5 s al proceso de tests, que hoy los hace caer.
- [ ] Ningun cambio de API de producto en este arreglo; 1-D y 2-B solo con decision de Karen.
- [ ] Las filas 40 y 41 de `docs/inventario-flakes.md` se actualizan con el PR.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | TaskGroup.swift, Task.swift, TaskSleepDuration.swift, Clock.swift | swiftlang/swift | swift-6.3.3-RELEASE | 2026-10-02 | high |
| 2 | SE-0329 Clock, Instant, and Duration | Swift Evolution | Swift 5.7 | 2026-10-02 | high |
| 3 | Limiting the running time of tests | swiftlang/swift-testing | swift-6.3.3-RELEASE | 2026-10-02 | high |
| 4 | Use async/await with URLSession | Apple (WWDC21 10095) | WWDC21 | 2026-10-02 | medium |
| 5 | TestManualClock.swift, Support/ManualClock.swift | apple/swift-async-algorithms | d9c2681 | 2026-10-02 | high |
| 6 | README.md, TestClock.swift | pointfreeco/swift-clocks | 82440fa | 2026-10-02 | medium |
| 7 | Task.swift (megaYield) | pointfreeco/swift-concurrency-extras | 5fa2534 | 2026-10-02 | medium |
| 8 | tests-espera-sin-hilo, tests-orden-no-prometido | companion-next docs/research | 2026-10-01 | 2026-10-02 | high |
| 9 | Sondas: los dos tests sueltos en companion-next-self-qa-wiring, mismas fuentes | esta corrida | 2026-10-02 | 2026-10-02 | medium |

[KAREN:chat 2026-10-02] (1) Acepto 1-A: proveedor que solo termina al cancelarse, sin tope de reloj; no hace falta otra referencia. (2) 2-A: quitar la premisa de tiempo y afirmar ok:true y presence.connected; el falso rojo con una pausa de mas de 1 s entre connect y hello queda como limite conocido. 2-B no, por ser diseno propio sin precedente. (3) Solo corregir el comentario de plan; 1-D (que race no espere al perdedor) se abre como cambio de producto solo si se observa en la app.
