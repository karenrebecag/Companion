# Tests: un target por modulo

Estado: CERRADO (2026-10-01). Aprobado por Karen el 2026-09-30; entregado en
#60 (gates), #62 (soporte), #63 (tests no-voz), #64 (casos negativos) y el PR
de la voz, que retira `CompanionTests`.
Research: `docs/research/tests-por-modulo-soporte.md` (APROBADO).

## Objetivo

Hoy hay un solo `CompanionTests` que depende de Core, Services y UI: un test
de Core compila contra UI y nada impide que un test de dominio se apoye en
un adaptador. La convencion de SwiftPM (y lo que hacen sourcekit-lsp y
swift-package-manager) es `Tests/<Target>Tests/`, un target de test por
target de produccion. Asi las capas tambien se cumplen en los tests.

## Lo que hay (391 archivos)

| Importa | Archivos | Destino |
|---|---|---|
| Solo Core | 94 | `CompanionCoreTests` |
| Core + Services | 153 | `CompanionServicesTests` |
| Solo Services | 8 | `CompanionServicesTests` |
| Core + UI | 67 | `CompanionUITests` |
| Solo UI | 9 | `CompanionUITests` |
| Core + Services + UI | 55 | `CompanionIntegrationTests` (UI no depende de Services) |
| Ninguno | 5 | segun lo que prueben (conformance, fixtures) |

239 archivos usan `@testable import` (164 Services, 98 UI, 17 Core). En los
targets de test eso sigue bien: los tests compilan en debug. El problema es
solo para un target de soporte, que es una libreria normal.

## Soporte compartido (el punto dificil)

| Archivo | Importa | Lo usan |
|---|---|---|
| `ChatFakes` | Core + Services | 2 C, 37 CS, 25 CSU, 15 CU |
| `VoiceSessionFakes` | Core + Services + `@testable` UI | 26 CS, 21 CSU, 1 CU |
| `ScreenHandsFakes` | Core + Services | 8 CS, 4 CSU |
| `BrowserToolSupport` | Core + `@testable` Services | 7 CS |
| `DiagramTestKit` | Core + `@testable` Services | 1 CS, 4 CSU |
| `SSEFixtures` | nada | 5 CS |
| `Approvals16q1Rig` | Core + `@testable` Services + `@testable` UI | 3 CSU |

Mas el arnes (`TestKit.swift`: `expect`/`expectEq`) y `ConformanceTests.swift`
(`Conformance.repoRoot`), que usan todos.

Consecuencia: un solo `CompanionTestSupport` que dependa de Services y UI
haria que los tests de Core enlacen Services y UI, que es justo lo que este
paso quiere impedir. Y los cuatro fakes con `@testable` no compilan en un
target de soporte en release.

Opciones (detalle y fuentes en el brief):
- **A (recomendada) Soporte por capas, targets regulares sin `@testable`.**
  - `CompanionTestKit`: arnes + `Conformance`, solo Testing y Foundation. Lo usan todos.
  - Soporte por capa (`CompanionServicesTestSupport`, etc.) con API `package`.
    Es el patron de SwiftPM, sourcekit-lsp y swift-nio.
  - `ChatFakes` se parte: lo que finge puertos de Core baja a una capa que los
    tests de UI puedan usar sin Services. El planner decide el corte.
  - Un target de soporte de UI NO copia `.defaultIsolation(MainActor.self)`:
    cambiaria la semantica de concurrencia de los fakes.
- **B Un solo `CompanionTestSupport`.** Las capas dejan de cumplirse en los
  tests y los `@testable` rompen `swift build -c release`. Descartada.
- **C Soporte como `.testTarget` sin tests.** `@testable` sigue compilando y
  release no lo construye, pero no esta documentado y en Xcode no esta
  verificado. Solo como puente para un fake que de verdad necesite internos,
  y solo si pasa la prueba previa 3.

