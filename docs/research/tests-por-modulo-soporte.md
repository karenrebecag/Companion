# Reference Brief: un target de test por modulo y soporte de test compartido en SwiftPM

Slug: tests-por-modulo-soporte | Nivel: standard | Fecha: 2026-09-30 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-09-30 ESCALATE
Decision de Karen (2026-09-30): opcion A, C solo como puente; internos a `package`; se aprueban Package.swift, gate de release y gate de `@testable`; ADR de capas; renombres en PR aparte; solo Command Line Tools (Xcode es nota, no requisito).

## 1. Pregunta y decisiones abiertas

Como partir `Tests/CompanionTests` en un target de test por modulo de produccion (Core, Services, UI) mas uno de integracion, y donde vive el soporte compartido (arnes, `Conformance`, fakes), sin romper `swift build -c release`, `swift test` local en paralelo, CI con `--no-parallel` ni la indexacion de Xcode/SourceKit.
Decisiones abiertas:
- D1. Forma del soporte: A (por capas, targets regulares sin `@testable`), B (un solo `CompanionTestSupport`) o C (soporte como `.testTarget` sin tests del que dependen otros test targets).
- D2. Que hacer con los 4 archivos de soporte que hoy usan `@testable` (`VoiceSessionFakes`, `BrowserToolSupport`, `DiagramTestKit`, `Approvals16q1Rig`) y con `TestKit.swift`, que tambien lo usa.
- D3. Como se clasifica un test cuando su dependencia real llega por un fake y no por su propio `import`.
- D4. Que gate impide que un target de soporte regular vuelva a meter `@testable`, dado que el CI solo compila en debug.
Los renombres por wave quedan fuera de este brief (la spec ya los separa en otro PR).

## 2. Estado actual

