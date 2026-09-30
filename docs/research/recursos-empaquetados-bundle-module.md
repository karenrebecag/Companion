# Reference Brief: Recursos empaquetados y Bundle.module

Slug: recursos-empaquetados-bundle-module | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE

<!--
Toolchain observado en esta Mac: Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), macOS 26. El codigo de SwiftPM
citado es el tag swift-6.3.3-RELEASE (commit 5f6969f5b083b4415632114d4897c6f820761a7f).
-->

## 1. Pregunta y decisiones abiertas

Pregunta de Karen para la spec 21c: "Como debe resolver companion-next sus recursos empaquetados (fuentes, skills, diagramas, localizacion) para que funcionen de forma robusta en todos los builds? Hoy se usa Bundle.module; queremos saber si esa es la estrategia correcta o si hay que cambiarla, y que estandar seguir."

Decisiones que la spec tiene que tomar:

1. Con que API se localiza el bundle de recursos de cada modulo (`CompanionUI`, `CompanionServices`) en cada contexto de ejecucion.
2. Donde deja `scripts/bundle.sh` los `.bundle` de SwiftPM dentro de la `.app`, y si esa ubicacion y la API de la decision 1 coinciden.
3. Que pasa cuando el recurso no esta: trap (`fatalError`) o degradacion registrada.
4. Que gate prueba que la app empaquetada arranca en una Mac que NO tiene el checkout.

Hallazgo que ordena todo lo demas: con el toolchain actual, el `Bundle.module` que genera `swift build` no busca en `Contents/Resources`, que es donde `bundle.sh` copia los bundles. La app instalada funciona hoy solo porque el accessor cae a una ruta absoluta dentro de `.build` de esta Mac (seccion 2).

## 2. Estado actual

- El manifiesto declara `defaultLocalization: "en"` [repo:Package.swift:8]
- `CompanionServices` declara `resources: [.copy("Skills"), .copy("Diagram")]` [repo:Package.swift:28]
- `CompanionUI` declara `resources: [.copy("Fonts"), .copy("Mascot")]`; sus carpetas `en.lproj` y `es.lproj` no aparecen en la lista pero SwiftPM las procesa igual como localizadas y quedan en el bundle (verificado con `ls` en `/Applications/Companion.app/Contents/Resources/Companion_CompanionUI.bundle`: `en.lproj`, `es.lproj`, `Fonts`, `Mascot`, `Info.plist`) [repo:Package.swift:36]
- El accessor que genero `swift build -c release` en esta Mac busca primero en `Bundle.main.bundleURL` + nombre del bundle, es decir en la RAIZ de la `.app`, no en `Contents/Resources` [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:5]
- Su segundo candidato es una ruta absoluta al `.build` de este checkout (`/Users/karenrebecaog/Desktop/SoftwareDevProjects/companion-next/.build/arm64-apple-macosx/release/...`) [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:6]
- Si ninguno de los dos existe, el accessor llama a `Swift.fatalError`, que no se puede atrapar con `do/catch` [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:12]
- `bundle.sh` copia cada `*.bundle` del bin path a `Contents/Resources/` de la app [repo:scripts/bundle.sh:54]
- `ls /Applications/Companion.app` muestra solo `Contents`: no hay bundle en la raiz, asi que en la app instalada el primer candidato del accessor falla siempre y se resuelve por la ruta absoluta de `.build` [repo:scripts/bundle.sh:47]
- `release.sh` empaqueta ese mismo layout en el DMG que se distribuye [repo:scripts/release.sh:32]
- Fuentes: `Fonts.register()` toca `Bundle.module.resourceURL` [repo:Sources/CompanionUI/Typography.swift:294]
- Fuentes: ademas lee `Bundle.main.resourceURL/Fonts`, una segunda copia que `bundle.sh` hace a mano [repo:Sources/CompanionUI/Typography.swift:299]
- `bundle.sh` duplica las fuentes en `Contents/Resources/Fonts` fuera del bundle de SwiftPM [repo:scripts/bundle.sh:59]
- `Fonts.register()` corre en el arranque, antes de cualquier request [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:40]
- Localizacion: `Localized` abre `<idioma>.lproj` via `Bundle.module.path(forResource:ofType:)` [repo:Sources/CompanionUI/Localized.swift:76]
- Mascota: `ClaudeLogo` carga `Mascot/claude.svg` con `Bundle.module.url` [repo:Sources/CompanionUI/ApprovalSheet.swift:193]
- Skills: `BundledSkills.load` usa `Bundle.module` por defecto y acepta un bundle inyectado [repo:Sources/CompanionServices/SkillStore.swift:26]
- Skills: el arranque envuelve la carga en `do/catch` y degrada a "sin skills de sistema", pero ese catch no cubre un trap del accessor [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:80]
- Diagramas: `vendoredScript()` busca `Diagram/mermaid.min.js` con `Bundle.module.url` [repo:Sources/CompanionServices/WebKitDiagramRenderer.swift:64]
- El ledger ya afirma que "`bundle.sh` ya copia los `.bundle` de SPM", sin decir que el accessor no los busca ahi [repo:docs/REFERENCE.md:265]
- Los tests leen catalogos via `Bundle.module` con `@testable import CompanionUI` [repo:Tests/CompanionTests/LocalizedTests.swift:53]
- Los gates revisan claves del Info.plist en `bundle.sh`, pero ninguno arranca la app empaquetada [repo:scripts/gates.sh:86]

