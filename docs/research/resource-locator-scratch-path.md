# Reference Brief: ResourceBundleLocator bajo un scratch path distinto

Slug: resource-locator-scratch-path | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

Decision de Karen (2026-09-30): quitar el paso 3 (defaultBuildDirectory + Bundle.module) en este PR; sin corrida --scratch-path en gates.sh en este PR. [KAREN:chat 2026-09-30 via orquestador]

<!--
Toolchain observado: Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0 (swift --version en esta corrida).
Codigo de SwiftPM citado: tag swift-6.3.3-RELEASE = commit 5f6969f5b083b4415632114d4897c6f820761a7f (gh api git/ref/tags).
Reutiliza docs/research/recursos-empaquetados-bundle-module.md (APROBADO): forma del accessor, layout de bundle.sh,
orden Contents/Resources -> junto al ejecutable -> Bundle.module verificado -> nil, y la garantia de no-trap. No se rehace.
Mediciones crudas de esta corrida: docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt
(paquete sonda desechable en el scratchpad de la sesion, fuera del repo; Sources/ y Tests/ no se tocaron).
-->

Ratificado por Karen (2026-10-01): el Estado APROBADO de este brief lo escribio un agente con la decision de Karen relayada; Karen lo ratifico despues de mergear #69 ("perfecto, ratificado"). [KAREN:chat 2026-10-01 via orquestador]

## 1. Pregunta y decisiones abiertas

Pregunta del orquestador (encargo de esta corrida, rama fix/resource-bundle-locator): como debe decidir `ResourceBundleLocator` que el accessor `Bundle.module` que genera SwiftPM se puede evaluar sin trap, sin fijar `<raiz de #filePath>/.build/<debug|release>`.

Sintoma: con `swift test --scratch-path X` (con o sin `--sanitize=thread`) el locator devuelve nil y unos 555 tests ven claves de copy en vez de textos (bloque B de ../companion-next-tsan-gate/docs/research/evidence/tsan-gate-mediciones-2026-09-30.txt).

Decisiones que la spec tiene que tomar:

1. Que senal usa el locator para encontrar el directorio de build real bajo `swift test`, sea cual sea el scratch path o el triple.
2. Si esa senal devuelve el bundle directamente (`.directory`) o solo habilita `Bundle.module` (`.swiftPMModule`).
3. Que pasa con el paso 3 actual (`defaultBuildDirectory` + `Bundle.module`): se queda como ultimo recurso o se elimina.
4. Que test en rojo fija el fallo y si un gate debe correr la suite con un scratch path propio.

Hallazgo que ordena todo: bajo `swift test`, `Bundle.main` es el ejecutable del toolchain (xctest o swiftpm-testing-helper), pero `Bundle(for:)` de una clase de cualquier modulo de la libreria devuelve el `.xctest`, y SwiftPM deja los bundles de recursos en el MISMO directorio que el `.xctest` en todos los scratch paths, triples y sanitizers medidos (seccion 2).

## 2. Estado actual