## Pruebas previas (antes de mover nada)

El brief deja cinco supuestos sin ejecutar. Se prueban primero en una rama
desechable; si alguno falla, la spec vuelve a Karen:

1. Un target regular con `import Testing` y `#expect` compila con
   `swift build -c release`, local y en CI (macos-26).
2. Los `@testable` de `TestKit.swift` (lineas 5 y 124) y de
   `VoiceSessionFakes` son vestigiales: quitarlos y ver que deja de compilar.
3. Solo si hace falta C: un `.testTarget` sin `@Test` como dependencia de
   otro, con `swift test` en paralelo y serie.
4. `Island16m4Tests` resuelve `Bundle.module` al bundle de UI.
5. Si Karen usa Xcode: abrir el paquete y correr Test tras la division.

## Trampas que la ejecucion tiene que cubrir

- `@testable` en un target regular compila en debug y truena en release; el
  CI solo compila debug. Van dos gates nuevos: `swift build -c release` en
  `gates.sh` y un grep que prohibe `@testable` fuera de `Tests/*Tests/`.
- Clasificar por `import` subestima: 15 archivos dependen de UI solo por
  `makeVoiceHarness`. Si `VoiceSessionFakes` no se puede partir, van a
  integracion y cambian los conteos de la tabla.
- `Conformance.repoRoot()` depende de la profundidad del archivo; en una
  subcarpeta se rompe y el test se salta en silencio.
- `hudGatesTests` escanea solo `Tests/CompanionTests`; hay que ampliarlo.
- La division no aisla en ejecucion: sigue siendo un proceso, asi que el
  paralelo y el estado global no cambian (eso lo cubre `suite-estable`).

## Renombres por wave

41 archivos de test se llaman por wave (`Approvals16q1Round3Tests`,
`Choice16m6FixesTests`). Recomendado: **PR aparte despues**. Mover de target
ya es un rename; renombrar en el mismo PR hace el historial ilegible. Nombre
por comportamiento, con una tabla viejo -> nuevo revisada antes de aplicar.

## Lo que se rompe

- `Package.swift`: los `.testTarget` y los de soporte (config raiz).
- Referencias a `Tests/CompanionTests`: `conformance/hud-gates.json`,
  `conformance/ui-contract.json`, `Extensions/browser/test/page.test.js`,
  `docs/ARCHITECTURE.md`, `docs/REFERENCE.md`. Las specs historicas en
  `docs/specs/` no se tocan.
- Los tests que leen fuentes por ruta ya resuelven desde `Conformance.repoRoot()`.

## Secuencia

Despues de que se integre 21c-3 (b6 retiene archivos de test nuevos hasta
entonces) y antes de la division de `VoiceSession`, porque esa mueve tests
de voz y conviene que ya caigan en su target.

## Ejecucion

pruebas previas -> planner (corte de `ChatFakes`/`VoiceSessionFakes`, orden
de movimiento) -> tdd-guide (gates de capas, release y `@testable`) ->
movimiento mecanico con `git mv`, un target por commit -> reviewers -> PR.

## Aceptacion

- `swift build -c release` y `scripts/gates.sh` verdes; release entra a gates.
- Cada target de test compila solo con sus dependencias declaradas.
- Mismo numero de tests que main al arrancar (1509 al medir).
- Un gate impide que un test de Core o UI importe una capa que no le toca.
- Un gate impide `@testable` en targets de soporte.

## Decisiones de Karen (2026-09-30)

1. Opcion A; C solo como puente, previa prueba 3.
2. Los internos que usan los fakes suben a `package`.
3. Se aprueban los cambios a `Package.swift` y los gates de release y `@testable`.
4. ADR: las capas siguen siendo 4; los targets de soporte y `CompanionCopy` no son capas.
5. Solo Command Line Tools: la prueba previa 5 (Xcode) es nota, no requisito.
6. Renombres por wave en un PR aparte, despues.