Contextos: app instalada por `bundle.sh release` en esta Mac (/Applications/Companion.app), app de desarrollo `bundle.sh` debug (Companion Next.app), DMG de `release.sh` abierto en otra Mac, `swift test` (runner de Swift Testing), `swift run companion` desde el checkout, CI (no hay pipeline en el repo; los gates corren local con `scripts/gates.sh`)

### Resolucion observada o derivada del accessor en cada contexto

- App instalada en esta Mac: candidato 1 (raiz de la .app) no existe, candidato 2 (`.build/.../release/*.bundle`) si existe: funciona, pero lee los recursos del `.build`, no los de la app que se firmo [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:6]
- DMG en otra Mac: ni la raiz ni la ruta absoluta existen, el accessor hace `fatalError` en `Fonts.register()` al arrancar (derivado del codigo, no ejecutado; la prueba esta en la seccion 9) [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:40]
- Esta misma Mac tras `swift package clean`, borrar `.build` o mover el repo: mismo trap que el DMG [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:12]
- `swift test`: `Bundle.main` es el runner de tests, no la app; el candidato 1 falla y resuelve el `.build/debug` [repo:Tests/CompanionTests/LocalizedTests.swift:53]
- `swift run`: `Bundle.main.bundleURL` es el directorio del ejecutable dentro de `.build/debug`, donde SwiftPM deja los bundles, asi que el candidato 1 funciona [repo:scripts/bundle.sh:51]

## 3. Fuentes primarias