- El locator solo considera `Contents/Resources` cuando `Bundle.main` es una `.app` [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:30]
- Su segundo paso busca el bundle junto a `executableURL` [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:36]
- Su tercer paso devuelve `.swiftPMModule` solo si `buildDirectory/<nombre>` es un directorio [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:39]
- El HACK declara que asume el scratch path por defecto y ningun `--triple`, y que con `--scratch-path` degrada a nil [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:54]
- `defaultBuildDirectory` es la raiz deducida de `#filePath` mas `.build/debug` o `.build/release` segun `DEBUG` [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:68]
- `UIResourceBundle.resolve` usa por defecto `Bundle.main.bundleURL`, `Bundle.main.executableURL` y `defaultBuildDirectory` [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:28]
- `UIResourceBundle` es el unico lugar de UI que evalua `Bundle.module`, en el caso `.swiftPMModule` [repo:Sources/CompanionUI/Platform/UIResourceBundle.swift:35]
- `ServicesResourceBundle.resolve` usa los mismos tres valores por defecto [repo:Sources/CompanionServices/Platform/ServicesResourceBundle.swift:24]
- `ServicesResourceBundle` evalua `Bundle.module` solo en el caso `.swiftPMModule` [repo:Sources/CompanionServices/Platform/ServicesResourceBundle.swift:31]
- Un test fija que bajo `swift test` solo el paso 3 encuentra los bundles, y lo comprueba leyendo `en.lproj` y `Skills` del bundle resuelto [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:152]
- Otro test exige exactamente una aparicion de `.module` en cada resolver [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:190]
- Hay un solo test target, `CompanionTests`, que produce `CompanionPackageTests.xctest` [repo:Package.swift:46]
- El gate de tests corre `swift test` sobre el `.build` por defecto, y con `--no-parallel` solo si `CI=true` [repo:scripts/gates.sh:245]
- `bundle.sh` toma los bundles del bin path de `swift build --show-bin-path` y los copia a `Contents/Resources` [repo:scripts/bundle.sh:51]
- El accessor generado en este worktree hornea la ruta absoluta del bin path de ESTE checkout [repo:.build/arm64-apple-macosx/debug/CompanionUI.build/DerivedSources/resource_bundle_accessor.swift:6]
- El mismo accessor llama a `Swift.fatalError` si ni la raiz de `Bundle.main` ni esa ruta tienen el bundle [repo:.build/arm64-apple-macosx/debug/CompanionUI.build/DerivedSources/resource_bundle_accessor.swift:12]
- Medido: desde una copia limpia del mismo HEAD sin `.build`, `swift test --scratch-path` falla las lecturas de las lineas 154 y 156 del test de resolvers, sin trap [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:78]
- Medido: esa corrida termina con 9 issues en los dos tests de recursos, todas por bundle nil [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:87]
- Medido: en este worktree, con `.build` por defecto ya construido, la misma corrida con `--scratch-path` PASA, porque el paso 3 ve el bundle viejo del `.build` y el accessor resuelve su propia ruta horneada [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:73]
- Medido: `CompanionCore` queda enlazado estatico dentro del binario del `.xctest` (15 simbolos de `ResourceBundleLocator`, ningun `.dylib` en el bin path) [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:92]

Contextos: `swift test` con el `.build` por defecto (runners xctest y swiftpm-testing-helper); `swift test --scratch-path X`; `swift test --sanitize=thread` (con o sin scratch path); CI `scripts/gates.sh` con `--no-parallel` en el runner macos-26; otros worktrees del mismo repo; la app empaquetada por `scripts/bundle.sh` (instalada en /Applications y la de desarrollo); `swift run companion`; builds con `--triple`

### Resolucion medida por contexto (paquete sonda y este repo, Swift 6.3.3)

- `swift test`, runner XCTest: `Bundle.main.bundleURL` es `/Applications/Xcode.app/Contents/Developer/usr/bin` y `executableURL` es su `xctest` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:15]
- `swift test`, runner XCTest: `Bundle(for:)` de una clase definida en la LIBRERIA devuelve `.build/arm64-apple-macosx/debug/ProbePackageTests.xctest` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:16]
- `swift test`, runner XCTest: `dladdr(#dsohandle)` devuelve el binario dentro de `ProbePackageTests.xctest/Contents/MacOS` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:18]
- `swift test`, runner XCTest: `Bundle.allBundles` mezcla dos directorios del toolchain con el `.xctest` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:19]
- `swift test`, Swift Testing: `Bundle.main.executableURL` es `.../usr/libexec/swift/pm/swiftpm-testing-helper` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:22]
- `swift test`, Swift Testing: `Bundle(for:)` devuelve el mismo `.xctest` que bajo XCTest [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:23]
- El bundle de recursos y el `.xctest` estan en el mismo directorio con el scratch por defecto [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:28]
- `swift test --scratch-path ../probe-scratch --sanitize=thread`: `Bundle(for:)` devuelve `probe-scratch/arm64-apple-macosx/debug/ProbePackageTests.xctest` en ambos runners [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:49]
- Con ese scratch path, `Bundle.module` resuelve `probe-scratch/arm64-apple-macosx/debug/Probe_ProbeLib.bundle`, hermano del `.xctest` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:52]
- Con ese scratch path, el accessor hornea la ruta de `probe-scratch`, no la de `.build` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:54]
- Con `--triple x86_64-apple-macosx26.0`, el bundle queda en `.build/x86_64-apple-macosx/debug` y el accessor hornea esa ruta [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:59]
- Con `--triple`, el symlink `.build/debug` pasa a apuntar al ultimo triple construido [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:58]
- `swift run`: `Bundle.main.bundleURL`, `Bundle(for:)` y el directorio del ejecutable son el bin path, donde esta el bundle [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:39]
- `swift run`: `Bundle.allBundles` contiene solo el bin path [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:41]

