# Reference Brief: gate de ThreadSanitizer en CI para companion-next

Slug: tsan-gate-ci | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

Decision de Karen (2026-09-30): (a) informativo ya con continue-on-error, requerido tras el arreglo de ClassicRuntime y N=5 corridas limpias; al promover, gates y tsan como checks requeridos; cero supresiones en produccion; A' scripts/tsan.sh invocado por ci.yml; sigpipeCount como `Atomic` de Int en un let global con import Synchronization solo en tests; timeout-minutes 45 y medicion en la primera corrida. [KAREN:chat 2026-09-30 via orquestador]

Ratificado por Karen (2026-10-01): el Estado APROBADO de este brief lo escribio un agente con la decision de Karen relayada; Karen lo ratifico despues de mergear #70 ("perfecto, ratificado"). [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Cambio: agregar `swift test --sanitize=thread` como gate de CI, en un PR propio. TSan fue el oraculo de la carrera del bridge: las corridas normales nunca la reprodujeron, y TSan mostro 3 de 500 callbacks perdidos mas sus avisos. Segun la peticion de la sesion orquestadora, Karen aprobo el gate como PR aparte; los archivos citados no registran esa frase textual, asi que este brief no la etiqueta como palabra de Karen.

ESCALAR SIEMPRE: este cambio toca los gates de CI (`.github/workflows/ci.yml`). Aunque el verificador de AUTO, la decision final es de Karen.

Decisiones a tomar:

1. Tiempo de la suite completa bajo TSan en el runner `macos-26` frente a local, y el `timeout-minutes` del job.
2. Suite completa o un subconjunto filtrado (voz, bridge, concurrencia).
3. Un job de CI aparte o un paso dentro de `scripts/gates.sh`.
4. Aislamiento del build: el mismo `.build`, `--scratch-path` o un runner propio.
5. Que hacer con las carreras conocidas: fallar ante cualquier aviso, archivo de supresiones, rasgos de Swift Testing o exclusion por filtro. Incluye como arreglar en este PR la carrera del helper de test `sigpipeCount`.
6. Check requerido o informativo al principio, y el criterio para promoverlo.

Hechos de esta sesion que condicionan todo (detalle y procedencia en las secciones 2, 8 y 9):

- Con `--scratch-path` la suite da unos 555 fallos de textos devueltos como claves, con TSan y sin TSan. La causa es un bug latente de `ResourceBundleLocator`; ese bug va a su propio arreglo y no entra en este PR.
- En el `.build` por defecto y en serie, TSan pasa los 1529 tests en 95 s, pero el proceso sale distinto de 0 por 3 avisos: una carrera de produccion nueva en `ClassicRuntime` y dos sobre el global de test `sigpipeCount`.
- Politica que fija la peticion, sin cita de Karen: ninguna supresion para carreras de produccion. La carrera de `ClassicRuntime` va a su propio arreglo. La de `sigpipeCount` se arregla en este PR, solo en tests.
- `grep -rn "import Synchronization" Sources Tests` no devuelve nada: el repo todavia no usa ese modulo.
- Branch protection de `main` (GET a la API de GitHub, 2026-09-30): existe, pero no define `required_status_checks`. Hoy ningun check es requerido para mergear, ni siquiera `gates`.
- Un `swift build --sanitize=thread` lanzado en paralelo con la suite en el mismo `.build` provoco un falso fallo en `BrowserHostRelayHardeningTests` (reporte de la sesion orquestadora, sin log). Ver la seccion 9.

## 2. Estado actual