- El paquete declara `swift-tools-version: 6.2` [repo:Package.swift:1]
- Un solo test target, `CompanionTests`, depende de Core, Services y UI a la vez [repo:Package.swift:46]
- Sus dependencias son las tres capas de produccion [repo:Package.swift:48]
- El unico producto es el ejecutable `companion`; no hay productos de biblioteca [repo:Package.swift:11]
- UI compila con aislamiento por defecto `MainActor`; el test target no declara `swiftSettings` [repo:Package.swift:36]
- Services depende solo de Core [repo:Package.swift:26]
- UI depende solo de Core, asi que un test que necesite Services y UI solo cabe en un target de integracion [repo:Package.swift:34]
- En main 08cd9cb hay 393 archivos Swift en `Tests/CompanionTests` y 241 con `@testable import`; la spec midio 391 y 239 sobre 7b56b17 [repo:docs/specs/tests-por-modulo.md:3]
- `TestKit.swift` NO es libre de dependencias: importa Core y hace `@testable import CompanionUI` [repo:Tests/CompanionTests/TestKit.swift:5]
- `TestKit.swift` ademas hace `@testable import CompanionServices` a mitad de archivo para `MockClock` [repo:Tests/CompanionTests/TestKit.swift:124]
- `MockClock` conforma `Clock`, que ya es API `package` de Services, asi que no necesita `@testable` [repo:Sources/CompanionServices/Approvals/Approvals.swift:4]
- `pinLanguage` en TestKit llama a `Localized.scoped`, que ya es `package` en UI [repo:Tests/CompanionTests/TestKit.swift:164]
- `Localized.scoped` esta declarado `package static func` [repo:Sources/CompanionUI/Localization/Localized.swift:47]
- Los helpers del arnes (`expect`, `expectEq`, `LockedBox`, `AsyncBox`, `pumpUntil`) son `internal` por omision: movidos a otro modulo no se ven sin `package` o `public` [repo:Tests/CompanionTests/TestKit.swift:9]
- `Conformance.repoRoot()` sube tres directorios desde `#filePath` y comprueba `conformance/ui-contract.json` [repo:Tests/CompanionTests/ConformanceTests.swift:155]
- `hudGatesTests` busca los tests citados solo dentro de `Tests/CompanionTests` [repo:Tests/CompanionTests/ConformanceTests.swift:104]
- El mismo archivo mezcla el `enum Conformance` (soporte) con funciones `@Test` [repo:Tests/CompanionTests/ConformanceTests.swift:25]
- `ChatFakes` importa Core y Services sin `@testable` [repo:Tests/CompanionTests/ChatFakes.swift:2]
- `VoiceSessionFakes` hace `@testable import CompanionUI` [repo:Tests/CompanionTests/VoiceSessionFakes.swift:3]
- `VoiceSession`, el tipo central del arnes de voz, vive en Services y es `package` [repo:Sources/CompanionServices/Voice/Session/VoiceSession.swift:4]
- 15 archivos llaman a `makeVoiceHarness` sin importar UI: su dependencia de UI llega por el fake, no por su `import` [repo:Tests/CompanionTests/VoiceSessionFakes.swift:31]
- `BrowserToolSupport` hace `@testable import CompanionServices` [repo:Tests/CompanionTests/BrowserToolSupport.swift:2]
- `DiagramTestKit` hace `@testable import CompanionServices` e importa WebKit [repo:Tests/CompanionTests/DiagramTestKit.swift:3]
- `Approvals16q1Rig` hace `@testable import` de Services y de UI [repo:Tests/CompanionTests/Approvals16q1Rig.swift:3]
- `SSEFixtures` solo importa Foundation [repo:Tests/CompanionTests/SSEFixtures.swift:1]
- `Island16m4Tests` usa `Bundle.module` aunque el test target no declara recursos; lo unico en alcance es el accesor interno de UI via `@testable` [repo:Tests/CompanionTests/Island16m4Tests.swift:278]
- `gates.sh` compila solo en debug (`swift build` sin `-c`) [repo:scripts/gates.sh:17]
- `gates.sh` pasa `--no-parallel` solo cuando `CI=true` [repo:scripts/gates.sh:245]
- `gates.sh` corre `swift test` sin filtro de target [repo:scripts/gates.sh:246]
- El gate de arquitectura solo escanea `Sources`, no `Tests` [repo:scripts/gates.sh:7]
- El CI corre `scripts/gates.sh` en `macos-26` y nada mas [repo:.github/workflows/ci.yml:21]
- El unico build de release es `bundle.sh`, que corre `swift build -c "$CONFIG"` sin `--product` [repo:scripts/bundle.sh:10]
- Rutas que nombran `Tests/CompanionTests` fuera de Swift: el libro de puertas del HUD [repo:conformance/hud-gates.json:2]
- Tambien el contrato de UI [repo:conformance/ui-contract.json:2]
- Y un fixture compartido con la extension del navegador [repo:Extensions/browser/test/page.test.js:196]
- `docs/ARCHITECTURE.md` todavia describe `CompanionTests` como un target ejecutable con arnes propio (texto desactualizado) [repo:docs/ARCHITECTURE.md:104]
Contextos: `swift test` local en paralelo; CI `scripts/gates.sh` con `--no-parallel` en macos-26; `swift build` debug de gates.sh; `swift build -c release` de bundle.sh/release.sh (compila todo target no-test); Xcode y SourceKit-LSP indexando el paquete.

## 3. Fuentes primarias

