# Reference Brief: flakes de NativeExecutorTests bajo carga

Slug: native-executor-flakes | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Por que fallan de forma intermitente bajo carga los tests de `Tests/CompanionServicesTests/NativeExecutorTests.swift` (2026-10-01, en ramas que no tocan el ejecutor) y que patron documentado los vuelve deterministas. Cambio previsto: solo tests y helpers de test; el ejecutor no cambia.

Decisiones:

1. Origen de los `CancellationError` reportados en :39, :65 y :146. Respuesta del brief: salen del tope de `runAsync` (TestKit.swift:82-83), no del body. El body no necesita el main actor (no hay deadlock), pero corre en un task detached que compite por el pool cooperativo mientras un hilo real queda bloqueado en un semaforo, y ademas borra recursivamente todo `temporaryDirectory` dentro del plazo de 5 s.
2. Por que :698 lee `seen.denied == []`. Respuesta: el evento si se emite y queda en el buffer del stream, pero `RoundEvents` lo consume en un Task no estructurado que nadie espera; la lectura sigue a `sink.finish()` sin esperar al consumidor, asi que es una carrera dentro del propio test (por eso aparece incluso en el job de TSan, que corre en serie).
3. Patron recomendado: tests `async` con `await` directo (sin `runAsync`), un directorio propio por test (`scratchDir`), y leer los eventos solo despues de esperar a que el consumidor termine (`sink.finish()` y luego `await` del task colector o `drain`). `pumpUntilAsync` queda como alternativa; dormir 50 ms queda descartado.

## 2. Estado actual

