# Reference Brief: probar que una espera async no ocupa un hilo del pool cooperativo (ProcessGroupRunner.wait)

Slug: tests-espera-sin-hilo | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Cambio: reemplazar `testTheWaitDoesNotBlockTheCaller`, que mide reloj de pared (`elapsed < 0.75`) y falla 5/5 con un SIGSTOP de 1 s al proceso de tests. Ademas no detecta la regresion que dice cuidar: en una Mac multinucleo dos hilos bloqueados tambien se solapan.

Extiende `docs/research/tests-orden-no-prometido.md` (APROBADO): esperar el estado observable, no un proxy. Aqui el proxy es el tiempo transcurrido y el estado observable es "todas las esperas llegaron a lanzar su proceso mientras las demas seguian esperando".

Regla del proyecto que filtra las opciones, segun la sesion orquestadora: ningun patron que no este probado y documentado en la industria. Por eso la seccion 9 separa lo que tiene precedente documentado de lo que es diseno propio.

Preguntas:

1. Que esta documentado sobre el ancho del pool cooperativo en macOS: si es el numero de nucleos, si es fijo, que API lo consulta y que overrides existen (`LIBDISPATCH_COOPERATIVE_POOL_STRICT`, variables del runtime).
2. Que patrones documentados existen para probar que codigo async no bloquea un hilo del pool sin asercion de reloj, y si una barrera es determinista en las dos direcciones.
3. Un diseno concreto para este repo, con su tamano en lineas y sus riesgos (CI de 3 vCPU, rutas, limpieza).

Decisiones: (a) que forma toma el test; (b) que N usar y de que API sale; (c) si hace falta un paso de CI aparte con el pool estricto, que es la unica tecnica con precedente documentado.

## 2. Estado actual

- `ProcessGroupRunner.wait(for:timeout:)` sondea `waitpid` con `WNOHANG` [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:143]
- Entre sondeos duerme con `Task.sleep` de 5 ms, que suspende la tarea en vez de bloquear el hilo [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:151]
- El comentario de `wait` fija la intencion: `waitpid` bloquea un hilo y el pool cooperativo no es lugar para estacionarlo [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:137]
- `run` lanza el proceso (spawn) antes de llamar a `wait`, asi que una tarea que no consigue hilo tampoco lanza su shell [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:60]
- `run` llama a `wait` despues del spawn y de abrir los drenajes [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:83]
- `run` acepta un `registry` inyectable, por defecto el compartido [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:47]
- `run` devuelve `refusedByCap` sin ejecutar nada cuando el techo esta lleno [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:49]
- El techo por defecto del registro es 8 procesos [repo:Sources/CompanionServices/Delegation/ProcessRegistry.swift:14]
- El registro se puede crear con otro techo, `package init(cap:)` [repo:Sources/CompanionServices/Delegation/ProcessRegistry.swift:23]
- Los tests ya crean registros propios con techo explicito [repo:Tests/CompanionServicesTests/ProcessRegistryTests.swift:17]
- Los drenajes de stdout/stderr leen en `DispatchQueue.global`, fuera del pool cooperativo [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:191]
- `terminateGroup` sigue usando un bucle con `usleep` de hasta 0,25 s; queda fuera de este cambio [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:171]
- El test actual lanza dos `sleep 0.4` con `async let` [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:79]
- Y exige que terminen en menos de 0,75 s de reloj de pared [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:83]
- El helper `sh` usa el registro compartido y pasa el comando como texto de `-c` [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:20]
- `processGroupTests` corre los subtests en serie dentro de un solo `@Test @MainActor` [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:6]
- `CompanionServices` se declara sin `swiftSettings`: ni aislamiento por defecto ni features futuras [repo:Package.swift:24]
- La arquitectura prohibe que un `DispatchSemaphore` bloquee un contexto async [repo:docs/ARCHITECTURE.md:80]
- En CI, Gate 4 corre `swift test --no-parallel` porque helpers con semaforos matan de hambre al pool en un runner de 3 vCPU [repo:scripts/gates.sh:259]
- La bandera serial solo se pone con `CI=true`; en local la suite corre en paralelo [repo:scripts/gates.sh:266]
- `tsan.sh` corre siempre en serie por la misma razon [repo:scripts/tsan.sh:15]
- CI corre en `macos-26` [repo:.github/workflows/ci.yml:30]
- Los tests de este target crean directorios temporales con UUID y los borran con `defer` [repo:Tests/CompanionServicesTests/MemoryTests.swift:73]
Contextos: (1) `swift test` local en paralelo (Mac de Karen, mas de 3 nucleos, compartida); (2) job `gates` de CI en macos-26, 3 vCPU, `--no-parallel`; (3) job TSan (`scripts/tsan.sh`), serie y mas lento; (4) la app empaquetada, donde `run` lo llaman los ejecutores de delegacion; el cambio es solo de test y no la toca; (5) solo con la opcion B, un paso de CI nuevo con `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`.