- SE-0271: en macOS cada bundle de recursos queda "at a place of the build system's choosing (typically nested inside the ultimate client's main bundle)", y el nombre del bundle es "implementation-defined" y el codigo no deberia depender de el [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0271-package-manager-resources.md@42ee8fb0d529487e1da8730b6a4b1a65eaa5d121]
- SE-0278: `defaultLocalization` define el fallback, los localizados viven en carpetas `<tag>.lproj`, y SwiftPM genera un `Info.plist` del bundle con `CFBundleDevelopmentRegion` [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0278-package-manager-localized-resources.md@42ee8fb0d529487e1da8730b6a4b1a65eaa5d121]
- SwiftPM 6.3.3, backend nativo: el accessor generado usa `Bundle.main.bundleURL.appendingPathComponent(<bundle>)` y como respaldo la ruta absoluta de build, y si no, `Swift.fatalError("could not load resource bundle ...")` [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L398-L436@swift-6.3.3-RELEASE]
- SwiftPM 6.3.3: el `--build-system` por defecto es `native`; existen `swiftbuild` y `xcode` como alternativas [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/CoreCommands/Options.swift#L546-L557@swift-6.3.3-RELEASE]
- swift-build (el motor de Xcode, abierto): su accessor prueba en orden `Bundle.main.resourceURL` ("when the package is linked into an App"), `Bundle(for: BundleFinder.self).resourceURL` (framework) y `Bundle.main.bundleURL` (herramientas de linea de comandos) [doc:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2168-L2226@dcf294f04a7380b41552bae59b74f4aadf4e0177]
- Apple, "Placing content in a bundle": en macOS los recursos van en `Contents/Resources/`; si no se construye con Xcode hay que colocarlos segun la tabla; contenido mal ubicado "might work during day-to-day development, but might cause problems during notarization" [doc:https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle@2026-09-30]
- Apple, misma pagina: un bundle sin codigo embebido en una ubicacion que no es de codigo (como `Contents/Resources`) se firma como recurso [doc:https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle@2026-09-30]
- Apple, "Bundling resources with a Swift package": "Always use `Bundle.module` when you access resources. A package shouldn't make assumptions about the exact location of a resource." [doc:https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package@2026-09-30]
- Apple, misma pagina: `.copy` conserva la estructura de un directorio; `.process` aplica el procesamiento de plataforma; las carpetas `.lproj` se tratan como recurso sin declararlas [doc:https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package@2026-09-30]

## 4. Implementaciones de referencia

- CodexBar (steipete, app de barra de menu para macOS construida con SwiftPM CLI y un script de empaquetado propio, ~22k estrellas, commits diarios; mismo modelo de build que companion-next). Tiene un resolver propio que prueba `Contents/Resources` primero, luego junto al ejecutable, y solo toca `Bundle.module` si el bundle de `.build` existe; devuelve `nil` en vez de hacer trap [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResources.swift#L6-L69@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar, incidente que motivo ese resolver: la version 0.48.0 "crashed at launch on every user machine" porque el accessor de SwiftPM solo prueba la raiz de la app y la ruta de build; en local pasaba porque la maquina de build tenia el checkout en esa ruta [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Scripts/verify_packaged_app_launch.sh#L2-L12@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar, gate: copia la app a un directorio temporal y la arranca con `sandbox-exec` negando toda lectura bajo el checkout, y falla el empaquetado si aparece "could not load resource bundle" [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Scripts/verify_packaged_app_launch.sh#L105-L112@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar, probe deterministico: con `CODEXBAR_RESOURCE_SMOKE=1` la app fuerza todas las cargas de recursos antes de montar UI y sale, porque las cargas perezosas pueden no ejecutarse durante la ventana del smoke [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResourceSmoke.swift#L3-L40@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- CodexBar empaqueta los bundles de SwiftPM igual que companion-next, en `Contents/Resources/` [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Scripts/package_app.sh#L598-L604@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- swift-build (Apple/swiftlang, motor de build de Xcode): su propio accessor ya resuelve `Contents/Resources` primero; es la referencia de que el comportamiento correcto para una app es buscar en `resourceURL`, y de que el problema es del backend nativo de SwiftPM, no de `Bundle.module` como concepto [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2207-L2224@dcf294f04a7380b41552bae59b74f4aadf4e0177]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Seguir con `Bundle.module` tal cual | Cero cambios | La app distribuida hace trap al arrancar en cualquier Mac sin el checkout; en esta Mac lee recursos del `.build`, no de la app firmada | baja | No |
| B. Mover los `.bundle` a la raiz de la `.app` para que el accessor los encuentre | Mantiene `Bundle.module` intacto | Viola la estructura de bundle de macOS (recursos en `Contents/Resources/`); Apple advierte problemas de firma y notarizacion por contenido mal ubicado | baja | No |
| C. Resolver propio por modulo (`Contents/Resources` -> junto al ejecutable -> `Bundle.module` solo si el bundle de build existe -> `nil`), recursos como opcionales, y un smoke de arranque con el checkout inaccesible | Correcto en los cinco contextos; sin trap; mismo layout que ya produce `bundle.sh`; patron probado en produccion por CodexBar tras su incidente | Duplica logica que la herramienta deberia dar; el nombre `Companion_<Target>.bundle` es "implementation-defined" segun SE-0271 | media | Si |
| D. Construir con `swift build --build-system swiftbuild` (o Xcode) para heredar el accessor que prueba `resourceURL` | Sin codigo propio de resolucion; alineado con el accessor de Apple | Cambia el backend de build de todo el proyecto y de los gates; no verificado que `swiftbuild` produzca los mismos nombres y rutas de bundle en 6.3.3; el accessor de swift-build tambien hace `fatalError` | media | Evaluar despues de C |
| E. Incrustar los recursos en el binario (literales o datos generados) | No hay bundle que perder | Rompe `.lproj` y la seleccion de idioma por Foundation, registrar fuentes y abrir skills como archivos | alta | No |

## 6. Evidencia en contra

- Contra C, la mas fuerte: Apple dice "Always use `Bundle.module` ... A package shouldn't make assumptions about the exact location of a resource." Resolucion: esa regla es para un paquete cuyo cliente lo empaqueta Xcode, que coloca el bundle y genera un accessor que lo encuentra. Aqui companion-next es a la vez el paquete y el empaquetador (`bundle.sh`), asi que la ubicacion es una decision propia y debe coincidir con quien busca; C conserva `Bundle.module` como candidato para `swift test` y `swift run`, donde si funciona [doc:https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package@2026-09-30]
- Contra C, segunda: el nombre `Companion_CompanionUI.bundle` no es contrato segun SE-0271, y un toolchain futuro podria cambiarlo. Se acepta, con mitigacion: un gate que falle si el bundle esperado no existe en el bin path o en la app empaquetada, en vez de descubrirlo en runtime [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0271-package-manager-resources.md@42ee8fb0d529487e1da8730b6a4b1a65eaa5d121]
- Contra C, tercera: el propio backend podria arreglarse (el accessor de swift-build ya prueba `resourceURL`), y un resolver propio quedaria de sobra. Se acepta: si D se valida, el resolver se reduce a `Bundle.module`, y el smoke de arranque se queda porque protege igual [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2207-L2224@dcf294f04a7380b41552bae59b74f4aadf4e0177]

## 7. Ejemplares y anti-ejemplos

- Asi se ve bien hecho, orden de busqueda para una app: `if mainBundle.bundleURL.pathExtension == "app" { if let url = mainBundle.url(forResource: name, withExtension: "bundle") ... }`, despues el directorio del ejecutable, y `return .module` solo si el bundle de `.build` existe [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResources.swift#L30-L67@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- Asi se ve bien hecho, el orden canonico de Apple para un paquete dentro de una app: `Bundle.main.resourceURL`, luego `Bundle(for: BundleFinder.self).resourceURL`, luego `Bundle.main.bundleURL` [ref:https://github.com/swiftlang/swift-build/blob/dcf294f04a7380b41552bae59b74f4aadf4e0177/Sources/SWBTaskConstruction/TaskProducers/BuildPhaseTaskProducers/SourcesTaskProducer.swift#L2207-L2216@dcf294f04a7380b41552bae59b74f4aadf4e0177]
- Asi se ve bien hecho en este repo: `BundledSkills.load(from:)` acepta el bundle inyectado, lo que permite testear la resolucion sin el accessor [repo:Sources/CompanionServices/SkillStore.swift:25]
- Anti-ejemplo en este repo: `Fonts.register()` accede a `Bundle.module` en el arranque; con el accessor actual un bundle ausente mata el proceso antes de pintar nada, y ningun manejo de errores lo puede evitar [repo:Sources/CompanionUI/Typography.swift:294]
- Anti-ejemplo en este repo: el `do/catch` alrededor de `BundledSkills.load()` da una sensacion de degradacion que el trap del accessor anula [repo:Sources/CompanionApp/CompanionMainEnvironment.swift:80]

## 8. Trampas

- Probar en la Mac de build no prueba nada: el accessor cae a la ruta absoluta de `.build`, asi que la app "funciona" aunque su layout este mal. CodexBar lo sufrio en 0.48.0 [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Scripts/verify_packaged_app_launch.sh#L2-L12@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- La app instalada lee recursos del `.build`, no de su propio `Contents/Resources`: un cambio en `Sources/.../Skills` recompilado sin re-empaquetar se vera en la app instalada, y lo empaquetado puede diferir de lo que se probo [repo:.build/arm64-apple-macosx/release/CompanionServices.build/DerivedSources/resource_bundle_accessor.swift:6]
- `fatalError` del accessor no pasa por `do/catch`: cualquier "degradacion" que dependa de atrapar el error es ilusoria mientras `Bundle.module` sea el primer acceso [doc:https://github.com/swiftlang/swift-package-manager/blob/5f6969f5b083b4415632114d4897c6f820761a7f/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L398-L436@swift-6.3.3-RELEASE]
- Un smoke de "arranca y sigue vivo" puede pasar aunque un recurso perezoso (diagrama, mascota) este roto, porque ese codigo no corre en la ventana del smoke; hace falta forzar las cargas [ref:https://github.com/steipete/CodexBar/blob/5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f/Sources/CodexBarCore/CodexBarCoreResourceSmoke.swift#L6-L14@5de8b9ccfdcf3ed13d7c67e3639a2dd18d11230f]
- Poner los bundles en la raiz de la `.app` para contentar al accessor rompe la estructura que Apple exige y puede fallar recien en la notarizacion [doc:https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle@2026-09-30]
- Bajo `swift test`, `Bundle.main` es el runner: cualquier resolver que asuma una `.app` debe tener un camino para ese contexto, o los tests de catalogo dejan de encontrar los `.lproj` [repo:Tests/CompanionTests/LocalizedTests.swift:53]
- Las fuentes estan en dos lugares (bundle de SwiftPM y la copia manual de `bundle.sh`); si C resuelve bien el bundle, la copia manual queda redundante y `Fonts.register()` registra cada archivo dos veces [repo:scripts/bundle.sh:57]
- Localizacion: `defaultLocalization` solo cubre el fallback de Foundation; el fallback a ingles de `Localized.fallback` depende de que el bundle resuelva, asi que un bundle `nil` debe dejar la clave cruda, no un trap [repo:Sources/CompanionUI/Localized.swift:76]

## 9. Incertidumbre

- ASSUMPTION: el DMG de `release.sh` hace trap al arrancar en una Mac sin el checkout (derivado del accessor generado y del layout de la app, no ejecutado). prueba: copiar `/Applications/Companion.app` a un directorio temporal y lanzar `Contents/MacOS/Companion` con `sandbox-exec -p '(version 1)(allow default)(deny file-read* (subpath "/Users/karenrebecaog/Desktop/SoftwareDevProjects/companion-next"))'`; esperar "could not load resource bundle" en stderr.
- ASSUMPTION: `swift build --build-system swiftbuild` en Swift 6.3.3 genera el accessor de swift-build (que prueba `Bundle.main.resourceURL`) y deja los bundles con los mismos nombres `Companion_<Target>.bundle`. prueba: construir con esa bandera en un clon temporal e inspeccionar `DerivedSources/resource_bundle_accessor.swift` y el bin path.
- ASSUMPTION: no hay otros accesos a `Bundle.module` fuera de los cinco listados en la seccion 2 que corran antes de `Fonts.register()`. prueba: `grep -rn "Bundle.module" Sources` (hecho en esta corrida: solo Typography, Localized, ApprovalSheet, SkillStore y WebKitDiagramRenderer) y un breakpoint simbolico en el getter en un arranque.
- [NEEDS CLARIFICATION: la spec 21c debe cubrir tambien la carpeta `BrowserExtension`, que no es recurso de SwiftPM sino una copia de `bundle.sh` leida con `Bundle.main.resourceURL`, o solo los recursos de SwiftPM?]
- [NEEDS CLARIFICATION: se acepta que el smoke de arranque use `sandbox-exec`, que Apple marca como obsoleto pero sigue disponible, o se prefiere copiar la app a otra cuenta de usuario / VM?]

## 10. Checklist de estandar

- [ ] Ningun codigo de produccion accede a `Bundle.module` como primer candidato; cada modulo con recursos expone un resolver que prueba en orden `Bundle.main` `Contents/Resources`, junto al ejecutable, y `Bundle.module` solo si el bundle de build existe.
- [ ] El resolver devuelve opcional; un bundle ausente se registra en el log y la funcion afectada degrada (sin fuentes propias, sin skills de sistema, sin diagramas, claves crudas), nunca hace trap.
- [ ] Tests del resolver con bundles falsos para: app con bundle en `Contents/Resources`, ejecutable con bundle adyacente, y nada presente (devuelve `nil`).
- [ ] Un modo de probe (variable de entorno) fuerza la carga de fuentes, `.lproj` en y es, `Mascot/claude.svg`, `Skills/*/SKILL.md` y `Diagram/mermaid.min.js`, e imprime un marcador de exito o la lista de fallos.
- [ ] `bundle.sh` (o `release.sh`) ejecuta ese probe sobre la app empaquetada con el checkout inaccesible y falla el empaquetado si aparece "could not load resource bundle" o el marcador no llega.
- [ ] Los bundles quedan solo en `Contents/Resources/`; nada en la raiz de la `.app`; `codesign --verify --strict` pasa.
- [ ] Las fuentes existen en un solo lugar dentro de la app.
- [ ] `docs/REFERENCE.md` registra la cicatriz: el accessor de `swift build` nativo no busca en `Contents/Resources`.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | SE-0271 Package Manager Resources | swiftlang/swift-evolution | 42ee8fb | 2026-09-30 | high |
| 2 | SE-0278 Package Manager Localized Resources | swiftlang/swift-evolution | 42ee8fb | 2026-09-30 | high |
| 3 | SwiftModuleBuildDescription.swift (accessor generado) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 4 | CoreCommands/Options.swift (build-system) | swiftlang/swift-package-manager | swift-6.3.3-RELEASE (5f6969f) | 2026-09-30 | high |
| 5 | SourcesTaskProducer.swift (accessor de swift-build) | swiftlang/swift-build | main dcf294f | 2026-09-30 | high |
| 6 | Placing content in a bundle | Apple Developer | consultado 2026-09-30 | 2026-09-30 | high |
| 7 | Bundling resources with a Swift package | Apple Developer | consultado 2026-09-30 | 2026-09-30 | high |
| 8 | CodexBar: CodexBarCoreResources, smoke y verify_packaged_app_launch | steipete/CodexBar | 5de8b9c | 2026-09-30 | medium |
| 9 | Accessor generado en este checkout (.build release) | companion-next | Swift 6.3.3 | 2026-09-30 | high |
