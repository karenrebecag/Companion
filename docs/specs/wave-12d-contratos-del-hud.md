# Wave 12d — Los contratos del HUD, ejecutables

**Estado: ENTREGADA (2026-09-06).** Gates verdes (236 pruebas, 9 funciones
nuevas dentro del grupo `hudContractTests`); desviaciones en §9, revisiones
en §10. Cubierta por la aprobación de Karen del
2026-09-06 ("vamos. aplica y loopea para continuar con toda la spec de
cambios que sean visibles") sobre el orden aprobado de la Wave 12 (12a →
12b → 12c → **12d contratos y validadores**). Última pieza del HUD
(`~/Desktop/relay-hud-spec/`, fuera del repo). Cubre `relay-hud-spec/05`
§10 ("Auditor gates before we ship a HUD slice") y `00` §3 (las tarjetas
de rol de los auditores). No es visible para la usuaria: es lo que impide
que lo visible de 12a-12c se deshaga sin que nada falle. Por eso es corta.

Sin commit: Karen commitea.

---

## 1. El defecto, medido

**A. Las puertas del auditor son prosa.** `relay-hud-spec/05` §10 lista
ocho puertas ("hold sin abrir main", "overlay solo escucha", "Stop → Idle y
los hijos mueren", "sin cuerpo de skill en el historial", "sin clave de
allow-list → denegar", …). En el repo cada una está probada por algún test
de alguna wave, o por ninguno, y nadie sabe cuál sin leer 40 archivos
(grep 2026-09-06). Un contrato que no se puede ejecutar se olvida.

**B. El contrato de la proyección cubre seis campos de once.** La regla
`session-kind-write` de `conformance/ui-contract.json` prohíbe que la UI
escriba `kind|job|approvalQueue|cards|interruption|voice`; `notice`,
`holding`, `partial`, `targets` y `pipeline` (12b, 12c) quedaron fuera.

**C. "Hold sin abrir main" no tiene guardián.** Hoy `Sources/CompanionUI`
no activa la app (`NSApp.activate` / `makeKeyAndOrderFront`: cero
resultados; la island se muestra con `orderFrontRegardless`, que no roba
el foco). Nada impide que la próxima vista lo haga.

**D. Dos sitios deniegan a mano.** `ParentToolGuard.check` (Services) y
`ChatViewModel.gate` (UI) construyen la denegación del padre con
`Escalation.deniedByUser` como texto, fuera de `ContractError`, el único
sitio donde el código de error es contrato (`ParentTools.swift`, corpus
LAYERING §3). El texto empieza por `denied_by_user:` de casualidad.

**E. "Stop desde cualquier kind" está probado por muestreo.** Hay tests
de Stop desde idle, listening, un encargo y la voz hablando; no desde
hover, pending, toolExecuting ni completed.

**F. Huérfanos anotados en 12a §7.** `approvalToolJSON`,
`needsHeardNotice`, `executorPrompt`, `stepLabel`, `spokenSoFar`,
`commitAudio`, `passesAA`, `disableVoiceProcessing` tienen llamadores o
tests. `storedLabel` y `thumbnailData` tienen cero llamadores y cero tests
(grep 2026-09-06).

---

## 2. Lo que dice la spec de producto y el corpus

| Fuente | Qué dice | Qué tomamos |
|---|---|---|
| `relay-hud-spec/05` §10 | Ocho puertas; "a slice is not done if any fail" | Un libro de puertas ejecutable: `conformance/hud-gates.json` (puerta → fuente → tests que la prueban) y un runner que falla si un test nombrado deja de existir |
| `relay-hud-spec/00` §3, reductor | "Must not: treat voice Prewarm/Streaming as session kinds; treat `chat_input` as a fifth kind" | Un `switch` exhaustivo sobre `SessionKind` en un test: un quinto kind no compila |
| `relay-hud-spec/00` §3, overlay | "Must not: `setState("Idle")` as truth" | `session-kind-write` cubre los once campos de la proyección |
| `relay-hud-spec/00` §3, humano | "Must not: be required to open main for a normal hold" | Regla `main-activation`: `Sources/CompanionUI` nunca activa la app |
| `relay-hud-spec/05` §10 | "Stop → Idle; children die" | Un test recorre todos los kinds alcanzables y para desde cada uno |
| `relay-hud-spec/05` §10 | "Missing allow-list key → deny card" | Sin actor de permisos, la puerta del padre deniega (Services y UI) |
| `relay-hud-spec/05` §10 | "No skill body in Hist" | El cuerpo que `read_skill` devuelve vive en `Recall` (memoria del turno), nunca en el `ConversationStore`: test |
| Corpus LAYERING §3 / `specs/00-phase0-contracts.md` | El error es contrato: `code` estable + mensaje; `ContractError` con `denied_url`, `denied_path`, `invalid_args` | `ContractError.deniedByUser(language)`; las dos denegaciones pasan por `ParentToolOutcome.failed` |
| `conformance/ui-contract.json` (nuestro) | "El contrato es data, el runner es tonto" (modelo Willison) | El libro de puertas sigue el mismo patrón |

---

## 3. Decisiones

### 3.1 El libro de puertas: `conformance/hud-gates.json`

```json
{ "gates": [
  { "id": "hold-without-main", "source": "relay-hud-spec/05 §10; 00 §3 humano",
    "claim": "…", "tests": ["testHoldEffectsReachTheVoicePort", "..."],
    "rules": ["main-activation"] }, … ] }
```

Runner `hudGatesTests` (en `ConformanceTests.swift`): para cada puerta,
cada nombre de `tests` tiene que **correr**: existir como `func <nombre>(`
en las líneas lógicas (sin comentarios) de `Tests/CompanionTests` y llevar
`@Test` o ser invocado desde otra línea (`Conformance.testRuns`); cada
nombre de `rules` tiene que existir en `ui-contract.json`. Una puerta sin
tests ni reglas falla, y el conjunto de ids es exactamente el de esta tabla
(`HUDGates.expected`). Así el libro no puede citar pruebas que ya no
existen, que nadie llama, ni perder puertas sin que nada falle.

Puertas (las ocho de `05` §10 más las dos del reductor de `00` §3):

| id | Prueba |
|---|---|
| `hold-without-main` | regla `main-activation`; `testHoldEffectsReachTheVoicePort`, `testHoldThenReleaseSendsTheNativeText` |
| `overlay-listens-only` | regla `session-kind-write`; `testTheUIMustNotWriteTheKind`; `testIslandStateFromProjection` |
| `four-kinds-only` | `testFourKindsAndNothingElse` (nuevo) |
| `voice-is-a-port-not-a-kind` | `testConnectingKeepsTheKind`; `testThePartialIsAFieldNotAKind` |
| `stop-is-idle-children-die` | `testStopFromEveryKindIsIdle` (nuevo); `testStopReturnsToIdleAndKillsTheChildren` |
| `cards-are-not-the-conversation` | `testToolBodiesStayOutOfTheStore` (nuevo); `testCardsAreTransient` |
| `child-work-has-a-row` | `testJobStartedIsSubAgentRunning`; `testIslandStateFromProjection` |
| `no-skill-body-in-hist` | `testToolBodiesStayOutOfTheStore` (nuevo) |
| `missing-allow-list-denies` | `testTheGateFailsClosedWithoutAnActor` (nuevo); `testForeignURLDeniedIsAnInstruction` |
| `one-host-per-sheet` | `testIslandYieldsTheSheetToMain` |

### 3.2 Reglas nuevas en `ui-contract.json`

- `session-kind-write`: patrón ampliado a
  `kind|job|approvalQueue|cards|interruption|voice|notice|holding|partial|targets|pipeline`
  y a las formas de escribir que no son `=`: `+=`, `-=`, subíndice,
  `.insert`, `.remove*`, `.popLast`, `.swapAt` (revisiones, §10).
- `main-activation`: `NSApp.activate`, `NSApplication.*.activate`,
  `NSRunningApplication.*.activate`, `makeKeyAndOrderFront`, `.makeKey()`,
  `activate(ignoringOtherApps:)`, `activate(options:)` y `.orderFront(` en
  `Sources/CompanionUI`. `orderFrontRegardless` y `orderOut` no cuentan.
  Hoy cero; baseline vacío.

### 3.3 El error como contrato

`ContractError.deniedByUser(_ language:)` → `code: "denied_by_user"`,
`message:` el texto de `Escalation.deniedByUserMessage(language)` (sin el
prefijo). `wire` produce el mismo string que hoy devuelve
`Escalation.deniedByUser`, así que el modelo no nota el cambio y los tests
que comparan con `Escalation.deniedByUser` siguen valiendo.
`ParentToolGuard.check` y `ChatViewModel.gate` construyen la denegación
con `ParentToolOutcome.failed(.deniedByUser(language), target:)`.

### 3.4 Tests de contrato nuevos (`HUDContractTests.swift`)

- `testFourKindsAndNothingElse`: `switch` exhaustivo sobre `SessionKind` y
  `SessionPhase` sin `default`; un caso nuevo rompe la compilación del
  test, que es el punto.
- `testStopFromEveryKindIsIdle`: lleva la máquina a hover, listening,
  pending, thinking, speaking, toolExecuting, subAgentRunning (con encargo
  y con una petición en cola) y completed; desde cada uno `.stop` deja
  `kind == .idle`, `job == nil`, cola vacía, `holding == false`,
  `interruption == .userStopped`, y `cancelJob` + `resolveApproval(false)`
  cuando había encargo o cola.
- `testTheGateFailsClosedWithoutAnActor`: `ParentToolGuard(approvals: nil)`
  deniega una URL no dicha con `denied_by_user:`; `ChatViewModel` sin
  `approvals` tampoco abre y el modelo lee lo mismo.
- `testToolBodiesStayOutOfTheStore`: `read_skill` con un cuerpo marcado;
  el historial del modelo lo lleva, el `ConversationStore` no.

### 3.5 Huérfanos

`storedLabel` y `thumbnailData` no tienen llamadores ni tests: son
candidatos a borrar, y borrar está en la lista de bloqueo. Quedan
anotados en §7 para Karen. El resto tiene llamadores o tests y se queda.

### 3.6 Archivos

| Capa | Archivo | Cambio |
|---|---|---|
| Core | `ParentTools.swift` | `ContractError.deniedByUser` |
| Core | `EscalationCopy.swift` | `deniedByUserMessage`; `deniedByUser` pasa por `ContractError` |
| Services | `ParentToolGuard.swift` | `.failed(.deniedByUser)` |
| UI | `ChatViewModel.swift` | `gate` idem |
| conformance | `ui-contract.json`, `hud-gates.json` (nuevo) | §3.1, §3.2 |
| Tests | `ConformanceTests.swift` (+`hudGatesTests`), `HUDContractTests.swift` (nuevo) | §3.4 |
| scripts | `gates.sh` | una línea: cuántas puertas tiene el libro |

---

## 4. Restricciones

- Sin borrar código (§3.5). Sin cambios de comportamiento visibles: el
  texto que lee el modelo al ser denegado es idéntico.
- Core puro; sin `try?` en Core/Services.
- El runner del libro no ejecuta tests: solo comprueba que existen. Los
  ejecuta `swift test` como siempre.

---

## 5. TDD (RED → GREEN)

| # | Test | Archivo |
|---|---|---|
| 1 | `hudGatesTests`: el libro carga, cada puerta tiene tests o reglas, cada test nombrado existe, cada regla existe | ConformanceTests |
| 2 | `testFourKindsAndNothingElse` | HUDContractTests |
| 3 | `testStopFromEveryKindIsIdle` | HUDContractTests |
| 4 | `testTheGateFailsClosedWithoutAnActor` | HUDContractTests |
| 5 | `testToolBodiesStayOutOfTheStore` | HUDContractTests |
| 6 | `ContractError.deniedByUser(.en).wire == Escalation.deniedByUser(.en)` (y `.es`) | HUDContractTests |
| 7 | La regla `main-activation` existe y `session-kind-write` cubre los once campos (`uiConformanceTests` ya la aplica; aquí se comprueba el contrato mismo) | HUDContractTests |
| 8 | `testTheLedgerKeepsItsTenGates`: el libro tiene exactamente los diez ids de §3.1 (revisión) | HUDContractTests |
| 9 | `testTheLedgerOnlyCountsTestsThatRun`: `@Test` o invocada cuenta; declarada sin llamar, en comentario o inexistente no (revisión) | HUDContractTests |

---

## 6. Prueba manual (Karen)

No hay: nada cambia en pantalla. `./scripts/gates.sh` muestra "libro de
puertas del HUD: 10 puertas".

---

## 7. Fuera de alcance

- Borrar `storedLabel` / `thumbnailData` (bloqueo de borrado): decisión de
  Karen.
- Glow / outline (G5), confirmación de spawn (G6): sin superficie aún.
- Los contratos del `AxPort` (canary, `stale_tree`): con la acción AX.
- Dictado en el campo enfocado (`relay-hud-spec/03` §, `05` §4, corpus
  spec 11): siguiente wave visible.

---

## 8. Fuentes

- `~/Desktop/relay-hud-spec/00-goals-and-auditors.md` §3, §5;
  `05-replication-checklist.md` §4, §10, §11.
- `AI_Research/AIResearch/specs/00-phase0-contracts.md`; `LAYERING.md` §3
  (el error como contrato).
- companion: `conformance/ui-contract.json`, `docs/specs/wave-12a-reductor-de-sesion.md` §7, §9.10.

---

## 9. Desviaciones respecto a §3

| # | Spec | Entregado | Por qué |
|---|---|---|---|
| 1 | El runner comprueba que el test citado existe (`func <nombre>(` en el texto) | Comprueba que corre: líneas lógicas sin comentarios, `@Test` o invocado (`Conformance.testRuns`) | Revisión de código: una función a la que nadie llama, o un nombre en un comentario, daba la puerta por cubierta |
| 2 | Nada fija el conjunto de puertas | `testTheLedgerKeepsItsTenGates` compara los ids con `HUDGates.expected` | Revisión de seguridad: borrar una puerta encogía el libro sin que nada fallara |
| 3 | `testDeniedByUserIsAContractError` comparaba `wire` con `Escalation.deniedByUser` | Además compara con el string literal en `en` y `es` | Revisión de seguridad: `Escalation.deniedByUser` se define a través del `ContractError`, así que la igualdad era tautológica |
| 4 | `session-kind-write` con `=`, `.append`, `.remove` | Más `+=`, `-=`, subíndice, `.insert`, `.popLast`, `.swapAt` | Las dos revisiones: esas formas escribían sin que la regla lo viera (hoy inofensivo por `private(set)`) |
| 5 | `main-activation` con las tres formas de §3.2 | Más `activate(options:)`, `NSApplication.*.activate`, `NSRunningApplication.*.activate`, `.makeKey()`, `.orderFront(` | Revisión de código: la API que Apple recomienda hoy (`activate(options:)`) no coincidía con ninguna |
| 6 | `ParentToolGuard.check` sacaba `url` de los argumentos a mano | `ParentTool.target(of:)`, como `ChatViewModel.gate` | Revisión de código: dos extracciones del mismo objetivo |

---

## 10. Revisiones (2026-09-06)

### 10.1 Seguridad (security-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Media | Borrar una puerta de `hud-gates.json` pasaba el runner y `gates.sh` solo imprimía un número menor | Test primero: `testTheLedgerKeepsItsTenGates` (ids exactos, sin repetidos) |
| 2 | Baja | `testDeniedByUserIsAContractError` era tautológico: `Escalation.deniedByUser` es el `wire` del `ContractError` | Test primero: golden strings en `en` y `es` dentro del mismo test |
| 3 | Baja | `session-kind-write` no veía `+=` ni `.insert` (inofensivo hoy: `SessionModel.projection` es `private(set)`) | Test primero: seis formas en `testTheProjectionRuleCoversEveryField`; patrón ampliado |
| — | Verificado | La puerta del padre falla cerrada en Services y UI (`remembered` nulo, sin actor, hoja rechazada); `ParentToolRunner.openURL` revalida la URL; el runner y `gates.sh` solo leen JSON, no lo ejecutan; `persist()` es el único escritor del `ConversationStore` y solo lleva `text` | — |
| N | Nota | El árbol no tiene baseline commiteado (`git status` es `??`), así que "sin cambios en `ParentToolPolicy`" se comprobó leyendo, no con `git diff` | Karen commitea |

### 10.2 Código (code-reviewer)

| # | Severidad | Hallazgo | Cierre |
|---|---|---|---|
| 1 | Alta | El runner buscaba `func <nombre>(` en el texto crudo: una función que nadie invoca (los tests de `HUDContractTests` corren porque `hudContractTests` los llama a mano) o un nombre en un comentario daban la puerta por cubierta | Test primero: `testTheLedgerOnlyCountsTestsThatRun`; `Conformance.testRuns` sobre líneas lógicas exige `@Test` o una llamada |
| 2 | Alta | `main-activation` no veía `NSApplication.shared.activate(options:)`, `makeKey()` ni `orderFront(` | Test primero: cinco formas modernas cuentan, `orderFrontRegardless` y `orderOut` no; patrón ampliado. La UI no usa ninguna hoy (grep) |
| 3 | Media | `session-kind-write` sin `+=`, `-=` ni subíndice | Cerrado con el 3 de seguridad (`-=` y `cards[0] =` añadidos al test) |
| 4 | Baja | `ParentToolGuard.check` duplicaba `ParentTool.target(of:)` | `ParentTool.target(of:)`; las pruebas de la puerta ya cubren el objetivo |
| — | Verificado | `switch` exhaustivos sin `default` (kind, fase, razón); las diez rutas de `testStopFromEveryKindIsIdle` llegan al kind que dicen; los once campos son exactamente los de `SessionProjection`; el cuerpo de `read_skill` vive solo en `Recall`; Core/Services puros | — |