Contextos: `swift test` local en paralelo (scripts/gates.sh fuera de CI); job `gates` de CI con `--no-parallel`; job `tsan` de CI con `--sanitize=thread --no-parallel`; la app instalada, que construye NativeExecutor pero no ejecuta ningun helper de test.
- `runAsync` es una funcion `@MainActor` sincrona con plazo por defecto de 5 s [repo:Tests/CompanionTestKit/TestKit.swift:71]
- `runAsync` lanza el body en un `Task.detached` que no guarda ni cancela nunca [repo:Tests/CompanionTestKit/TestKit.swift:77]
- `runAsync` espera con `DispatchSemaphore.wait(timeout:)`, bloqueando el hilo del main actor mientras dura la espera [repo:Tests/CompanionTestKit/TestKit.swift:82]
- Al vencer el plazo lanza `CancellationError()` sin cancelar el task detached, que sigue corriendo [repo:Tests/CompanionTestKit/TestKit.swift:83]
- El body asigna `box.result` antes de `lock.signal()`, asi que la rama `box.result == nil` de la linea 85 no se alcanza tras un signal [repo:Tests/CompanionTestKit/TestKit.swift:80]
- Cualquier error del body se relanza tal cual [repo:Tests/CompanionTestKit/TestKit.swift:88]
- El ejecutor solo lanza `CancellationError` via `Task.checkCancellation()` [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:45]
- Lo vuelve a comprobar en cada iteracion del bucle [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:72]
- Como el task detached nunca se cancela, esas comprobaciones no disparan dentro de `runAsync`: el unico origen posible del `CancellationError` en :39/:65/:146 es el tope de la linea 83 [repo:Tests/CompanionTestKit/TestKit.swift:83]
- `NativeExecutor` es un struct `Sendable` sin aislamiento a actor [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:6]
- `run` es un metodo `async` no aislado [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:41]
- El target CompanionServices no declara `defaultIsolation` [repo:Package.swift:24]
- CompanionUI si declara `defaultIsolation(MainActor.self)`; Services no hereda nada de eso [repo:Package.swift:36]
- `NativeToolRunner` es un struct `Sendable` sin `@MainActor` [repo:Sources/CompanionServices/Tools/NativeToolRunner.swift:22]
- Su init crea por defecto `MapKitPlacesSearch()` [repo:Sources/CompanionServices/Tools/NativeToolRunner.swift:55]
- Ese init solo guarda el limite; no toca MapKit ni el main thread [repo:Sources/CompanionServices/Tools/PlacesSearch.swift:32]
- Los fakes de permisos de los tres tests son actors propios, no `@MainActor` (DenyingApprovals) [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:281]
- ApprovingApprovals tambien es un actor propio [repo:Tests/CompanionCoreTestSupport/ToolFakes.swift:292]
- El provider de prueba emite desde un `Task` sin aislamiento, no desde el main actor [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:213]
- Conclusion de la traza: el body de :39/:65/:146 llama un `run` que no esta aislado al main actor, asi que el main thread bloqueado no lo detiene; no es un deadlock parcial, y la causa del vencimiento queda como hipotesis con prueba en la seccion 9 [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:41]
- El body de :39 toma `FileManager.default.temporaryDirectory.path` como `tempDir` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:41]
- Y en su `defer` borra ese directorio entero, recursivamente, dentro del plazo de 5 s [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:42]
- :65 repite el mismo `defer` que borra `temporaryDirectory` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:68]
- :146 tambien [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:149]
- `scratchDir`, que usan los tests de rondas, crea sus carpetas dentro de ese mismo `temporaryDirectory` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:466]
- Los tres tests de `runAsync` ya esperan a su consumidor antes de leer (`try? await drainTask.value`) [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:98]
- Camino de la negacion: `perform` emite `.approvalDenied` antes de devolver el resultado de la tool [repo:Sources/CompanionServices/Delegation/NativeExecutor.swift:193]
- `RoundEvents` arranca su consumidor como un `Task` no estructurado dentro del init y no guarda su handle [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:585]
- `seen.denied` es la propiedad del actor que ese consumidor llena al recibir `.approvalDenied` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:593]
- El test llama a `sink.finish()` en cuanto `run` devuelve [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:694]
- Y lee `await seen.denied` de inmediato, sin `pumpUntil` ni espera al consumidor [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:698]
- `EventCollector` repite la forma: consumidor no estructurado en el init [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:363]
- Y se lee inmediatamente despues de `finish` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:292]
- Dos tests tapan la misma carrera con una siesta de 50 ms antes de leer [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:733]
- El segundo [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:771]
- En CI la suite corre en serie por un HACK cuyo trigger de salida es migrar los semaforos a espera estructurada [repo:scripts/gates.sh:259]
- Fuera de CI no se pasa `--no-parallel` [repo:scripts/gates.sh:266]
- El job de TSan tambien corre en serie [repo:scripts/tsan.sh:15]
- Y con `--sanitize=thread` [repo:scripts/tsan.sh:18]
- El job `tsan` de CI ejecuta ese script [repo:.github/workflows/ci.yml:46]
- `pumpUntil` documenta que sus plazos subieron porque los `runAsync` de otros sitios bloquean un hilo real hasta 5 s [repo:Tests/CompanionTestKit/TestKit.swift:97]
- Ejemplar propio de espera estructurada: un colector que se espera con `await collector.value` despues de `finish` [repo:Tests/CompanionServicesTests/JobRunnerTests.swift:61]
- Ejemplar propio del fix de una carrera de lectura con `pumpUntil` (commit 570dca0) [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:130]
- TestKit ya ofrece `drain`, que consume un stream hasta su fin [repo:Tests/CompanionTestKit/TestKit.swift:148]
- `TestGate` permite detener codigo en un punto conocido y soltarlo desde el test [repo:Tests/CompanionTestKit/TestKitFakes.swift:5]
- En la app, NativeExecutor se construye en el composition root, sin ningun helper de test [repo:Sources/CompanionApp/CompanionMainProviders.swift:95]

## 3. Fuentes primarias