## 3. Fuentes primarias

- Apple, WWDC21 "Swift concurrency: Behind the scenes": el pool nuevo "will only spawn as many threads as there are CPU cores" [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@WWDC21]
- La misma charla: semaforos y variables de condicion son inseguros porque esconden la dependencia al runtime y violan el contrato de progreso [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@WWDC21]
- La misma charla recomienda "testing your apps" con una variable de entorno que fuerza el invariante de progreso; un hilo del pool colgado delata una primitiva bloqueante [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@WWDC21]
- Apple DTS (Quinn), foro de desarrolladores: el pool tiene "a very limited size, typically one thread per core", y una funcion async no debe bloquear su hilo [doc:https://developer.apple.com/forums/thread/708664@2022]
- Runtime de Swift: el ejecutor global en Apple pide `dispatch_get_global_queue` con la bandera cooperativa, y cae a una cola global normal si dispatch no la soporta [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L184@swift-6.3.3-RELEASE]
- `SWIFT_DEBUG_CONCURRENCY_ENABLE_COOPERATIVE_QUEUES` (por defecto true) apaga las colas cooperativas; esta fuera del bloque `#ifndef NDEBUG`, asi que existe en runtimes de release [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/runtime/EnvironmentVariables.def#L70@swift-6.3.3-RELEASE]
- libdispatch lee `LIBDISPATCH_COOPERATIVE_POOL_STRICT` del entorno al inicializarse [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/queue.c#L8767@libdispatch-1542.0.4]
- Con macOS 12 o mas y soporte del kernel, libdispatch usa la workqueue cooperativa del kernel (`DISPATCH_USE_COOPERATIVE_WORKQUEUE 1`) [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/internal.h#L750@libdispatch-1542.0.4]
- En ese camino, el modo estricto no fija un ancho en libdispatch: pide al kernel `kern.wq_limit_cooperative_threads = -1`, "strict per QoS bucket" [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/queue.c#L8700@libdispatch-1542.0.4]
- El ancho `max_cpus` (o 1 en estricto) solo lo calcula libdispatch en el camino de respaldo sin workqueue cooperativa [doc:https://github.com/apple-oss-distributions/libdispatch/blob/2361ffb78a76f7ee488cd052eb0bc5c767118bf9/src/queue.c#L8592@libdispatch-1542.0.4]
- Kernel (xnu): el ancho del pool cooperativo es `wq_max_cooperative_threads = num_cpus` [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L2121@xnu-12377.1.9]
- Ese `num_cpus` sale de `ml_wait_max_cpus()` [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L2094@xnu-12377.1.9]
- `ml_wait_max_cpus()` devuelve `machine_info.max_cpus` [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/osfmk/arm/machine_routines_common.c#L1366@xnu-12377.1.9]
- El sysctl `hw.ncpu` devuelve `max_cpus`; `hw.activecpu` devuelve `avail_cpus`, que es otro campo [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_mib.c#L340@xnu-12377.1.9]
- El kernel lo declara "not a hard limit": el pool puede sobresuscribirse hasta `wq_max_cooperative_threads * WORKQ_NUM_QOS_BUCKETS` en total, repartido entre buckets de QoS [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L153@xnu-12377.1.9]
- La admision niega un hilo nuevo cuando los hilos programados en ese QoS o mayores ya llegan al ancho [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L1610@xnu-12377.1.9]
- La unica excepcion: un bucket con trabajo pendiente y cero hilos recibe uno [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L1596@xnu-12377.1.9]
- Cuando un hilo de la workqueue se bloquea, el callback solo descuenta la contabilidad del pool restringido (`_wq_thactive_dec`), no la del cooperativo; un hilo cooperativo bloqueado sigue contando [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L1956@xnu-12377.1.9]
- El sysctl `kern.wq_limit_cooperative_threads` solo acepta 0 (por defecto) o -1 (estricto por bucket) [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L201@xnu-12377.1.9]
- Y lo rechaza con `ENOTSUP` si la workqueue del proceso ya tiene peticiones o hilos [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L221@xnu-12377.1.9]
- Respuesta (1), ancho: es el numero de CPUs que el kernel llama `max_cpus`, por bucket de QoS acumulado, no un tope duro global; no hay API publica que devuelva el ancho del pool [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L2121@xnu-12377.1.9]
- Respuesta (1), API: `ProcessInfo.processorCount` es `hw.ncpu`, es decir `max_cpus`, el mismo valor que usa el kernel [doc:https://developer.apple.com/documentation/foundation/processinfo/processorcount@macOS-26]
- `activeProcessorCount` NO es ese valor: Apple dice que refleja los nucleos activos (`hw.logicalcpu`) y que puede ser menor por boot-args, throttling termico o defecto de fabrica [doc:https://developer.apple.com/documentation/foundation/processinfo/activeprocessorcount@macOS-26]
- SE-0461: sin la feature futura `NonisolatedNonsendingByDefault`, una funcion async `nonisolated` es `@concurrent` y corre en el ejecutor generico, no en el actor de quien llama [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- SE-0417: dentro de `withTaskExecutorPreference`, funciones async `nonisolated`, hijos de `TaskGroup` y `async let` corren en el ejecutor preferido; no especifica a donde reanuda `Task.sleep` [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0417-task-executor-preference.md@6.0]
- GitHub: el runner estandar `macos-26` arm64 tiene 3 CPU (M1) y 7 GB de RAM [doc:https://docs.github.com/en/actions/reference/runners/github-hosted-runners@2026-10-01]
- Respuesta (2), precedente documentado: la unica tecnica que Apple documenta para detectar un bloqueo del pool en pruebas es correr con el pool estricto y tratar un hilo colgado como el fallo; respalda la opcion B, no la A [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@WWDC21]
- Respuesta (2), sin precedente: ninguna fuente primaria leida (WWDC21, runtime de Swift, libdispatch, xnu, SE-0417, foro de Apple) documenta un test de barrera con mas operaciones que hilos; la opcion A es diseno propio [doc:https://developer.apple.com/videos/play/wwdc2021/10254/@WWDC21]

## 4. Implementaciones de referencia

- swift-build (swiftlang, el motor de build de SwiftPM/Xcode): exige, antes de mover trabajo a una tarea de Swift, comprobar que no hay deadlock con `LIBDISPATCH_COOPERATIVE_POOL_STRICT`; usa la variable como prueba, igual que la opcion B [ref:https://github.com/swiftlang/swift-build/blob/2111547197302121c4eff0789cd968ee17f92380/Sources/SWBTaskExecution/DynamicTaskSpecs/CompilationCachingDataPruner.swift#L103@2111547]
- MachOSwiftSection (328 estrellas, activo hoy): tras la suite normal, re-corre en CI dos suites con `LIBDISPATCH_COOPERATIVE_POOL_STRICT: 1`, porque en un runner de 3 nucleos tres tests bloqueantes congelaron el proceso; es la opcion B ya en produccion [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L125@fc27627]
- Ese paso lleva `timeout-minutes: 5`, que convierte el cuelgue en fallo [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L135@fc27627]
- El mismo proyecto excluye de ese paso los tests que prueban solapamiento, porque necesitan dos hilos por diseno [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L132@fc27627]
- RoamRun (3 estrellas, pista, no estandar): lanza `activeProcessorCount * 2` esperas de 1 s y exige que tarden menos de 1,8 s; es la idea de "mas que el ancho" de la opcion A, pero con asercion de reloj [ref:https://github.com/mh-mobile/RoamRun/blob/988a7623cc289b6ef24b65890bcf7c7df5b883b6/Tests/RoamRunTests/RoamRunTests.swift#L287@988a762]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Barrera en el test normal: N = `processorCount + 2` shells, cada uno crea su marcador y espera, acotado (unos 20 s), a ver los N; se exige `exitCode == 0` en todos y se borra la asercion de tiempo | Mide el hecho, no un proxy; resiste el SIGSTOP; detecta en cualquier Mac sin tocar CI | Diseno propio, sin precedente documentado; el ancho no es tope duro; en local una suite paralela que bloquee el pool mas de 20 s daria falso rojo | baja, ~28 lineas que sustituyen 10 | Solo si Karen acepta un patron propio |
| B. Barrera de 2 shells en el test, y un paso de CI aparte que corre `processGroupTests` con `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` y timeout de paso (patron MachOSwiftSection) | Tecnica que Apple documenta y que swift-build y MachOSwiftSection usan; ancho 1 por bucket, asi que N = 2 basta y no depende de nucleos | Toca CI (escala siempre); hay que filtrar, porque la suite entera bajo estricto se colgaria por los helpers con semaforos; la deteccion solo ocurre en ese paso, no en `swift test` local | media, ~20 lineas de test + ~8 de workflow | Si, por la regla de patron documentado; decide Karen porque toca CI |
| C. Ejecutor de tareas propio de un solo hilo y `withTaskExecutorPreference` | Ancho 1 en proceso, sin CI | ~25 lineas extra; SE-0417 no dice donde reanuda `Task.sleep`; sin precedente | media | No |
| D. Relajar el umbral de tiempo | Una linea | Sigue siendo reloj; no detecta en multinucleo | baja | No |

## 6. Evidencia en contra

- Contra B: la suite tiene helpers que bloquean hilos con semaforos; bajo pool estricto, correrla entera colgaria el proceso [repo:scripts/gates.sh:259]
- Se resuelve como MachOSwiftSection: el paso estricto filtra a `processGroupTests` y lleva su propio timeout [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L125@fc27627]
- Contra B: el paso estricto es un cambio de CI, que la casa escala siempre; se acepta y se lleva a Karen (seccion 9) [repo:.github/workflows/ci.yml:30]
- Contra A: el kernel declara el ancho "not a hard limit" y permite sobresuscribir entre buckets; si las N tareas cayeran en buckets distintos, una espera bloqueante pasaria el test [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L153@xnu-12377.1.9]
- Dentro de un mismo bucket la admision corta al llegar al ancho; lo que queda se cierra con el RED obligatorio [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L1610@xnu-12377.1.9]
- Contra A en la direccion verde: en local la suite corre en paralelo y helpers con semaforos pueden ocupar el pool mas que el plazo del shell [repo:scripts/gates.sh:259]

## 7. Ejemplares y anti-ejemplos

- Anti-ejemplo: asercion de reloj de pared como proxy de concurrencia [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:83]
- Anti-ejemplo externo, misma idea de N mayor que el ancho pero con umbral de 1,8 s [ref:https://github.com/mh-mobile/RoamRun/blob/988a7623cc289b6ef24b65890bcf7c7df5b883b6/Tests/RoamRunTests/RoamRunTests.swift#L294@988a762]
- Ejemplar de la casa: esperar el hecho del mundo y no un proxy, opcion B del brief hermano [repo:docs/research/tests-orden-no-prometido.md:120]
- Ejemplar externo de la opcion B: paso de CI con el pool estricto, filtrado y con timeout propio [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L137@fc27627]
- Boceto de la barrera, sin compilar, que reemplazaria el test de esta linea; con B, `n` es 2; con A, `processorCount + 2` [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:75]

```swift
@MainActor func testTheWaitDoesNotBlockTheCaller() async {
    // Option A: n = processorCount + 2 (more waits than pool threads).
    // Option B: n = 2, and CI reruns this under LIBDISPATCH_COOPERATIVE_POOL_STRICT=1.
    let n = ProcessInfo.processInfo.processorCount + 2
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("pgwait-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    catch { Issue.record("no temp dir: \(error)"); return }
    defer { try? FileManager.default.removeItem(at: dir) }
    let registry = ProcessRegistry(cap: n)
    let script = """
        touch "$1/$2"; i=0
        while [ $(ls "$1" | wc -l) -lt "$3" ]; do
          i=$((i+1)); [ "$i" -gt 400 ] && exit 7; sleep 0.05
        done
        """
    let outcomes = await withTaskGroup(of: ShellOutcome.self) { group in
        for i in 0..<n {
            group.addTask {
                await ProcessGroupRunner.run(
                    executable: "/bin/sh",
                    arguments: ["-c", script, "sh", dir.path, "\(i)", "\(n)"],
                    cwd: nil, timeout: 60, registry: registry)
            }
        }
        return await group.reduce(into: []) { $0.append($1) }
    }
    expectEq(outcomes.count, n, "every wait returned")
    for o in outcomes { expectEq(o.exitCode, 0, "all \(n) reached the barrier: \(o.stderr)") }
}
```

## 8. Trampas

- Usar `activeProcessorCount` en vez de `processorCount` (opcion A): si hay nucleos inactivos, N puede quedar por debajo del ancho real y el test deja de detectar [doc:https://developer.apple.com/documentation/foundation/processinfo/activeprocessorcount@macOS-26]
- Usar el registro compartido: con techo 8, en una Mac de 7 o mas nucleos las ultimas tareas de A vuelven `refusedByCap` [repo:Sources/CompanionServices/Delegation/ProcessRegistry.swift:14]
- Si `CompanionServices` adopta `NonisolatedNonsendingByDefault`, `run` llamado directo desde `@MainActor` heredaria el MainActor; por eso el boceto usa `TaskGroup.addTask` [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md@6.2]
- `SWIFT_DEBUG_CONCURRENCY_ENABLE_COOPERATIVE_QUEUES=0` en el entorno cambia el ejecutor a una cola global normal; con eso una espera bloqueante pasaria A y B [doc:https://github.com/swiftlang/swift/blob/064859e41d68596f486c5d724401cb370f260409/stdlib/public/Concurrency/DispatchGlobalExecutor.cpp#L184@swift-6.3.3-RELEASE]
- Opcion B: la variable estricta solo surte efecto en el entorno al arrancar el proceso; el kernel rechaza el cambio en cuanto la workqueue tiene hilos, asi que va en el `env:` del paso, no dentro del test [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L221@xnu-12377.1.9]
- Opcion B: sin timeout de paso, un bloqueo cuelga el job hasta el timeout del job entero; MachOSwiftSection pone 5 min [ref:https://github.com/MxIris-Reverse-Engineering/MachOSwiftSection/blob/fc27627ec24b3f12a7ff9e86db603e6725ec85ff/.github/workflows/macOS.yml#L135@fc27627]
- Opcion B: en la corrida normal, con N = 2 en una Mac multinucleo la barrera pasa aunque la espera bloquee; la deteccion vive solo en el paso estricto [doc:https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/pthread/pthread_workqueue.c#L2121@xnu-12377.1.9]
- Contexto (2), CI: con 3 CPU, A son 5 shells `sh` + `sleep`; carga trivial frente a 7 GB [doc:https://docs.github.com/en/actions/reference/runners/github-hosted-runners@2026-10-01]
- Contexto (2), CI: Gate 4 corre en serie, asi que ningun otro test compite por el pool durante la barrera [repo:scripts/gates.sh:266]
- Contexto (1), local: suite en paralelo; el plazo de 20 s absorbe la competencia normal [repo:scripts/gates.sh:265]
- Contexto (3), TSan: en serie y mas lento; el spawn de N procesos no depende del sanitizer [repo:scripts/tsan.sh:15]
- Contexto (4), app: el cambio es solo de test; `wait` y `run` no cambian [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:139]
- Limpieza: con espera bloqueante, los shells salen solos a los ~20 s con codigo 7 y, si no, `run` mata el grupo al vencer su timeout; el `defer` borra el directorio cuando ya volvieron todos [repo:Sources/CompanionServices/Delegation/ProcessGroup.swift:84]
- Rutas: hoy el helper `sh` mete el comando en el texto de `-c`; el boceto pasa directorio e indices como `$1 $2 $3` [repo:Tests/CompanionServicesTests/ProcessGroupTests.swift:20]

## 9. Incertidumbre

- Respuesta (1): el ancho del pool es `max_cpus` (= `hw.ncpu` = `ProcessInfo.processorCount`) segun xnu-12377.1.9 y la doc de Apple; no hay API publica que devuelva el ancho, y `activeProcessorCount` no es ese valor.
- Respuesta (2), precedente que SI existe y respalda la opcion B: WWDC21 10254 recomienda probar con `LIBDISPATCH_COOPERATIVE_POOL_STRICT` y leer un hilo del pool colgado como bloqueo; swift-build lo exige como chequeo (CompilationCachingDataPruner.swift:103); MachOSwiftSection lo corre como paso de CI filtrado con timeout (.github/workflows/macOS.yml:125-137).
- Respuesta (2), precedente que NO existe para la opcion A: barrera de N tareas por encima del ancho del pool, sin reloj. Donde se busco: swift-nio (busqueda de codigo de "cooperative pool", "COOPERATIVE_POOL", "forward progress"; solo aparece la doc de `NIOThreadPool` para trabajo bloqueante, sin test de pool); swift-async-algorithms ("cooperative": solo comentarios de cancelacion); swiftlang/swift `test/Concurrency/Runtime` en swift-6.3.3-RELEASE (131 archivos, ninguno de saturacion o deteccion de bloqueo; "cooperative" solo en task_immediate_mainactor_isolation.swift y async_task_locals_copy_to_sync.swift); `LIBDISPATCH_COOPERATIVE_POOL_STRICT` en swift-nio, swift-async-algorithms, swiftlang/swift, swift-testing, swift-foundation y swift-package-manager: cero resultados; foros: Swift Forums 70685 (Ole Begemann observa el cuelgue con hijos >= hilos, sin test) y Apple Developer Forums 708664 (Quinn: ancho tipicamente un hilo por nucleo, sin test); RoamRun usa la idea de A pero con asercion de reloj.
- ASSUMPTION: xnu-12377.1.9 y libdispatch-1542.0.4 se comportan como el macOS 26 instalado aqui y en el runner. prueba: `uname -v` y `sysctl hw.ncpu hw.activecpu` en las dos maquinas, y el RED de abajo.
- ASSUMPTION: la barrera es determinista en las dos direcciones (rojo con espera bloqueante, verde con sondeo), en A con el pool normal y en B con el estricto; deducido del codigo del kernel, no observado. prueba: RED reponiendo temporalmente un bucle `usleep` en `wait` (B: el paso estricto debe fallar; A: la corrida normal debe fallar con codigo 7), luego GREEN con el codigo actual y bajo el SIGSTOP de 1 s que hoy falla 5/5.
- ASSUMPTION: los hijos de `addTask` caen en un solo bucket de QoS, asi que en A no hay sobresuscripcion entre buckets. prueba: el RED anterior; si A pasa con la espera bloqueante, subir N o quedarse con B.
- ASSUMPTION: el boceto compila tal cual (`reduce(into:)` sobre `TaskGroup`, `expectEq` con `Int32?`, `wc -l` sin comillas en `[ ]`). prueba: compilarlo y correrlo en la rama del cambio; no se compilo aqui porque la Mac es compartida.
- [NEEDS CLARIFICATION: Karen, A (barrera por encima del ancho en el test normal, sin CI, diseno propio) o B (barrera de 2 y paso de CI con `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` filtrado a `processGroupTests` con timeout, patron documentado por Apple y usado por swift-build y MachOSwiftSection, pero toca CI)? La regla de patron documentado apunta a B.]

## 10. Checklist de estandar

- [ ] El test no contiene ninguna asercion de tiempo transcurrido.
- [ ] Con A, N sale de `ProcessInfo.processInfo.processorCount` mas un margen de al menos 2; con B, N = 2 y el paso de CI fija `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` en su `env:`.
- [ ] Con B, el paso estricto filtra a `processGroupTests`, reutiliza el build y tiene timeout propio.
- [ ] Las corridas usan un `ProcessRegistry(cap: n)` propio, no el compartido.
- [ ] Las tareas se lanzan con `TaskGroup.addTask`, no con `run` llamado directo desde el MainActor.
- [ ] Cada shell espera acotado (unos 20 s) y sale con un codigo distinto de 0 si no ve los N marcadores; el timeout de `run` es mayor que ese plazo.
- [ ] Se exige `exitCode == 0` en las N corridas y que volvieron N resultados.
- [ ] Rutas e indices viajan como argumentos posicionales de `sh -c`.
- [ ] El directorio temporal lleva UUID y se borra con `defer`.
- [ ] RED documentado: con un bucle `usleep` repuesto en `wait`, el test falla en el contexto que detecta (A: normal; B: paso estricto); con el codigo actual pasa, tambien bajo SIGSTOP de 1 s.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Swift concurrency: Behind the scenes | Apple | WWDC21 | 2026-10-01 | high |
| 2 | Developer Forums thread 708664 (respuesta de Quinn, DTS) | Apple | 2022 | 2026-10-01 | medium |
| 3 | pthread_workqueue.c, kern_mib.c, machine_routines_common.c | Apple (xnu) | xnu-12377.1.9 | 2026-10-01 | high |
| 4 | queue.c, internal.h | Apple (libdispatch) | libdispatch-1542.0.4 | 2026-10-01 | high |
| 5 | DispatchGlobalExecutor.cpp, EnvironmentVariables.def | swiftlang/swift | swift-6.3.3-RELEASE | 2026-10-01 | high |
| 6 | ProcessInfo.processorCount, activeProcessorCount | Apple Developer Documentation | macOS 26 | 2026-10-01 | high |
| 7 | SE-0461 Async function isolation | Swift Evolution | Swift 6.2 | 2026-10-01 | high |
| 8 | SE-0417 Task executor preference | Swift Evolution | Swift 6.0 | 2026-10-01 | high |
| 9 | GitHub-hosted runners reference | GitHub Docs | 2026-10-01 | 2026-10-01 | high |
| 10 | CompilationCachingDataPruner.swift | swiftlang/swift-build | 2111547 | 2026-10-01 | medium |
| 11 | macOS.yml (paso con pool estricto) | MxIris-Reverse-Engineering/MachOSwiftSection | fc27627 | 2026-10-01 | medium |
| 12 | RoamRunTests.swift | mh-mobile/RoamRun | 988a762 | 2026-10-01 | low |
| 13 | Cooperative pool deadlock when calling into an opaque subsystem | Swift Forums | 2024 | 2026-10-01 | low |
| 14 | tests-orden-no-prometido | companion-next docs/research | 2026-10-01 | 2026-10-01 | high |

[KAREN:chat 2026-10-01] Opcion B (paso de CI con LIBDISPATCH_COOPERATIVE_POOL_STRICT, precedente swift-build y MachOSwiftSection). Acepto que la deteccion sea solo en ese paso de CI. No hace falta confirmar la slide de WWDC.