- CI tiene un unico job `gates` [repo:.github/workflows/ci.yml:9]
- Ese job corre en `macos-26` [repo:.github/workflows/ci.yml:15]
- El job ejecuta el mismo script que se corre en local [repo:.github/workflows/ci.yml:21]
- El comentario del workflow fija el principio "Same script contributors run locally, no CI-only pipeline" [repo:.github/workflows/ci.yml:11]
- `gates.sh` corre la suite en serie solo en CI, porque con 3 vCPU y los semaforos de los helpers el pool cooperativo se muere de inanicion (HACK) [repo:scripts/gates.sh:238]
- El flag `--no-parallel` se agrega solo cuando `CI=true` [repo:scripts/gates.sh:245]
- `gates.sh` invoca `swift test` sin sanitizer, en el `.build` por defecto [repo:scripts/gates.sh:246]
- Package.swift declara `swift-tools-version: 6.2` [repo:Package.swift:1]
- Package.swift fija la plataforma minima en macOS 26 [repo:Package.swift:9]
- El toolchain real, local y en el runner, es Apple Swift 6.3.3 [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:34]
- El job `gates` en el runner tardo unos 6 min: build de unos 64 s y Gate 4 de unos 4 min 42 s, con la suite en serie y 1514 tests [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:36]
- Esa corrida espero unos 17 min en cola antes de que arrancara el job [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:38]
- `ResourceBundleLocator.defaultBuildDirectory` arma la ruta `checkout/.build/debug` desde `#filePath` [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:68]
- El HACK de esa propiedad admite que un build con `--scratch-path` no encuentra nada ahi y degrada a nil [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:54]
- `UIResourceBundle.resolve` usa esa ruta como valor por defecto [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:28]
- `ServicesResourceBundle.resolve` hace lo mismo [repo:Sources/CompanionServices/Platform/ServicesResourceBundle.swift:24]
- Si no hay `.app` ni bundle junto al ejecutable, el localizador solo prueba `buildDirectory` y si no lo encuentra devuelve nil [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:39]
- Con nil, la UI registra "raw copy keys": los textos salen como claves [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:20]
- Medicion local con `--scratch-path .build-plain` y sin sanitizer: 555 issues en 1529 tests [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:18]
- La misma suite con `--scratch-path .build-tsan` y TSan: 558 issues en 1529 tests [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:8]
- Ejemplo de esos fallos: `BridgeUITests` recibe "island.hands.stop" donde espera "Stop hands" [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:14]
- TSan en el `.build` por defecto y en serie: los 1529 tests pasan en 95,2 s, con 1 known issue [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:24]
- En esa misma corrida TSan reporto 3 avisos [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:25]
- El helper de Swift Testing termino con la senal 6, asi que el proceso sale en rojo aunque cada test este en verde [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:26]
- El producto de test de esa corrida vive en `.build/arm64-apple-macosx/debug`, la misma carpeta que el build sin sanitizer [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:26]
- Aviso de produccion: escritura en `ClassicRuntime.submit` (ClassicRuntime.swift:285) contra lectura en `ClassicRuntime.speak` (+Mouth.swift:138), desde dos hilos de GCD [repo:docs/research/evidence/tsan-classicruntime-submit-speak.txt:1]
- La linea 285 es `cardThisTurn = false` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:285]
- La linea 138 de +Mouth lee `cardThisTurn` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime+Mouth.swift:138]
- `ClassicRuntime` es una `final class @unchecked Sendable` [repo:Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift:6]
- `sigpipeCount` es un global `nonisolated(unsafe) var` [repo:Tests/CompanionTests/BrowserListenerTests.swift:16]
- El handler de SIGPIPE lo incrementa [repo:Tests/CompanionTests/BrowserListenerTests.swift:18]
- `withSigpipeCounter` lo pone en 0 desde un hilo del pool [repo:Tests/CompanionTests/BrowserListenerTests.swift:45]
- `waitForSigpipes` lo lee en un bucle de sondeo [repo:Tests/CompanionTests/BrowserListenerTests.swift:52]
- Los tests de SIGPIPE ya comparten una suite `.serialized`, porque la disposicion de la senal es global al proceso [repo:Tests/CompanionTests/BrowserListenerTests.swift:14]
- En la corrida del `.build` por defecto, ninguno de los cinco tests sospechosos (earReview, mentionSelectorTabDuringDialog, processRegistry, utteranceLogPrivacy, mcpTools) produjo un aviso de TSan [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:30]
- En otra corrida en serie aparecio una carrera mas en un helper de test, `AnalyzerTranscriberTests.swift:152` [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:11]
- La corrida paralela con `--scratch-path` dio 0 avisos de TSan [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:9]
- Los tests son dispatchers: un `@Test` llama varias funciones de caso, como `earReviewTests`, que corre cinco [repo:Tests/CompanionTests/EarReviewTests.swift:9]
- La suite ya usa `withKnownIssue` en un test [repo:Tests/CompanionTests/DecisionDatasetTests.swift:290]
- La spec suite-estable, aprobada por Karen (linea 3), deja "TSan como gate" como opcional "si su tiempo lo permite" [repo:docs/specs/suite-estable.md:71]
- La misma spec registra que TSan es viable como gate opcional, filtrado y con supresiones, y no bloqueante hasta arreglar las carreras de produccion [repo:docs/specs/suite-estable.md:96]
- La spec races-produccion deja fuera los fallos de `processRegistryTests` y `earReviewTests` vistos una vez bajo TSan [repo:docs/specs/races-produccion.md:79]
- El brief del bridge dejo abierta la pregunta: TSan en `gates.sh` o como verificacion manual [repo:docs/research/bridge-conexion-arranque-dos-fases.md:159]
- El helper `LockedBox` de TestKit es el primitivo con lock que la suite ya usa para los fakes [repo:Tests/CompanionTests/TestKit.swift:28]
Contextos: (1) job `gates` de CI en macos-26, `swift test --no-parallel` en el `.build` por defecto; (2) el job TSan nuevo, en su propio runner macos-26; (3) `gates.sh` local, con la suite en paralelo y el `.build` del checkout; (4) TSan local a mano, en el mismo checkout que (3) o con `--scratch-path`; (5) worktrees, cada uno con su propio `.build`; (6) la app empaquetada (`bundle.sh`), que TSan no toca pero comparte `ResourceBundleLocator`.

## 3. Fuentes primarias