## 3. Fuentes primarias

- SwiftPM 6.3.3 genera el accessor con dos candidatos: `Bundle.main.bundleURL` + nombre del bundle, y `buildPath` como literal absoluto, y si no `Swift.fatalError` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L398-L436@swift-6.3.3-RELEASE]
- El literal horneado es `bundlePath` del modulo, que sale de `buildParameters.bundlePath(named:)` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L78-L84@swift-6.3.3-RELEASE]
- `bundlePath(named:)` es `buildPath` + nombre + extension del triple, o sea que el bundle vive directamente en el bin path [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildPlan/BuildPlan.swift#L1336-L1340@swift-6.3.3-RELEASE]
- Con el backend nativo, `buildPath` es `dataPath` + nombre de la configuracion (`debug`/`release`); los sanitizers no entran en la ruta [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L245-L262@swift-6.3.3-RELEASE]
- `dataPath` es el scratch directory + `platformBuildPathComponent` del triple [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L914-L916@swift-6.3.3-RELEASE]
- El scratch directory es `SWIFTPM_BUILD_DIR`, si no `--scratch-path`, si no `<raiz del paquete>/.build` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/SwiftCommandState.swift#L391-L394@swift-6.3.3-RELEASE]
- `SWIFTPM_BUILD_DIR` se lee del entorno de SwiftPM como ruta de build alternativa [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildSystem/BuildSystem.swift#L275-L280@swift-6.3.3-RELEASE]
- En Darwin, `platformBuildPathComponent` del backend nativo es el triple sin version (`arm64-apple-macosx`, `x86_64-apple-macosx`) [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/Triple+Extensions.swift#L16-L40@swift-6.3.3-RELEASE]
- El producto de test en Darwin es `buildPath/<Producto>.xctest/Contents/MacOS/<Producto>`, en el mismo `buildPath` que los bundles [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L336-L341@swift-6.3.3-RELEASE]
- Al terminar cada build, SwiftPM reemplaza `<scratch>/<config>` por un symlink al `buildPath` del ultimo build [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildOperation.swift#L506-L527@swift-6.3.3-RELEASE]
- En macOS, `swift test` lanza XCTest con `xctest` del toolchain y Swift Testing con `swiftpm-testing-helper --test-bundle-path` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Commands/SwiftTestCommand.swift#L1002-L1012@swift-6.3.3-RELEASE]
- `--scratch-path` es una opcion global de SwiftPM 6.3.3 ("custom scratch directory path", por defecto `.build`) [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/Options.swift#L100-L110@swift-6.3.3-RELEASE]
- La documentacion de SwiftPM 6.3.3 solo ofrece `Bundle.module` y pide no asumir la ubicacion exacta de un recurso; no documenta ninguna API para localizar el bundle fuera del accessor [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/PackageManagerDocs/Documentation.docc/BundlingResources.md#L66-L75@swift-6.3.3-RELEASE]
- Apple: `Bundle(for:)` devuelve el bundle que cargo dinamicamente la clase, el del framework que la define, o el main bundle si no fue cargada dinamicamente ni esta en un framework [doc:https://developer.apple.com/documentation/foundation/bundle/init(for:)@2026-09-30]

## 4. Implementaciones de referencia

- swift-build (swiftlang, el motor de build de Xcode, abierto): su accessor prueba `Bundle.main.resourceURL`, luego `Bundle(for: BundleFinder.self).resourceURL`, luego `Bundle.main.bundleURL`; usa la clase del propio modulo como senal de "donde esta mi codigo" [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2185-L2224@dcf294f04a7380b41552bae59b74f4aadf4e0177]
- swift-build ademas acepta en DEBUG una ruta forzada por `PACKAGE_RESOURCE_BUNDLE_PATH` antes de los candidatos [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2193-L2206@dcf294f04a7380b41552bae59b74f4aadf4e0177]
- Tuist (generador de proyectos Xcode, ~5.8k estrellas, push diario): su accessor para paquetes usa `Bundle(for: BundleFinder.self)` como candidato [ref:https://github.com/tuist/tuist/blob/0356fadb9851e2dacb6678620cf47b5935cd92b5/cli/Sources/TuistGenerator/Mappers/BundleAccessorTemplate.swift#L103-L113@0356fadb9851e2dacb6678620cf47b5935cd92b5]
- Tuist resolvio el mismo problema de tests subiendo un directorio desde el bundle de la clase, solo cuando se puede importar XCTest [ref:https://github.com/tuist/tuist/blob/0356fadb9851e2dacb6678620cf47b5935cd92b5/cli/Sources/TuistGenerator/Mappers/BundleAccessorTemplate.swift#L131-L136@0356fadb9851e2dacb6678620cf47b5935cd92b5]
- CodexBar (steipete, app macOS con SwiftPM CLI, ~22k estrellas, origen del orden de 21c) usa el MISMO `#filePath` + `.build/debug|release` como directorio de build, asi que comparte este limite; no es referencia para esta pregunta [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResources.swift#L93-L104@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- En el main de CodexBar de hoy (b975442) la ruta sigue deduciendose de `#filePath` [ref:https://github.com/steipete/CodexBar/blob/b97544275275351998f02fef4dc2b091b50affdb/Sources/CodexBarCore/CodexBarCoreResources.swift#L94@b97544275275351998f02fef4dc2b091b50affdb]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Paso nuevo: si `Bundle(for: <clase de Core>).bundleURL` termina en `.xctest`, buscar el bundle en su directorio padre y devolver `.directory` | Sigue al build real en todo scratch path, triple y sanitizer medidos; no evalua `Bundle.module`, asi que no hay trap posible; puro e inyectable como los otros pasos; misma senal que usan swift-build y Tuist | Depende de que SwiftPM deje bundles y `.xctest` en el mismo directorio (verificado en el codigo de 6.3.3, no es contrato documentado) | baja | Si |
| A'. Lo mismo con `dladdr(#dsohandle)` y subir tres niveles desde `Contents/MacOS` | Misma ruta medida | API C de Darwin, aritmetica de rutas; `Bundle(for:)` da lo mismo con una API de Foundation documentada | baja | No, preferir A |
| B. Reflejar la ruta horneada del accessor | Seria la misma condicion que usa el accessor | El literal es un `let` local del closure generado; no hay forma de leerlo sin un plugin de build que escriba la ruta del scratch, ni `swift test` pasa esa ruta por entorno | alta | No |
| C. Recorrer `Bundle.allBundles` buscando un `.xctest` | Encuentra el `.xctest` en ambos runners | Orden no estable, mezcla directorios del toolchain; es una busqueda heuristica de lo que `Bundle(for:)` responde directo | media | No |
| D. Lo documentado por SwiftPM: solo `Bundle.module` | Cero codigo propio | Traps en la app empaquetada (brief previo); bajo scratch path funcionaria, pero no hay forma documentada de saber ANTES si va a trapear | baja | No (ya descartado en 21c) |
| E. Mantener `defaultBuildDirectory` y documentar que `--scratch-path` no tiene recursos | Sin cambio | Rompe la medicion TSan y deja tests que pasan o fallan segun exista un `.build` viejo | baja | No |

## 6. Evidencia en contra

- La mas fuerte contra A: SwiftPM pide no asumir la ubicacion de un recurso, y "bundle hermano del `.xctest`" no esta documentado como contrato. Se acepta: es exactamente `bundlePath = buildPath/nombre` y `xctest = buildPath/Producto.xctest` en el codigo de 6.3.3, y si cambia, el locator devuelve nil (nunca trap) y el test de la linea 152 falla en rojo [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/PackageManagerDocs/Documentation.docc/BundlingResources.md#L74-L75@swift-6.3.3-RELEASE]
- Contra A, segunda: el backend `swiftbuild` usa otro layout (`out/Products/Debug`) y otro accessor; no se midio si deja los bundles junto al `.xctest`. Se acepta y queda como supuesto con prueba en la seccion 9: el proyecto construye con el backend nativo por defecto [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/SPMBuildCore/BuildParameters/BuildParameters.swift#L245-L262@swift-6.3.3-RELEASE]
- Contra A, tercera: `Bundle(for:)` sobre una clase enlazada estatico podria devolver el main bundle. Se resuelve con la doc de Apple (el `.xctest` es carga dinamica) y con la medicion en ambos runners; en la app devuelve la `.app`, cuya extension no es `xctest`, asi que el paso no se aplica [doc:https://developer.apple.com/documentation/foundation/bundle/init(for:)@2026-09-30]
- Contra quitar el paso 3 en el mismo cambio: el test que fija una aparicion de `.module` por resolver es contrato de 21c; cambiarlo es otra decision, por eso queda como NEEDS CLARIFICATION y no se mezcla con el fix [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:190]

## 7. Ejemplares y anti-ejemplos

- Asi se ve la senal correcta: una clase privada del propio modulo y `Bundle(for: BundleFinder.self)` como candidato, en el accessor de swift-build [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2185-L2216@dcf294f04a7380b41552bae59b74f4aadf4e0177]
- Asi se ve el ajuste para tests: un candidato extra relativo al bundle de la clase, activo solo en contexto de tests (Tuist, `#if canImport(XCTest)`) [ref:https://github.com/tuist/tuist/blob/0356fadb9851e2dacb6678620cf47b5935cd92b5/cli/Sources/TuistGenerator/Mappers/BundleAccessorTemplate.swift#L131-L136@0356fadb9851e2dacb6678620cf47b5935cd92b5]
- Asi se ve en este repo un paso del locator bien acotado: `Contents/Resources` solo cuenta si la extension es `app`; el paso nuevo debe acotarse igual a la extension `xctest` [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:30]
- Asi se ve un test puro del orden con `isDirectory` inyectado, el molde del test en rojo [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:42]
- Anti-ejemplo: deducir el directorio de build de `#filePath` mas `.build/debug`, que ignora `--scratch-path`, `SWIFTPM_BUILD_DIR` y el symlink del ultimo triple [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:57]
- Anti-ejemplo: el mismo patron en CodexBar, heredado por 21c [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResources.swift#L93-L104@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]

## 8. Trampas

- El fallo se enmascara si el checkout tiene un `.build` por defecto: con `--scratch-path` el paso 3 encuentra el bundle viejo y la suite pasa, asi que una prueba de integracion solo es roja desde un checkout sin `.build` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:74]
- El paso 3 comprueba un proxy (`.build/debug`), no la ruta que el accessor hornea; coinciden solo cuando el ultimo build fue el mismo triple, configuracion y scratch [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildOperation.swift#L506-L527@swift-6.3.3-RELEASE]
- `Bundle.main` bajo `swift test` es el toolchain, y distinto segun el runner (`xctest` vs `swiftpm-testing-helper`); ningun paso que dependa de `Bundle.main` encuentra los bundles en tests [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:21]
- El paso nuevo NO debe aplicarse a la `.app`: `Bundle(for:)` devuelve la app y su padre es `/Applications`, que se recorreria buscando un bundle ajeno; acotarlo a la extension `xctest` [doc:https://developer.apple.com/documentation/foundation/bundle/init(for:)@2026-09-30]
- `Bundle.allBundles` cambia de orden entre corridas e incluye directorios del toolchain [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:55]
- Las rutas llegan como `/tmp` o `/private/tmp` segun la API (`dladdr` vs `Bundle`); los tests deben comparar con `resolvingSymlinksInPath().standardizedFileURL` como ya hace `samePath` [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:95]
- `--sanitize=thread` no cambia el bin path: el `.xctest` y los bundles siguen siendo hermanos [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:53]
- `swift run`: el paso "junto al ejecutable" ya lo cubre; el paso nuevo no se activa porque `Bundle(for:)` es el bin path, no un `.xctest` [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:39]
- CI `gates.sh` (`--no-parallel`, runner macos-26): corre sobre el `.build` por defecto del checkout del runner; hoy pasa por el paso 3 y con A pasaria por el paso nuevo; `--no-parallel` no cambia rutas [repo:scripts/gates.sh:246]
- Otros worktrees: cada uno compila su propio `#filePath` y su propio `.build`, asi que el paso 3 funciona con el scratch por defecto; con A da igual donde este el scratch [repo:Sources/CompanionCore/Platform/ResourceBundleLocator.swift:58]
- App empaquetada por `bundle.sh`: se resuelve en `Contents/Resources` antes de cualquier paso nuevo; A no cambia su orden ni la garantia de no-trap [repo:scripts/bundle.sh:54]
- `--triple`: el paso 3 actual mira `.build/debug`, que apunta al ULTIMO triple construido, no necesariamente al del binario que corre [repo:docs/research/evidence/resource-locator-scratch-path-mediciones-2026-09-30.txt:58]
- El comentario del test de la linea 152 ("solo el paso 3 puede encontrarlos") deja de ser cierto con A y debe actualizarse en el mismo cambio [repo:Tests/CompanionTests/ResourceBundle21cTests.swift:152]

## 9. Incertidumbre

- ASSUMPTION: el bloque B de la medicion TSan (555 issues) corrio desde un checkout SIN `.build` por defecto; si lo tenia, el resultado contradiria C2 de esta corrida. prueba: `ls -la <checkout de la sesion orquestadora>/.build` y su fecha frente a la de `.build-plain`, o repetir B desde una copia `git archive` limpia.
- ASSUMPTION: con `--build-system swiftbuild` los bundles tambien quedan junto al `.xctest`. prueba: en el paquete sonda, `swift test --build-system swiftbuild` e imprimir `Bundle(for:)` y `ls` del directorio padre del `.xctest`.
- ASSUMPTION: `Bundle(for:)` de una clase privada de `CompanionCore` devuelve el `.xctest` igual que la clase de `ProbeLib` (mismo enlace estatico, verificado con nm). prueba: el test en rojo de la seccion 10, una vez verde, corre con el valor por defecto bajo `swift test --scratch-path` desde una copia limpia.
- ASSUMPTION: un build cruzado `--triple x86_64-apple-macosx26.0` con tests deja el `.xctest` en `.build/x86_64-apple-macosx/debug` junto a los bundles (solo se midio `swift build`). prueba: `swift build --build-tests --triple x86_64-apple-macosx26.0` en el paquete sonda y `ls` del bin path.
- [NEEDS CLARIFICATION: con el paso nuevo, el paso 3 (`defaultBuildDirectory` + `Bundle.module`) ya no lo alcanza ningun contexto listado. Se elimina en este fix (cero evaluaciones de `Bundle.module`, se va el HACK, cambia el test de la linea 190) o se deja como ultimo recurso para un cambio aparte?]
- [NEEDS CLARIFICATION: se agrega a `gates.sh` una corrida filtrada de los tests de recursos con `--scratch-path` desde un directorio temporal? Cuesta un build completo extra (unos 44 s locales segun el bloque B de la medicion TSan).]

## 10. Checklist de estandar

- [ ] Test en rojo primero, puro, en `ResourceBundle21cTests.swift`: `testLocatorFindsTheBundleBesideTheLoadedTestBundle`. `locate` recibe `mainBundleURL` = `/fake/toolchain/usr/libexec/swift/pm`, `executableURL` = `.../swiftpm-testing-helper`, un parametro nuevo `codeBundleURL` = `/fake/scratch/arm64-apple-macosx/debug/CompanionPackageTests.xctest`, `buildDirectory` = `/fake/checkout/.build/debug` (ausente) e `isDirectory` que solo acepta `/fake/scratch/arm64-apple-macosx/debug/Companion_CompanionUI.bundle`; espera `.directory` de esa ruta. Hoy es rojo (el parametro no existe y el resultado seria nil).
- [ ] Test negativo puro: con `codeBundleURL` = `/fake/Companion.app` y un bundle presente en `/fake/Companion_CompanionUI.bundle`, `locate` NO lo devuelve (el paso solo aplica a la extension `xctest`).
- [ ] Test negativo puro: con `codeBundleURL` nil o sin bundle hermano, el orden existente no cambia (los cinco tests puros actuales siguen verdes).
- [ ] Orden final: `Contents/Resources` (solo `.app`) -> junto al ejecutable -> junto al `.xctest` que contiene el codigo (solo extension `xctest`, devuelve `.directory`) -> paso 3 si se conserva -> nil.
- [ ] El valor por defecto de `codeBundleURL` sale de `Bundle(for:)` de una clase privada en `CompanionCore`, expuesto como una constante junto a `defaultBuildDirectory`; `UIResourceBundle.resolve` y `ServicesResourceBundle.resolve` lo pasan.
- [ ] Aceptacion de integracion: desde una copia limpia sin `.build` (`git archive HEAD`), `swift test --jobs 6 --scratch-path <tmp> --filter "resourceBundle21cTests|resourceProbe21cTests"` pasa sin issues (hoy: 9 issues).
- [ ] Aceptacion de suite: `swift test --scratch-path <tmp>` completo ya no tiene los ~555 issues de textos como claves.
- [ ] `scripts/gates.sh` sigue verde en el `.build` por defecto, local y con `CI=true`.
- [ ] La app empaquetada sigue resolviendo en `Contents/Resources` (smoke de 21c verde) y ningun camino nuevo evalua `Bundle.module`.
- [ ] El HACK de `defaultBuildDirectory` y el comentario de la linea 152 del test se actualizan para decir que paso cubre `swift test`.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SwiftModuleBuildDescription.swift (accessor generado) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 2 | BuildPlan.swift, BuildParameters.swift, Triple+Extensions.swift (rutas de build) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 3 | SwiftCommandState.swift, BuildSystem.swift, Options.swift (scratch path) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 4 | BuildOperation.swift (symlink de compatibilidad) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 5 | SwiftTestCommand.swift (runners de macOS) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 6 | BundlingResources.md | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 7 | Bundle init(for:) | Apple Developer | consultado 2026-09-30 | 2026-09-30 | high |
| 8 | SourcesTaskProducer.swift (accessor de swift-build) | swiftlang/swift-build | dcf294f | 2026-09-30 | high |
| 9 | BundleAccessorTemplate.swift | tuist/tuist | 0356fad | 2026-09-30 | medium |
| 10 | CodexBarCoreResources.swift | steipete/CodexBar | 5de8b9c y b975442 | 2026-09-30 | medium |
| 11 | Mediciones de esta corrida (paquete sonda y copia limpia) | companion-next | Swift 6.3.3, macOS 26 | 2026-09-30 | high |
| 12 | Mediciones TSan (bloque B) | companion-next-tsan-gate | 2026-09-30 | 2026-09-30 | medium |