- Swift Testing: un test puede marcarse `async` y hacer `await` directo de las interacciones asincronas [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Testing.docc/testing-asynchronous-code.md#L17-L28@6.3]
- Swift Testing: para confirmar que un evento ocurre N veces existe `confirmation(expectedCount:)` [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Testing.docc/testing-asynchronous-code.md#L34-L50@6.3]
- Swift Testing: `@Test @MainActor func ... async throws` es la forma documentada de un test que necesita el main actor [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Testing.docc/DefiningTests.md#L69-L75@6.3]
- Swift Testing: los tests corren en paralelo por defecto y `--no-parallel` lo desactiva globalmente [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Testing.docc/Parallelization.md#L17-L20@6.3]
- Swift Testing (codigo del runner): un error lanzado fuera del body se registra en `step.test.sourceLocation`, la linea del `@Test`; por eso :64 y :145 [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Running/Runner.swift#L409-L410@6.3]
- Swift Testing: el texto del issue es "Caught error: ..." [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Issues/Issue.swift#L312@6.3]
- Swift Testing: `.timeLimit` acepta minimo un minuto y registra `timeLimitExceeded` como fallo [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Traits/TimeLimitTrait.swift#L65-L72@6.3]
- SE-0338: una funcion `async` no aislada corre en un executor generico, nunca en el de un actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@5.7]
- SE-0314: los elementos en buffer se entregan al consumidor antes del fin, y el buffer por defecto es ilimitado [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md@5.5]
- SE-0306: los tasks que esperan un actor no tienen garantizado correr en el orden en que lo esperaron [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@5.5]
- WWDC21 "Swift concurrency: Behind the scenes": el pool cooperativo tiene tantos hilos como nucleos y los semaforos que crean una dependencia entre tasks rompen el contrato de progreso [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@wwdc2021]
- Swift stdlib: un task detached no hereda la cancelacion ni la prioridad, y descartar su referencia no lo cancela [doc:https://github.com/swiftlang/swift/blob/6bb593c2d91fdd65082b6dea7d58dfcf15e84cae/stdlib/public/Concurrency/Task%2Binit.swift.gyb#L255-L267@6.3]

## 4. Implementaciones de referencia

- apple/swift-async-algorithms (Apple, 3.7k estrellas, push 2026-09-30): sus tests son funciones `async` que hacen `await` de la coleccion completa antes de afirmar, sin semaforos ni plazos [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/TestRangeReplaceableCollection.swift#L37-L42@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- pointfreeco/swift-concurrency-extras (Point-Free, 490 estrellas, push 2026-07-24): `withMainSerialExecutor` serializa los tasks de un test, y su doc advierte que depende de una variable global mutable del runtime sin garantia de alcance [ref:https://github.com/pointfreeco/swift-concurrency-extras/blob/5fa253428866f2360c3754e88537f700ed2656b5/Sources/ConcurrencyExtras/MainSerialExecutor.swift#L22-L28@5fa253428866f2360c3754e88537f700ed2656b5]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Tests `async` con `await` directo; colectores esperados tras `finish` (handle del Task o `drain`); `scratchDir` por test | Sin plazo arbitrario ni hilo bloqueado; la lectura tiene happens-before con el consumo; patron documentado por Swift Testing y ya usado en JobRunnerTests | Pierde el tope de 5 s como guarda de cuelgue (ver seccion 6); toca helpers `RoundEvents` y `EventCollector` | baja | Si |
| B. Mantener `runAsync` y subir el plazo | Diff de una linea | Sigue bloqueando un hilo real (WWDC21); el plazo ya se subio en `pumpUntil` y la carga lo alcanza igual; no arregla :698 | baja | No |
| C. `pumpUntilAsync` sobre `seen.denied` | Ya existe; patron del fix 570dca0 | Sondeo con plazo (30 s); un "nunca llega" tarda 30 s en fallar; no dice cuando el consumidor termino | baja | Alternativa para lecturas sin fin de stream |
| D. `withMainSerialExecutor` | Determinismo global del scheduling | Dependencia nueva (bloqueada); variable global del runtime contra tests paralelos | media | No |
| E. Dormir 50 ms antes de leer (como :733) | Ninguno real | Sigue siendo carrera; solo baja la probabilidad | baja | No, y retirar los dos existentes |
| T. `scratchDir` propio en vez de borrar `temporaryDirectory` | Quita I/O recursivo del plazo y el borrado de carpetas ajenas | Ninguno | baja | Si, junto con A |

## 6. Evidencia en contra

- Lo mas fuerte contra A: quitar `runAsync` quita el tope de 5 s, y un test async colgado ya no falla rapido; se acepta con `.timeLimit(.minutes(1))` en los tests migrados, que Swift Testing registra como fallo [doc:https://github.com/swiftlang/swift-testing/blob/d62511b5ac83b196d91a9b071672300dc6119b4a/Sources/Testing/Traits/TimeLimitTrait.swift#L65-L72@6.3]
- Ademas, el job de TSan tiene su propio techo de 45 minutos, que corta un cuelgue aunque falte el trait [repo:.github/workflows/ci.yml:39]
- Contra A: migrar solo estos tres tests deja unos 149 usos de `runAsync`/`runOk` en la suite y el HACK de `--no-parallel` sigue vigente; se acepta como alcance local, el trigger del HACK no cambia [repo:scripts/gates.sh:259]
- Contra esperar al consumidor: si un test olvida `sink.finish()`, esperar al colector cuelga para siempre, porque el stream solo termina con `finish` [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md@5.5]
- Se resuelve porque todos los tests afectados ya llaman `sink.finish()` tras `run`, incluso cuando `run` falla, al usar `try?` [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:693]

## 7. Ejemplares y anti-ejemplos

- Bien: colector como `Task` con handle, `sink.finish()` y luego `await collector.value` antes de afirmar [repo:Tests/CompanionServicesTests/JobRunnerTests.swift:61]
- Bien, en el mismo archivo: `continuation.finish()` y `try? await drainTask.value` antes de leer el tracker [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:176]
- Bien, para un efecto sin fin de stream: `await pumpUntil(...)` en vez de leer en el acto (commit 570dca0) [repo:Tests/CompanionIntegrationTests/Diagram16m5bRound2Tests.swift:130]
- Bien, externo: `await` de la secuencia completa y despues la afirmacion [ref:https://github.com/apple/swift-async-algorithms/blob/13713a4ffdee8abd929f92568ee9462a46ae26e0/Tests/AsyncAlgorithmsTests/TestRangeReplaceableCollection.swift#L37-L42@13713a4ffdee8abd929f92568ee9462a46ae26e0]
- Anti: leer el actor colector justo despues de `finish`, sin esperar al consumidor [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:698]
- Anti: siesta de 50 ms para "dar tiempo" al consumidor [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:733]
- Anti: semaforo que bloquea un hilo esperando a un task no estructurado, el patron que WWDC21 declara inseguro [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@wwdc2021]
- Anti: `defer` que borra `temporaryDirectory` completo en lugar de una carpeta propia [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:42]

## 8. Trampas

- Arreglar solo `seen.denied` deja la misma carrera en `seen.finished` de la linea siguiente [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:699]
- Y en `seen.steps`, `seen.approvals`, `seen.remembered` de los otros tests de rondas [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:500]
- `EventCollector` de los tests de seguridad tiene la misma carrera aunque todavia no fallo en CI [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:292]
- Esperar el `.value` del colector exige guardar el handle del Task; hoy el init de `RoundEvents` lo descarta [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:585]
- Esperar a un actor no ordena las llamadas: la lectura puede adelantarse a `add` aunque ambos esperen el mismo actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@5.5]
- Llamar `runAsync` desde un test que ya es `async` mete un semaforo dentro de un contexto async, el caso que WWDC21 prohibe [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@wwdc2021]
- Dejar `@MainActor` en el test migrado no bloquea nada: `executor.run` es no aislado y corre fuera del main actor [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0338-clarify-execution-non-actor-async.md@5.7]
- Contexto local en paralelo: aplican las dos causas, y el borrado de `temporaryDirectory` puede alcanzar los `scratchDir` de los tests de rondas en curso [repo:Tests/CompanionServicesTests/NativeExecutorTests.swift:466]
- Contexto CI `gates` en serie: no hay tests solapados, pero la carrera del colector sigue dentro de cada test [repo:scripts/gates.sh:266]
- Contexto CI `tsan` en serie: TSan ralentiza todo, y ahi fallo :698 en el PR #91; la recomendacion la elimina porque la lectura deja de depender del scheduling [repo:scripts/tsan.sh:18]
- Contexto app: no cambia nada, ningun helper de test entra en el binario [repo:Sources/CompanionApp/CompanionMainProviders.swift:95]

## 9. Incertidumbre

- ASSUMPTION: los vencimientos de :39/:65/:146 se deben a que el task detached no consigue turno en el pool cooperativo bajo load 30-60 y/o a que el borrado recursivo de `temporaryDirectory` tarda; no se midio cual pesa mas. prueba: medir con `ContinuousClock` el tiempo del `defer` y el retraso entre `Task.detached` y la primera linea del body, en 20 corridas con `yes > /dev/null` en 2x los nucleos, y registrar ambos.
- ASSUMPTION: bajo `swift test`, `temporaryDirectory` es el `$TMPDIR` por usuario y contiene carpetas de otros tests en curso, que el `defer` borra. prueba: test RED con un archivo centinela en `temporaryDirectory` creado antes del body de :39 y que se afirma vivo despues.
- Medido (sonda de b6, 2026-10-01, binario compilado con swiftc 6.3): `FileManager.default.temporaryDirectory` devuelve `/var/folders/.../T` aunque el proceso arranque con `TMPDIR=$(mktemp -d)`; en Darwin sale del directorio temporal por usuario, no de la variable de entorno. Por eso no hay forma de aislar el borrado desde fuera (gates locales, CI con el usuario de la maquina): el arreglo tiene que estar en el test. Alcance: el directorio es el temporal de todo el usuario, no solo el de los tests, asi que el `defer` alcanza archivos de otros procesos de la Mac.
- ASSUMPTION (dato de 8f, 2026-10-01): el `$TMPDIR` de Karen tenia 166182 entradas y conservaba archivos de hace 6 dias, asi que `removeItem` no lo vacia entero: borra hasta el primer error (un archivo sin permiso o en uso) y lanza, y el `try?` del `defer` se traga el error. prueba: en una carpeta de prueba con un archivo protegido (`chflags uchg`) en medio, llamar `removeItem` y contar lo que queda antes y despues de la entrada protegida.
- ASSUMPTION: la rama release/6.3 de swift-testing describe el Swift Testing del toolchain 6.3.3 de esta Mac y de macos-26. prueba: comparar `swift --version` de ambos y la version de Testing que imprime `swift test --verbose`.
- ASSUMPTION: no hay otra fuente de `CancellationError` en el body (los fakes no la lanzan). prueba: envolver el body con `do/catch` que registre el error con un texto propio; si el fallo dice "Caught error: CancellationError()" sin ese texto, salio del tope.
- [NEEDS CLARIFICATION: los tests de `runAsync` de :39/:65/:146 viven desde Wave 10 con un `defer` que borra `temporaryDirectory`; confirmar si se reescriben con `scratchDir` en el mismo PR o en uno aparte.]

## 10. Checklist de estandar

- [ ] RED causa 1 (tope): un test llama `runAsync(timeout: 0.2)` con un body que espera un `TestGate` que nunca se abre y falla con "Caught error: CancellationError()" en la linea del `@Test`: demuestra que la firma observada sale de TestKit.swift:83
- [ ] RED causa 1b (borrado): un archivo centinela creado en `temporaryDirectory` antes del body de :39 sigue existiendo despues; hoy falla y queda verde al pasar a `scratchDir`
- [ ] RED causa 2 (colector): un `RoundEvents` con su consumidor detenido en un `TestGate` cerrado devuelve `denied == []` si se lee en el acto tras `finish`; con la espera al consumidor (abrir el gate y luego `await` del task) devuelve `["run_shell"]` siempre
- [ ] `nativeExecutorAcceptsApprovalsDependency`, `riskyToolEmitsApprovalEvent` e `iterationLimitPreventsInfiniteLoop` son `async`, sin `runAsync`, y llevan `.timeLimit(.minutes(1))`
- [ ] Ningun test de NativeExecutorTests.swift borra `temporaryDirectory`; cada uno usa `scratchDir` y borra solo esa carpeta
- [ ] Toda lectura de `RoundEvents` y `EventCollector` ocurre despues de `sink.finish()` y de esperar el fin del consumidor
- [ ] `grep -n "Task.sleep" Tests/CompanionServicesTests/NativeExecutorTests.swift` no devuelve nada
- [ ] `swift test --filter NativeExecutor` 30 veces seguidas con carga artificial, y una corrida de `scripts/tsan.sh`, sin fallos
- [ ] Fragmento en `changelog.d/` con la entrada del fix

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Testing asynchronous code (testing-asynchronous-code.md) | swiftlang/swift-testing | release/6.3 d62511b | 2026-10-01 | high |
| 2 | Defining test functions (DefiningTests.md) | swiftlang/swift-testing | release/6.3 d62511b | 2026-10-01 | high |
| 3 | Running tests serially or in parallel (Parallelization.md) | swiftlang/swift-testing | release/6.3 d62511b | 2026-10-01 | high |
| 4 | Runner.swift, Issue.swift, TimeLimitTrait.swift | swiftlang/swift-testing | release/6.3 d62511b | 2026-10-01 | high |
| 5 | SE-0338 Clarify the execution of non-actor-isolated async functions | Swift Evolution | Swift 5.7 | 2026-10-01 | high |
| 6 | SE-0314 AsyncStream and AsyncThrowingStream | Swift Evolution | Swift 5.5 | 2026-10-01 | high |
| 7 | SE-0306 Actors | Swift Evolution | Swift 5.5 | 2026-10-01 | high |
| 8 | Swift concurrency: Behind the scenes (sesion 10254) | Apple WWDC21 | 2021 | 2026-10-01 | high |
| 9 | Task+init.swift.gyb (doc de Task.detached) | swiftlang/swift | release/6.3 6bb593c | 2026-10-01 | high |
| 10 | TestRangeReplaceableCollection.swift | apple/swift-async-algorithms | 13713a4 | 2026-10-01 | medium |
| 11 | MainSerialExecutor.swift | pointfreeco/swift-concurrency-extras | 5fa2534 | 2026-10-01 | medium |

[KAREN:chat 2026-10-01] El cambio a scratchDir va en un PR urgente aparte, solo de tests, antes que todo. Lo demas segun la recomendacion del brief: tests async con await directo y esperar el fin del consumidor de RoundEvents antes de leer seen.denied, en el PR del flake.