- `@testable` solo da acceso a lo `internal` si el modulo importado se compilo con testing habilitado [doc:https://github.com/swiftlang/swift-book/blob/1c0598430507e6c2b9a0f068b6dd7c618392fea6/TSPL.docc/LanguageGuide/AccessControl.md#L159@6.2]
- El acceso `package` hace visible una entidad en cualquier modulo del mismo paquete y en ninguno fuera [doc:https://github.com/swiftlang/swift-book/blob/1c0598430507e6c2b9a0f068b6dd7c618392fea6/TSPL.docc/LanguageGuide/AccessControl.md#L72@6.2]
- SE-0386 (`package`, implementado en Swift 5.9) llama a `@testable` como sustituto de acceso de paquete una "subversion" que debilita las fronteras de modulo [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0386-package-access-modifier.md#L314@5.9]
- SE-0409 (niveles de acceso en `import`, p. ej. `package import`) esta implementado en Swift 6.0 [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0409-access-level-on-imports.md#L6@6.0]
- El compilador rechaza `@testable` contra un modulo sin `-enable-testing` con el error fatal "module %0 was not compiled for testing" [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/include/swift/AST/DiagnosticsSema.def#L1205@6.2]
- En SwiftPM 6.2 la testability por defecto es `configuration == .debug` salvo que se fuerce explicitamente [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/SPMBuildCore/BuildParameters/BuildParameters+Testing.swift#L117@6.2]
- Los test targets SIEMPRE se compilan con `-enable-testing`; un target regular solo si la testability del build esta activa [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L1020@6.2]
- Los test targets ademas reciben `-enable-cross-import-overlays` para Swift Testing; un target regular no [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L1029@6.2]
- `swift build` sin opciones construye el subconjunto `allExcludingTests`: todos los productos y todos los targets no-test [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/SPMBuildCore/BuildSystem/BuildSystem.swift#L22@6.2]
- `swift build` expone `--build-tests`, `--target` y `--product`, pero no `--enable-testable-imports` [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageManagerDocs/Documentation.docc/SwiftBuild.md#L249@6.2]
- `swift test` si expone `--enable-testable-imports|disable-testable-imports`, habilitado por defecto [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageManagerDocs/Documentation.docc/SwiftTest.md#L307@6.2]
- En 6.2 un target no-test que dependa de un test target es error de manifiesto; solo test targets pueden depender de test targets [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L923@6.2]
- El mensaje exacto es "Only test targets can depend on other test targets" [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/ManifestLoader+Validation.swift#L316@6.2]
- Esa regla entro con el PR 8513 (abril 2025), que dice que test-a-test ya estaba permitido y solo bloquea no-test-a-test [doc:https://github.com/swiftlang/swift-package-manager/pull/8513@2025-04-25]
- Por defecto SwiftPM crea UN solo producto de test (`<Paquete>PackageTests`) con todos los test targets [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L1540@6.2]
- En macOS la toolchain agrega la ruta de Swift Testing (`-F` o `-I/-L`) a los flags globales del compilador, no solo a los test targets [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageModel/UserToolchain.swift#L756@6.2]
- El pitch abierto "Restrict testability to direct in-package source module dependencies of test targets" (agosto 2024) describe que hoy en debug todo modulo es testable y que eso permite codigo que rompe en release [doc:https://forums.swift.org/t/pitch-restrict-testability-to-direct-in-package-source-module-dependencies-of-test-targets/73921@2024-08-12]
- En SR-8497 (2018) un mantenedor de SwiftPM confirmo que un test target ya podia depender de otro y que `swift test` funcionaba; lo que fallaba era el proyecto Xcode generado [doc:https://github.com/swiftlang/swift-package-manager/issues/5344@2018-08-10]

## 4. Implementaciones de referencia

- swift-nio (Apple, repo de red base del ecosistema, activo hoy): `NIOTestUtils` es un `.target` regular con dependencias de producto [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Package.swift#L243@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- swift-nio publica `NIOTestUtils` como producto porque es API para usuarios, no solo soporte interno [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Package.swift#L57@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- Ninguno de los 4 archivos de `NIOTestUtils` usa `@testable`; lo que es solo para el paquete va con `package` [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOTestUtils/ManualTaskExecutor.swift#L107@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- swift-package-manager (swiftlang, release/6.2): `_InternalTestSupport` es un `.target` regular, fuera de `products`, del que dependen casi todos los test targets [ref:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Package.swift#L824@215e9f91823d7e44c379fa17bf1eef189438fc24]
- SwiftPM tambien lo parte por capas: `_InternalBuildTestSupport` depende de `_InternalTestSupport` y agrega los sistemas de build [ref:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Package.swift#L810@215e9f91823d7e44c379fa17bf1eef189438fc24]
- sourcekit-lsp (swiftlang, release/6.2): `SKTestSupport` es un `.target` regular con recursos, fuera de `products` [ref:https://github.com/swiftlang/sourcekit-lsp/blob/fcdf78d91fd77108a879c3e61bbd8f47b75f5347/Package.swift#L428@fcdf78d91fd77108a879c3e61bbd8f47b75f5347]
- `SKTestSupport` expone sus helpers con `package func` y `package import`, sin `@testable` [ref:https://github.com/swiftlang/sourcekit-lsp/blob/fcdf78d91fd77108a879c3e61bbd8f47b75f5347/Sources/SKTestSupport/Assertions.swift#L16@fcdf78d91fd77108a879c3e61bbd8f47b75f5347]
- isowords (Point-Free, app de produccion modularizada; ultimo push 2024-08, tools 5.9, se cita como patron de capas, no por actividad): `TestHelpers` es un target sin dependencias [ref:https://github.com/pointfreeco/isowords/blob/c727d3a7c49cf0c98f2fa4f24c562f81e30165f7/Package.swift#L170@c727d3a7c49cf0c98f2fa4f24c562f81e30165f7]
- isowords apila encima `IntegrationTestHelpers`, que si depende de modulos de producto [ref:https://github.com/pointfreeco/isowords/blob/c727d3a7c49cf0c98f2fa4f24c562f81e30165f7/Package.swift#L709@c727d3a7c49cf0c98f2fa4f24c562f81e30165f7]
- Los helpers de isowords son `public` y regulares, sin `@testable` [ref:https://github.com/pointfreeco/isowords/blob/c727d3a7c49cf0c98f2fa4f24c562f81e30165f7/Sources/TestHelpers/Unwrap.swift#L3@c727d3a7c49cf0c98f2fa4f24c562f81e30165f7]
- swift-composable-architecture (Point-Free, activo): no tiene target de soporte propio; su test target consume `IssueReportingTestSupport` como producto de otro paquete [ref:https://github.com/pointfreeco/swift-composable-architecture/blob/377da4061db10d26337a71bb279c506bb951f50f/Package.swift#L78@377da4061db10d26337a71bb279c506bb951f50f]
- swift-numerics (Apple): `_TestSupport` es un `.target` regular del que dependen los tres test targets [ref:https://github.com/apple/swift-numerics/blob/a7d826ead09420d5e38221ff76c3e0ec9ea4ea8b/Package.swift#L61@a7d826ead09420d5e38221ff76c3e0ec9ea4ea8b]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Por capas, targets regulares sin `@testable`: `CompanionTestKit` (solo Testing/Foundation) y soporte por capa (`CompanionCoreTestSupport`, `CompanionServicesTestSupport`, `CompanionUITestSupport`) con API `package` | Las capas se cumplen tambien en tests; compila en release; es el patron de SwiftPM, sourcekit-lsp, swift-nio e isowords | Hay que reescribir los 4 `@testable` y los dos de TestKit a API `package`; mas targets en el manifiesto; hay que partir `ChatFakes` y `VoiceSessionFakes` | media | Recomendada, alineada con la spec |
| B. Un solo `CompanionTestSupport` regular que depende de Core, Services y UI | Un solo lugar; cambio casi mecanico | Todo test de Core enlaza Services y UI y el objetivo de capas se pierde; los `@testable` siguen rompiendo `swift build -c release` | baja | No |
| C. Soporte como `.testTarget` sin tests (p. ej. `CompanionTestKit` test target) del que dependen los demas test targets | `@testable` sigue compilando (test targets siempre llevan `-enable-testing`); `swift build -c release` no lo construye | Permitido por el validador pero sin documentacion de uso; comportamiento en Xcode y en el backend swift-build sin verificar; esconde deuda `@testable` en vez de pagarla | baja | Solo como puente para los fakes que de verdad necesitan internos, y solo si la prueba de la seccion 9 pasa |

## 6. Evidencia en contra

- Contra A: obliga a subir a `package` simbolos que hoy solo los tests ven, ampliando la superficie de API por razones de test; se acepta porque `package` no sale del paquete y el proyecto ya lo usa en `Localized.scoped` [repo:Sources/CompanionUI/Localization/Localized.swift:47]
- Contra A: SE-0386 disena `package` justamente para modulos de un mismo paquete, y describe `@testable` como el atajo peor, no el mejor [doc:https://github.com/swiftlang/swift-evolution/blob/42ee8fb0d529487e1da8730b6a4b1a65eaa5d121/proposals/0386-package-access-modifier.md#L314@5.9]
- Contra A: son mas targets y mas manifiesto; SwiftPM mismo mantiene dos capas de soporte con ese costo [ref:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Package.swift#L810@215e9f91823d7e44c379fa17bf1eef189438fc24]
- Contra A: partir `VoiceSessionFakes` puede no ser posible si de verdad necesita UI; entonces sus 15 consumidores sin `import CompanionUI` van a integracion y el conteo de la spec cambia [repo:Tests/CompanionTests/VoiceSessionFakes.swift:3]
- Contra la division en si: no aisla en ejecucion; los test targets siguen en un solo producto y proceso, asi que el paralelo y el estado global compartido no cambian [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L1540@6.2]
- Contra C como solucion general: el unico respaldo de uso es un hilo de 2018 y un comentario de codigo; nadie de las referencias lo usa asi [doc:https://github.com/swiftlang/swift-package-manager/issues/5344@2018-08-10]

## 7. Ejemplares y anti-ejemplos

- Bien: soporte regular con API `package`, sin `@testable`, como `package final class ManualTaskExecutor` [ref:https://github.com/apple/swift-nio/blob/d09ffc8ad6437bc278897279e33150d8e39ee3d5/Sources/NIOTestUtils/ManualTaskExecutor.swift#L107@d09ffc8ad6437bc278897279e33150d8e39ee3d5]
- Bien: `package import XCTest` en el soporte para no filtrar el framework a otros modulos [ref:https://github.com/swiftlang/sourcekit-lsp/blob/fcdf78d91fd77108a879c3e61bbd8f47b75f5347/Sources/SKTestSupport/Assertions.swift#L13@fcdf78d91fd77108a879c3e61bbd8f47b75f5347]
- Bien: capa base sin dependencias y capa de integracion encima [ref:https://github.com/pointfreeco/isowords/blob/c727d3a7c49cf0c98f2fa4f24c562f81e30165f7/Package.swift#L170@c727d3a7c49cf0c98f2fa4f24c562f81e30165f7]
- Anti-ejemplo: un arnes "base" que hace `@testable import CompanionUI`; movido tal cual a un target regular, rompe en release y arrastra UI a los tests de Core [repo:Tests/CompanionTests/TestKit.swift:5]
- Anti-ejemplo: soporte y tests en el mismo archivo (`enum Conformance` junto a `@Test`); un `@Test` dentro de un target regular no forma parte del producto de test [repo:Tests/CompanionTests/ConformanceTests.swift:25]

## 8. Trampas

- `@testable` en un target de soporte regular compila en debug y falla en release con "was not compiled for testing" [doc:https://github.com/swiftlang/swift/blob/635acfac65e866455abe016b2083b90a34f2d2e3/include/swift/AST/DiagnosticsSema.def#L1205@6.2]
- El CI no lo detecta: gates.sh solo compila en debug, donde todo modulo es testable [repo:scripts/gates.sh:17]
- Lo detecta `bundle.sh release`, porque `swift build` sin `--product` compila todos los targets no-test, incluidos los de soporte [repo:scripts/bundle.sh:10]
- Pasar `--product companion` a bundle.sh evitaria construir el soporte en release, pero solo esconde el fallo a ese script; `swift build -c release` a secas sigue rompiendo [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageManagerDocs/Documentation.docc/SwiftBuild.md#L279@6.2]
- Mover archivos a otro modulo vuelve invisibles los simbolos `internal`; sin `package` los test targets no los ven (y `@testable import` del soporte reintroduce la trampa de release) [repo:Tests/CompanionTests/TestKit.swift:9]
- `#expect` dentro de un target regular no recibe `-enable-cross-import-overlays`; helpers que dependan de overlays Testing+Foundation pueden no compilar ahi [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/Build/BuildDescription/SwiftModuleBuildDescription.swift#L1029@6.2]
- Un target de soporte de UI no debe copiar `.defaultIsolation(MainActor.self)` de UI: los fakes hoy compilan sin ese aislamiento y cambiaria su semantica de concurrencia [repo:Package.swift:36]
- `Conformance.repoRoot()` depende de la profundidad del archivo (tres niveles); ponerlo en una subcarpeta del target nuevo lo rompe en silencio y el test se salta [repo:Tests/CompanionTests/ConformanceTests.swift:155]
- `hudGatesTests` escanea solo `Tests/CompanionTests`; tras la division las puertas citan tests que ya no encuentra y fallan [repo:Tests/CompanionTests/ConformanceTests.swift:104]
- `Bundle.module` en un test sin recursos resuelve por el accesor interno de UI via `@testable`; si ese archivo termina en un target con dos `@testable` de modulos con recursos, o con recursos propios, cambia o se vuelve ambiguo [repo:Tests/CompanionTests/Island16m4Tests.swift:278]
- Clasificar por `import` subestima: 15 archivos dependen de UI solo a traves de `makeVoiceHarness` [repo:Tests/CompanionTests/VoiceSessionFakes.swift:31]
- Contexto `swift test` local en paralelo: sigue siendo un solo proceso con todos los targets, el paralelo no cambia [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/PackageLoading/PackageBuilder.swift#L1540@6.2]
- Contexto CI con `--no-parallel`: el flag se aplica a todo el producto de test, no hay que tocarlo por target [repo:scripts/gates.sh:245]
- Contexto `swift build -c release`: con A (sin `@testable`) compila; con B o A mal hecha, falla; con C no se construye [doc:https://github.com/swiftlang/swift-package-manager/blob/215e9f91823d7e44c379fa17bf1eef189438fc24/Sources/SPMBuildCore/BuildSystem/BuildSystem.swift#L22@6.2]
- Contexto Xcode/SourceKit: los targets regulares de soporte aparecen como modulos normales del paquete; el caso C en Xcode es el que no esta verificado [doc:https://github.com/swiftlang/swift-package-manager/issues/5344@2018-08-10]
- El pitch abierto para restringir testability a dependencias directas de test targets, si se implementa, dejaria de hacer testable en debug a lo que hoy lo es por accidente [doc:https://forums.swift.org/t/pitch-restrict-testability-to-direct-in-package-source-module-dependencies-of-test-targets/73921@2024-08-12]

## 9. Incertidumbre

- ASSUMPTION: `import Testing` compila en un target regular bajo `swift build -c release` en macos-26 con Command Line Tools, porque la ruta de Testing va en los flags globales. prueba: target regular de 5 lineas con `import Testing` y un `func expect` que use `#expect`, correr `swift build -c release` local y en CI.
- ASSUMPTION: los `@testable` de `VoiceSessionFakes` y `TestKit` son vestigiales (lo que usan ya es `package`). prueba: quitar el `@testable` de cada uno en una rama y ver que archivos dejan de compilar.
- ASSUMPTION: un `.testTarget` sin `@Test` puede ser dependencia de otros test targets y `swift test` corre bien con `--parallel` y `--no-parallel`. prueba: paquete minimo con `SupportTests` (sin tests, con `@testable import`) y `CoreTests` que depende de el; correr `swift test`, `swift build -c release` y abrirlo en Xcode.
- ASSUMPTION: Xcode compila un target regular de soporte sin `@testable` igual que SwiftPM. prueba: abrir el paquete en Xcode tras la division y correr la accion Test.
- ASSUMPTION: el `Bundle.module` de `Island16m4Tests` resuelve al bundle de UI. prueba: imprimir `Bundle.module.bundlePath` en ese test.
- [NEEDS CLARIFICATION: Karen, ¿el paquete se abre en Xcode o solo se trabaja con Command Line Tools? Decide si el contexto Xcode es requisito o solo nota.]
- [NEEDS CLARIFICATION: Karen, ¿se acepta subir a `package` los simbolos internos que hoy solo usan los fakes con `@testable`, o esos casos van a integracion?]

## 10. Checklist de estandar

- [ ] Ningun target regular de soporte contiene `@testable import` (gate por grep sobre sus carpetas).
- [ ] gates.sh o CI corre `swift build -c release` sin `--product`, para que un `@testable` en soporte falle en PR y no en el bundle.
- [ ] `CompanionTestKit` depende solo de Testing y Foundation; ni Core, ni Services, ni UI.
- [ ] Todo simbolo compartido entre modulos de test se declara `package`, no `public` ni `internal`.
- [ ] Los targets de soporte no llevan `.defaultIsolation(MainActor.self)` salvo decision explicita.
- [ ] `CompanionCoreTests` depende solo de Core y de soporte de capa Core o inferior; mismo principio para Services y UI.
- [ ] Un gate falla si un archivo de `Tests/CompanionCoreTests` importa Services o UI, o si uno de `Tests/CompanionUITests` importa Services.
- [ ] `Conformance.repoRoot()` sigue encontrando la raiz tras moverlo (test que falla si devuelve nil dentro del checkout).
- [ ] `hudGatesTests` busca tests en todo `Tests/`, no solo en `Tests/CompanionTests`.
- [ ] Ningun archivo de soporte contiene funciones `@Test`.
- [ ] `swift test` reporta el mismo numero de tests antes y despues (re-medido sobre el main del momento).
- [ ] `conformance/*.json`, `Extensions/browser/test/page.test.js` y `docs/ARCHITECTURE.md` dejan de nombrar `Tests/CompanionTests`.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | The Swift Programming Language, Access Control | swiftlang | main 1c05984 | 2026-09-30 | high |
| 2 | SE-0386 package access modifier | swiftlang | Swift 5.9 | 2026-09-30 | high |
| 3 | SE-0409 access-level on imports | swiftlang | Swift 6.0 | 2026-09-30 | high |
| 4 | DiagnosticsSema.def | swiftlang/swift | release/6.2 635acfa | 2026-09-30 | high |
| 5 | SwiftPM fuente y docs (BuildParameters+Testing, SwiftModuleBuildDescription, BuildSystem, PackageBuilder, UserToolchain, SwiftBuild.md, SwiftTest.md) | swiftlang | release/6.2 215e9f9 | 2026-09-30 | high |
| 6 | SwiftPM PR 8513 | swiftlang | 2025-04-25 | 2026-09-30 | high |
| 7 | SwiftPM issue 5344 (SR-8497) | swiftlang | 2018-08 | 2026-09-30 | medium |
| 8 | Pitch: restrict testability to direct dependencies | Swift Forums | 2024-08-12 | 2026-09-30 | medium |
| 9 | swift-nio Package.swift y NIOTestUtils | Apple | d09ffc8 | 2026-09-30 | high |
| 10 | sourcekit-lsp Package.swift y SKTestSupport | swiftlang | release/6.2 fcdf78d | 2026-09-30 | high |
| 11 | isowords Package.swift y TestHelpers | Point-Free | c727d3a | 2026-09-30 | medium |
| 12 | swift-composable-architecture Package.swift | Point-Free | 377da40 | 2026-09-30 | high |
| 13 | swift-numerics Package.swift | Apple | a7d826e | 2026-09-30 | high |

## Nota de reuso (2026-09-30)

Este brief se reusa para 21-tests C1/C2 (gates de capas y `Conformance.repoRoot`):
`scripts/check-test-layers.sh`, `Tests/CompanionTests/TestLayerGateTests.swift` y el
endurecimiento de `repoRoot(from:)`. El Estado no cambia.

## Nota de reuso, PR 2 (2026-09-30)

Este brief se reusa para 21-tests C3a-C3d (targets de soporte `CompanionTestKit`,
`CompanionCoreTestSupport`, `CompanionServicesTestSupport`, `CompanionUITestSupport`):
mover helpers sin cambiar comportamiento, todo `package`, sin `@testable` ni
swiftSettings en soporte. Un archivo transitorio `SupportImports.swift` con
`@_exported import` evita tocar los imports de ~390 archivos hasta PR 3. El Estado no cambia.

## Nota de reuso, PR 3 (2026-09-30)

Este brief se reusa para 21-tests C4-C8 (movimiento de los tests no-voz a
`CompanionCoreTests`, `CompanionServicesTests`, `CompanionUITests` y
`CompanionIntegrationTests`; regla R4 contra `@_exported import` y R3 extendida a los
cuatro targets de soporte). Solo `git mv` y imports explicitos; el lote de voz y
`SupportImports.swift` se quedan en `CompanionTests` hasta PR 4. El Estado no cambia.

## Nota de reuso, PR de casos negativos (2026-09-30)

Este brief se reusa para cerrar la deuda de QA de #63: casos negativos de la tabla de
dependencias de los targets de test (R3) y una comprobacion de `products` del manifiesto
(ningun producto lista un target de soporte, `CompanionTestKit` o un target de test).
Solo `scripts/check-test-layers.sh`, `Tests/CompanionCoreTests/TestLayerGateTests.swift` y
`CHANGELOG.md`; sin dependencias nuevas. El Estado no cambia.

## Nota de reuso, PR 4 (2026-10-01)

Este brief se reusa para 21-tests C9-C10 (cierre del programa): los tests de voz se
reparten entre `CompanionServicesTests` y `CompanionIntegrationTests`;
`VoiceSessionFakes` baja a `CompanionServicesTestSupport` sin `@testable`, con el unico
uso de UI (`SessionModel`) detras de un seam `SessionEventSink` que vive solo en el
soporte; los helpers solo-voz compartidos entre los dos destinos bajan al soporte mas
bajo que sus imports permitan. Se borran `SupportImports.swift`, el target transitorio
`CompanionTests` y sus exenciones en `check-test-layers.sh` (R3 y R4); cada archivo
importa explicitamente lo que usa. Deuda de #63/#64 en el mismo gate. Sin dependencias
nuevas. El Estado del brief no cambia; la spec pasa a CERRADO.