- Clang TSan: el slowdown tipico es de 5x a 15x y el costo de memoria de 5x a 10x [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- Clang TSan: soporta Darwin arm64 [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- Clang TSan: exige todo el codigo instrumentado; el codigo sin instrumentar, como las librerias del sistema, puede ocultar carreras o dar falsos positivos [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- Apple: TSan cuesta de 2x a 20x en CPU y de 5x a 10x en memoria, y en macOS solo sirve para apps de 64 bits [doc:https://developer.apple.com/tutorials/data/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early.json@macOS26-sdk-docs]
- swift.org: "your tests need to actually exercise multithreaded code, otherwise Thread Sanitizer will not find data races" [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]
- swift.org: TSan necesita build Debug porque usa la informacion de depuracion para describir lo que encuentra [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]
- Guia de servidores de swift.org: correr la suite con `swift test --sanitize=thread` como parte regular de CI [doc:https://github.com/swift-server/guides/blob/main/docs/testing.md@main-2026-09-30]
- Flags de TSan: se pasan por `TSAN_OPTIONS`; `halt_on_error` vale 0 por defecto, asi que TSan sigue y reporta todo [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]
- Flags de TSan: `exitcode` vale 66 por defecto, el codigo de salida cuando hubo reportes [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]
- Flags de TSan: `report_signal_unsafe` vale 1 por defecto y reporta violaciones de async-signal-safety, como un malloc dentro de un handler [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]
- Supresiones de TSan: archivo pasado con `TSAN_OPTIONS=suppressions=ruta`, con tipos `race`, `race_top`, `thread`, `mutex`, `signal`, `deadlock` y `called_from_lib` [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerSuppressions@wiki-2026-09-30]
- Supresiones de TSan: a cada patron se le antepone y se le agrega `*`, y el patron casa con nombres de funcion, de archivo y de variable global del reporte [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerSuppressions@wiki-2026-09-30]
- SwiftPM 6.3.3: con el build system nativo, `buildPath` es `dataPath` mas el nombre de la configuracion; el sanitizer no entra en la ruta [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L245-L262@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: `dataPath` es el scratch directory mas el componente del triple, de nuevo sin el sanitizer [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L914-L916@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: el scratch directory sale de `--scratch-path`, y si falta, de `paquete/.build` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L390-L393@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: cada comando toma un lock exclusivo sobre el scratch directory y espera si otro SwiftPM lo tiene [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L1156-L1185@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: el lock se suelta cuando el comando termina, despues de `run`, que en `swift test` incluye ejecutar los tests [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L123-L146@swift-6.3.3-RELEASE]
- SwiftPM issue 9748: `--sanitize=thread` justo despues de `--sanitize=address` fallaba al enlazar simbolos de ASan; los mantenedores lo atribuyeron a que SwiftPM no invalidaba los productos [doc:https://github.com/swiftlang/swift-package-manager/issues/9748@closed-2023-12-11]
- En ese mismo issue, el autor reporto que con toolchains 5.9 ya funcionaba; la evidencia es historica [doc:https://github.com/swiftlang/swift-package-manager/issues/9748@closed-2023-12-11]
- GitHub: los runners arm64 `macos-26` tienen 3 CPU (M1), 7 GB de RAM y 14 GB de SSD, tanto en repos publicos como privados [doc:https://docs.github.com/en/actions/reference/runners/github-hosted-runners@2026-09-30]
- GitHub: `jobs.ID.timeout-minutes` vale 360 por defecto [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@github-docs-10844e1]
- GitHub: `jobs.ID.continue-on-error: true` deja pasar la corrida del workflow cuando ese job falla [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@github-docs-10844e1]
- GitHub: un check requerido debe terminar en `successful`, `skipped` o `neutral`, y repetir el mismo nombre de job en varios workflows vuelve ambiguo el check [doc:https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches@2026-09-30]
- GitHub: Actions es gratis con runners estandar en repos publicos [doc:https://docs.github.com/en/billing/concepts/product-billing/github-actions@2026-09-30]
- GitHub: en los planes Free y Pro corren a lo sumo 5 jobs macOS a la vez [doc:https://docs.github.com/en/actions/reference/limits@2026-09-30]
- Corrida real del job `gates` en el runner, que da los tiempos de base [doc:https://github.com/karenrebecag/Companion/actions/runs/36795743537@run-36795743537]
- Swift Testing: `withKnownIssue` vuelve "known" los issues registrados dentro de su closure y los errores que esta lanza, y el test no queda como fallo [doc:https://developer.apple.com/tutorials/data/documentation/testing/known-issues.json@swift-testing-current]
- Swift Testing: `.disabled()` desactiva un test sin condicion y `.enabled(if:)` lo desactiva si la condicion es falsa [doc:https://developer.apple.com/tutorials/data/documentation/testing/enablingandDisabling.json@swift-testing-current]
- C (cppreference): un handler asincrono tiene comportamiento indefinido si toca un objeto estatico que no sea atomico lock-free, salvo asignar a un `volatile sig_atomic_t` [doc:https://en.cppreference.com/w/c/program/signal@C11]
- SE-0410: `Atomic` vive en el modulo `Synchronization`, implementado en Swift 6.0 [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md@Swift-6.0]
- SE-0410: el tipo atomico debe tener una implementacion lock-free en toda plataforma que lo ofrezca [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md@Swift-6.0]
- SE-0410: `Atomic` es `~Copyable` y solo puede declararse con `let`; un `var` de tipo `Atomic` es error de compilacion [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md@Swift-6.0]
- Apple: `Atomic` esta disponible desde macOS 15.0, por debajo del minimo macOS 26 del paquete [doc:https://developer.apple.com/tutorials/data/documentation/synchronization/atomic.json@macOS26-sdk-docs]

## 4. Implementaciones de referencia

- opentelemetry-swift (org OpenTelemetry/CNCF, 366 estrellas, push 2026-10-01): tiene un job `ThreadSanitizer` aparte en `macos-latest` que corre `swift test --sanitize=thread` sin `--scratch-path` [ref:https://github.com/open-telemetry/opentelemetry-swift/blob/1466d2d1d34db9f051154d41339dad42e55b1358/.github/workflows/BuildAndTest.yml#L203-L218@1466d2d1d34db9f051154d41339dad42e55b1358]
- opentelemetry-swift: el job TSan activa por variable de entorno pruebas de estres de concurrencia que los demas jobs saltan; el subconjunto se suma, no reemplaza a la suite [ref:https://github.com/open-telemetry/opentelemetry-swift/blob/1466d2d1d34db9f051154d41339dad42e55b1358/.github/workflows/BuildAndTest.yml#L214-L218@1466d2d1d34db9f051154d41339dad42e55b1358]
- opentelemetry-swift: un job agregador `required-status-checks` con `if: always()` falla si `ThreadSanitizer` fallo; ese agregador es el unico nombre que hace falta requerir [ref:https://github.com/open-telemetry/opentelemetry-swift/blob/1466d2d1d34db9f051154d41339dad42e55b1358/.github/workflows/BuildAndTest.yml#L219-L248@1466d2d1d34db9f051154d41339dad42e55b1358]
- vapor/ci (workflow reutilizable de la org Vapor, que vapor/vapor fija por sha): la entrada `with_tsan` viene en `true` por defecto [ref:https://github.com/vapor/ci/blob/86063c56edafba6c24009fca0db54a6a3bad4ea3/.github/workflows/run-unit-tests.yml#L25-L29@86063c56edafba6c24009fca0db54a6a3bad4ea3]
- vapor/ci: el job `macos-unit` corre en `macos-26` y mete `--sanitize=thread` en el mismo `swift test` de la suite, en el `.build` por defecto, con `timeout-minutes: 60` [ref:https://github.com/vapor/ci/blob/86063c56edafba6c24009fca0db54a6a3bad4ea3/.github/workflows/run-unit-tests.yml#L227-L262@86063c56edafba6c24009fca0db54a6a3bad4ea3]
- vapor/vapor desactiva ese TSan para su propio repo (`with_tsan: false`); el default no prueba que lo usen en el paquete principal [ref:https://github.com/vapor/vapor/blob/3fe848c28edff6b2db1751bac4d96647a5f4f0de/.github/workflows/test.yml#L43-L46@3fe848c28edff6b2db1751bac4d96647a5f4f0de]
- ordo-one/FuzzyMatch (ordo-one mantiene package-benchmark, 158 estrellas, push 2026-09-23): tiene un workflow `Thread sanitizer` aparte que corre `swift package clean` antes de `swift test --sanitize=thread`, con el comentario "Required to clean build directory before sanitizer!"; corre en Linux, no en macOS [ref:https://github.com/ordo-one/FuzzyMatch/blob/ea09aa7faa3c1832716d1ccdb81dcb83bea89774/.github/workflows/swift-sanitizer-thread.yml#L41-L46@ea09aa7faa3c1832716d1ccdb81dcb83bea89774]

## 5. Opciones

### 5a. Forma del job y aislamiento del build (decisiones 3 y 4)

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Job `tsan` aparte en `ci.yml`, runner `macos-26` propio, `.build` por defecto, `swift test --sanitize=thread --no-parallel` | Su runner tiene un `.build` limpio y por defecto, asi que los textos se encuentran sin tocar el localizador; no comparte binarios con `gates`; corre en paralelo con `gates`; mismo patron que opentelemetry-swift | Otro runner macOS por corrida, otro build en frio y mas cola (tope de 5 jobs macOS a la vez) | baja | Si |
| A'. Igual que A, pero la orden vive en `scripts/tsan.sh` y el job la invoca | Cumple "same script contributors run locally"; Karen o un agente lo corren igual en local | Un archivo mas; en local hay que avisar que no se corre a la vez que `gates.sh` en el mismo checkout | baja | Si, si se quiere respetar el principio del workflow |
| B. Paso dentro de `gates.sh`, despues de Gate 4, en el mismo `.build` | Un solo script y un solo job | Alterna el build con y sin TSan en `.build/arm64-apple-macosx/debug`, con recompilacion total en cada cambio; suma el tiempo de TSan al gate que todos corren en local; un gate rojo por TSan bloquea igual que un test roto | media | No |
| C. Paso en `gates.sh` con `--scratch-path .build-tsan` | Separa los binarios del build normal | Hoy rompe unos 555 tests de textos por el HACK de `ResourceBundleLocator`; tendria que esperar a ese arreglo | media | No hasta arreglar el localizador |
| D. Job aparte con `--scratch-path` | Mismo aislamiento que A | Mismo problema que C, sin ninguna ventaja sobre A en un runner limpio | media | No |

### 5b. Alcance de la suite (decision 2)

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| Suite completa | TSan solo ve lo que se ejecuta; la carrera nueva de `ClassicRuntime` salio de un test de jobs en segundo plano, no de los sospechosos; en local la suite tarda unos 95 s con carga alta | Mas minutos de runner y mas memoria | baja | Si |
| Filtro voz, bridge y concurrencia | Mas rapido | Pierde carreras fuera del filtro; el filtro hay que mantenerlo a mano | baja | No |

### 5c. Carreras conocidas (decision 5)

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| Fallar ante cualquier aviso (exit distinto de 0) | Sin deuda escondida; es la senal que dio el oraculo del bridge | Rojo hasta arreglar `ClassicRuntime` | baja | Si, combinada con el modo informativo de 5d |
| Supresion `race_top` para `ClassicRuntime.submit` | Verde ya | Contradice la politica de cero supresiones en produccion; el patron casa por subcadena y puede tapar carreras nuevas del mismo tipo | baja | No |
| `.disabled` o `withKnownIssue` en el test que dispara la carrera | Nada | El aviso de TSan es del proceso, no un issue de Swift Testing, asi que `withKnownIssue` no lo absorbe; `.disabled` apaga un dispatcher entero y su cobertura | media | No |
| `--skip` del test en el job TSan | Verde ya | Igual que la supresion, pero mas ancho; esconde todo lo que corre ese test | baja | No |
| `sigpipeCount` con `Atomic` de `Synchronization` en un `let` global (en este PR) | Lock-free por contrato de SE-0410, que es lo que C admite en un handler asincrono; sin lock ni malloc dentro del handler | Primer `import Synchronization` del repo, aunque sea del toolchain y no una dependencia | baja | Si |
| `sigpipeCount` como `sig_atomic_t` | Es el tipo POSIX clasico | La regla de C exige `volatile`, que Swift no expresa; un `var` Swift comun sigue siendo acceso no atomico y TSan lo seguiria marcando | baja | No |
| `sigpipeCount` con `LockedBox` o `NSLock` | Ya existe en TestKit | Tomar un lock dentro de un handler de senal no es async-signal-safe y puede trabarse | baja | No |

### 5d. Requerido o informativo (decision 6), las dos que pide la peticion

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| (a) Entra ya como informativo (`continue-on-error: true` en el job) y pasa a requerido cuando se arregle `ClassicRuntime` y cumpla el criterio de promocion | Detecta carreras nuevas desde hoy; el workflow sigue verde; deja medir tiempo y memoria reales del runner antes de exigirlo | Un job rojo informativo se acostumbra a ignorar si se queda asi mucho tiempo | baja | Si, con fecha o issue para promoverlo |
| (b) Espera al arreglo de `ClassicRuntime` y entra directo como requerido | Nunca hay un check rojo tolerado | Sin oraculo hasta ese arreglo; el primer dato del runner llega el mismo dia en que ya bloquea | baja | Valida si el arreglo de `ClassicRuntime` es inminente |

Criterio de promocion propuesto para (a): arreglo de `ClassicRuntime` mergeado, mas N corridas seguidas del job TSan sin avisos en `main` y en los PR (N a decidir por Karen; ver la seccion 9). Despues se quita `continue-on-error` y, si Karen quiere bloqueo real, se agrega el check en branch protection, que hoy no exige ninguno.

## 6. Evidencia en contra

- Contra A (job aparte): duplica el build en frio en un segundo runner macOS, y el job `gates` ya espero unos 17 min en cola. Se acepta: el repo es publico y Actions es gratis ahi, y los dos jobs corren en paralelo; el costo es cola y no dinero [doc:https://docs.github.com/en/billing/concepts/product-billing/github-actions@2026-09-30]
- Contra A, el tope de 5 jobs macOS concurrentes puede alargar la espera cuando hay varios PR a la vez. Se acepta y se mide en las primeras corridas [doc:https://docs.github.com/en/actions/reference/limits@2026-09-30]
- Contra A, el principio del repo es un solo script local igual a CI, sin pipeline exclusivo de CI. Se resuelve con A', donde el job llama a `scripts/tsan.sh` [repo:.github/workflows/ci.yml:11]
- Contra la suite completa: con 2x a 20x de CPU y 5x a 10x de memoria en un runner de 3 CPU y 7 GB, el job puede quedarse sin memoria o pasar del timeout. Queda sin medir en el runner: `timeout-minutes` explicito y medicion en la primera corrida, ver la seccion 9 [doc:https://developer.apple.com/tutorials/data/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early.json@macOS26-sdk-docs]
- Contra la suite completa, los tests con relojes de pared que la spec suite-estable ya marca pueden fallar mas bajo el slowdown de TSan. En la corrida local en serie pasaron los 1529 con carga alta, y si alguno falla se trata en suite-estable, no con exclusiones en el gate [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:24]
- Contra fallar ante cualquier aviso: TSan depende del intercalado; una corrida paralela dio 0 avisos y otra en serie dio un aviso en `AnalyzerTranscriberTests` que la siguiente no dio, asi que un rojo puede ser una carrera vieja que recien aparece. Se acepta: es una carrera real igual, y el modo informativo de (a) absorbe ese ruido inicial [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:11]
- Contra no usar `--scratch-path`: el `.build` compartido mezcla binarios con y sin TSan en la misma carpeta de debug. En el runner propio de A no hay otro build que pisar; en local queda la regla de no correrlos a la vez en el mismo checkout hasta arreglar el localizador [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L245-L262@swift-6.3.3-RELEASE]
- Contra `Atomic` para `sigpipeCount`: SE-0410 no dice nada de async-signal-safety. Se resuelve con la regla de C, que admite objetos atomicos lock-free en un handler, junto con la garantia lock-free de SE-0410; el ultimo paso se comprueba con TSan, ver la seccion 9 [doc:https://en.cppreference.com/w/c/program/signal@C11]
- Contra la opcion (a): un check rojo tolerado normaliza ignorar rojos, justo lo que la spec suite-estable quiso cortar. Se resuelve con un criterio de promocion explicito y fechado, o se elige (b) [repo:docs/specs/suite-estable.md:10]

## 7. Ejemplares y anti-ejemplos

- Asi se ve un job TSan aparte en macOS, sin scratch path, en un proyecto mantenido [ref:https://github.com/open-telemetry/opentelemetry-swift/blob/1466d2d1d34db9f051154d41339dad42e55b1358/.github/workflows/BuildAndTest.yml#L203-L215@1466d2d1d34db9f051154d41339dad42e55b1358]

```yaml
  ThreadSanitizer:
    runs-on: macos-latest
    steps:
    - uses: actions/checkout@...
    - name: Build and Test with Thread Sanitizer
      run: swift test --sanitize=thread
```

- Asi se agrega en un solo check lo que se requiere, sin requerir cada job por su nombre [ref:https://github.com/open-telemetry/opentelemetry-swift/blob/1466d2d1d34db9f051154d41339dad42e55b1358/.github/workflows/BuildAndTest.yml#L219-L232@1466d2d1d34db9f051154d41339dad42e55b1358]
- Forma que sigue de la documentacion de GitHub para la opcion (a), con el job informativo y su techo de tiempo [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@github-docs-10844e1]

```yaml
  tsan:
    runs-on: macos-26
    timeout-minutes: 30          # techo explicito; el default es 360
    continue-on-error: true      # opcion (a); se quita al promover
    steps:
      - uses: actions/checkout@v4
      - run: swift --version
      - run: swift test --sanitize=thread --no-parallel
```

- Asi se ve un contador compartido con un handler de senal, sin lock y sin malloc, con `Atomic` en un `let` global como exige SE-0410 [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0410-atomics.md@Swift-6.0]

```swift
import Synchronization
let sigpipeCount = Atomic<Int>(0)
private func countSigpipe(_ signal: Int32) { sigpipeCount.add(1, ordering: .relaxed) }
// lectores: sigpipeCount.load(ordering: .relaxed); reset: sigpipeCount.store(0, ordering: .relaxed)
```

- Anti-ejemplo: el contador de hoy, un `var` Swift comun que escriben el handler y un hilo del pool, y que TSan marca dos veces [repo:Tests/CompanionTests/BrowserListenerTests.swift:16]
- Anti-ejemplo: alternar sanitizers en el mismo scratch directory sin limpiar; FuzzyMatch limpia antes de cada corrida con sanitizer por ese motivo [ref:https://github.com/ordo-one/FuzzyMatch/blob/ea09aa7faa3c1832716d1ccdb81dcb83bea89774/.github/workflows/swift-sanitizer-thread.yml#L41-L43@ea09aa7faa3c1832716d1ccdb81dcb83bea89774]
- Anti-ejemplo: `--scratch-path` en este repo hoy, que deja 555 tests leyendo claves en lugar de textos [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:18]

## 8. Trampas

- Contexto 2 (job TSan en CI): `--scratch-path` rompe la carga de recursos mientras el localizador fije `.build/debug`; el job tiene que usar el `.build` por defecto [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:54]
- Contexto 2: el runner tiene 3 vCPU y la suite en paralelo se muere de inanicion; el job TSan necesita `--no-parallel`, igual que `gates` [repo:scripts/gates.sh:238]
- Contexto 2: el runner tiene 7 GB de RAM y TSan multiplica la memoria de 5x a 10x; un proceso que muere por memoria se ve como una senal, no como un aviso de TSan [doc:https://docs.github.com/en/actions/reference/runners/github-hosted-runners@2026-09-30]
- Contexto 2: sin `timeout-minutes`, un test colgado bajo TSan retiene el runner hasta 360 min [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@github-docs-10844e1]
- Contexto 2: el rojo de TSan es del proceso. Swift Testing imprime "passed", el helper muere con senal 6 y `swift test` sale distinto de 0; el gate tiene que mirar el codigo de salida, no buscar "✘" en la salida [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:26]
- Contexto 2: `withKnownIssue` solo absorbe issues registrados dentro de su closure, asi que no sirve para silenciar un aviso de TSan [doc:https://developer.apple.com/tutorials/data/documentation/testing/known-issues.json@swift-testing-current]
- Contexto 2: un patron de supresion se rodea de `*` y casa con funcion, archivo o global, asi que `race:ClassicRuntime` taparia cualquier carrera futura de ese tipo [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerSuppressions@wiki-2026-09-30]
- Contexto 2: los nombres de los checks son nombres de job; si el job se llama `gates` o se repite en otro workflow, el check requerido queda ambiguo [doc:https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches@2026-09-30]
- Contexto 2: un job saltado cuenta como aprobado en un check requerido; un filtro por rutas sobre el job TSan lo volveria verde sin correr [doc:https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches@2026-09-30]
- Contexto 1 (job `gates`): no cambia; no se le agrega TSan ni `--scratch-path` [repo:scripts/gates.sh:246]
- Contextos 3 y 4 (local, mismo checkout): con y sin TSan se compila en la misma carpeta de debug, porque el sanitizer no entra en `buildPath`; alternarlos recompila todo, y lanzarlos a la vez es lo que se reporto como falso fallo en `BrowserHostRelayHardeningTests` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L245-L262@swift-6.3.3-RELEASE]
- Contextos 3 y 4: SwiftPM toma un lock exclusivo sobre el scratch directory durante todo el comando, asi que dos comandos sobre el mismo `.build` deberian serializarse; el mecanismo exacto del falso fallo sigue sin explicar, ver la seccion 9 [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L1156-L1185@swift-6.3.3-RELEASE]
- Contexto 4 con `--scratch-path`: hoy no sirve para la suite completa, por los mismos 555 fallos de textos [repo:docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt:20]
- Contexto 5 (worktrees): cada worktree tiene su propio `.build`, asi que TSan en un worktree y `gates.sh` en otro no chocan; `defaultBuildDirectory` se arma desde el `#filePath` de cada checkout [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:58]
- Contexto 6 (app empaquetada): el gate no la toca. El localizador busca primero `Contents/Resources` del `.app`, y TSan exige build Debug, que no es el que se empaqueta [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:31]
- No mezclar ASan y TSan en el mismo scratch directory: historicamente SwiftPM no invalidaba los productos al cambiar de sanitizer [doc:https://github.com/swiftlang/swift-package-manager/issues/9748@closed-2023-12-11]
- Un handler de senal que toma un lock o reserva memoria es inseguro, y `report_signal_unsafe=1` puede reportar el malloc; por eso se descarta `LockedBox` para `sigpipeCount` [doc:https://github.com/google/sanitizers/wiki/ThreadSanitizerFlags@wiki-2026-09-30]
- El codigo de Apple sin instrumentar (Foundation, AVFoundation, GCD) puede ocultar carreras o dar falsos positivos; si un aviso cae solo en frames del sistema, hay que triarlo antes de culpar al codigo propio [doc:https://clang.llvm.org/docs/ThreadSanitizer.html@clang-current]
- Un TSan verde no prueba que no haya carreras; solo dice que no hubo ninguna en los caminos ejecutados [doc:https://www.swift.org/blog/tsan-support-on-linux/@swift.org-blog]

## 9. Incertidumbre

- ASSUMPTION: el job TSan completo (build en frio con TSan mas la suite en serie) cabe en unos 8 a 15 min en el runner `macos-26`. Sale de sumar el job `gates` actual (unos 6 min) y el factor de 2x a 20x; no se midio, y las mediciones locales se tomaron con carga ~19 en 14 cores. prueba: la primera corrida del job en el PR, leyendo los tiempos por paso con `gh api repos/karenrebecag/Companion/actions/runs/ID/jobs`; fijar `timeout-minutes` en 2x lo medido
- ASSUMPTION: la memoria pico de la suite bajo TSan cabe en los 7 GB del runner. prueba: correr la suite como `/usr/bin/time -l swift test --sanitize=thread --no-parallel` en la primera corrida y leer "maximum resident set size"
- ASSUMPTION: un job con `continue-on-error: true` que falla deja el workflow verde, pero su check aparece como fallido en la lista del PR; la doc solo dice lo primero. prueba: la primera corrida de la opcion (a) con la carrera de `ClassicRuntime` todavia presente; mirar el workflow y el check del job en el PR
- ASSUMPTION: `Atomic` (Int) en un `let` global, leido y escrito con `load`, `store` y `add`, deja a TSan sin avisos sobre `sigpipeCount`, y el handler no dispara `report_signal_unsafe`. prueba: `swift test --sanitize=thread --no-parallel --filter SigpipeSensitive` y, si hace falta, la suite completa; cero lineas "WARNING: ThreadSanitizer" que nombren BrowserListenerTests
- ASSUMPTION: Swift no tiene el calificador `volatile`, asi que `sig_atomic_t` no cumple la regla de C desde Swift. prueba: cambiar el global a `sig_atomic_t` en una rama local y correr el filtro de arriba con TSan; si TSan sigue marcando la carrera, queda descartado
- ASSUMPTION: el falso fallo de `BrowserHostRelayHardeningTests` con un build TSan concurrente vino de que un comando pisara los productos de la misma carpeta de debug, aunque el lock de SwiftPM deberia serializarlos (quizas fueron uno despues del otro, o hubo `--ignore-lock`). prueba: en un checkout, lanzar `swift test` y, mientras corre, `swift build --sanitize=thread`; ver si el segundo imprime "Another instance of SwiftPM ... waiting"
- ASSUMPTION: la corrida en serie con `--scratch-path` que termina sin linea de resumen murio por la misma causa de recursos o por la senal 6 de TSan, no por un crash propio de TSan. prueba: repetir la corrida en serie en el `.build` por defecto y comprobar que tiene linea "Test run with"
- ASSUMPTION: la carrera de `AnalyzerTranscriberTests.swift:152` es intermitente y de un helper de test, igual que `sigpipeCount`. prueba: correr `--filter analyzerTranscriberTests` con TSan 10 veces y contar los avisos; si aparece, va a la lista de suite-estable y no a supresiones
- [NEEDS CLARIFICATION: opcion (a), informativo ya y requerido despues del arreglo de `ClassicRuntime`, u opcion (b), esperar a ese arreglo]
- [NEEDS CLARIFICATION: con la opcion (a), cuantas corridas seguidas sin avisos (N) hacen falta para promover, y si "requerido" significa activar el check en branch protection de `main`, que hoy no exige ninguno, ni siquiera `gates`]
- [NEEDS CLARIFICATION: la politica de cero supresiones para carreras de produccion llega en la peticion de la sesion orquestadora; confirmar que es decision de Karen]
- [NEEDS CLARIFICATION: A (orden inline en `ci.yml`) o A' (`scripts/tsan.sh` invocado por el job, siguiendo el principio "same script contributors run locally")]
- Nota de lectura de fuentes: el resumen automatico del issue 9748 de SwiftPM atribuyo a los mantenedores un workaround con `--scratch-path` que el issue no contiene; se releyeron con `gh api` el cuerpo y los comentarios, y el brief cita solo eso. No fue una inyeccion: el resumidor invento contenido. No se detectaron instrucciones inyectadas en ninguna fuente.

## 10. Checklist de estandar

- [ ] `ci.yml` tiene un job TSan aparte de `gates`, con un nombre unico en todos los workflows y `runs-on: macos-26`.
- [ ] El job corre `swift test --sanitize=thread --no-parallel` sobre la suite completa, sin `--filter` ni `--skip`.
- [ ] El job no usa `--scratch-path` mientras `ResourceBundleLocator.defaultBuildDirectory` fije `.build/debug`.
- [ ] El job tiene `timeout-minutes` explicito, fijado despues de la primera medicion en el runner.
- [ ] No hay archivo de supresiones de TSan, ni `TSAN_OPTIONS=suppressions=...`, para codigo de produccion.
- [ ] El gate falla por el codigo de salida de `swift test`, no buscando texto en la salida.
- [ ] `scripts/gates.sh` no cambia; si se elige A', `scripts/tsan.sh` es un script aparte y su cabecera advierte que no se corre a la vez que `gates.sh` en el mismo checkout.
- [ ] `sigpipeCount` pasa a `Atomic` (Int) en un `let` global, `import Synchronization` queda solo en el target de tests, y el handler no toma locks ni reserva memoria.
- [ ] Con TSan, la suite completa en el `.build` por defecto queda sin avisos en BrowserListenerTests.swift.
- [ ] El numero de tests no cambia: 1529, o el que tenga main al abrir el PR.
- [ ] Opcion (a): el job lleva `continue-on-error: true` con un comentario que nombra el criterio de promocion y el arreglo de `ClassicRuntime` que lo destraba.
- [ ] Opcion (b): el PR no se mergea antes del arreglo de `ClassicRuntime`, y la corrida TSan del PR sale sin avisos.
- [ ] La descripcion del PR incluye los tiempos y la memoria medidos en la primera corrida del runner.
- [ ] El PR se escala a Karen, porque cambia los gates de CI.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | ThreadSanitizer | LLVM/Clang | actual | 2026-09-30 | high |
| 2 | Diagnosing memory, thread, and crash issues early | Apple Developer Documentation | SDK actual | 2026-09-30 | high |
| 3 | Thread Sanitizer for Swift on Linux | swift.org blog | sin fecha visible | 2026-09-30 | medium |
| 4 | swift-server guides, testing.md | swift-server workgroup | main | 2026-09-30 | medium |
| 5 | ThreadSanitizerFlags | google/sanitizers wiki | 2026-09-30 | 2026-09-30 | high |
| 6 | ThreadSanitizerSuppressions | google/sanitizers wiki | 2026-09-30 | 2026-09-30 | high |
| 7 | BuildParameters.swift, SwiftCommandState.swift | swiftlang/swift-package-manager | swift-6.3.3-RELEASE 5f6969f | 2026-09-30 | high |
| 8 | Issue 9748, sanitize=thread after sanitize=address | swiftlang/swift-package-manager | cerrado 2023-12-11 | 2026-09-30 | medium (historico) |
| 9 | GitHub-hosted runners reference | GitHub Docs | 2026-09-30 | 2026-09-30 | high |
| 10 | Workflow syntax (continue-on-error, timeout-minutes) | GitHub Docs, github/docs | 10844e1 | 2026-09-30 | high |
| 11 | About protected branches | GitHub Docs | 2026-09-30 | 2026-09-30 | high |
| 12 | GitHub Actions billing | GitHub Docs | 2026-09-30 | 2026-09-30 | high |
| 13 | Actions limits | GitHub Docs | 2026-09-30 | 2026-09-30 | high |
| 14 | Corrida 36795743537 del job gates | karenrebecag/Companion | 568dbd5 | 2026-09-30 | high |
| 15 | Known issues, Enabling and disabling tests | Apple, Swift Testing | actual | 2026-09-30 | high |
| 16 | signal | cppreference (C11) | C11 | 2026-09-30 | medium (secundaria sobre ISO C) |
| 17 | SE-0410 Atomics | Swift Evolution | Swift 6.0 | 2026-09-30 | high |
| 18 | Atomic | Apple Developer Documentation | macOS 15.0+ | 2026-09-30 | high |
| 19 | opentelemetry-swift BuildAndTest.yml | OpenTelemetry | 1466d2d | 2026-09-30 | high |
| 20 | vapor/ci run-unit-tests.yml, vapor/vapor test.yml | Vapor | 86063c5, 3fe848c | 2026-09-30 | high |
| 21 | FuzzyMatch swift-sanitizer-thread.yml | ordo-one | ea09aa7 | 2026-09-30 | medium (Linux) |
| 22 | Mediciones locales y del runner | docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt | 2026-09-30 | 2026-09-30 | medium (local con carga alta) |
