# Integración de `origin/main` en `feat/ui-gap` (PR #37)

Rama: `integrate/main-into-ui-gap`, merge de `origin/main` sobre `origin/feat/ui-gap` (31c2d13).
Base común: `a8742fc`. Main aporta 48 commits (20c, 20d A-C, 18, 18b, ADR 007); feat/ui-gap
aporta 16p/16h/16m, 16q-1 y 16q-2.

Método: cada uno de los 22 archivos en conflicto se resolvió por hunk, leyendo lo que cada
lado cambió contra la base. Ningún archivo se tomó entero de un lado salvo donde el otro lado
no lo tocó en ese hunk. Donde los dos diseños de aprobación se contradicen, se quedó el **más
restrictivo** (regla de la integración).

## 1. Decisiones de comportamiento (leer primero)

| # | Choque | Main (20c/20d) | feat/ui-gap (16q-1) | Queda |
|---|---|---|---|---|
| C1 | Qué puede aprobar un sí hablado | Solo bajo riesgo (`ApprovalRisk.low`), con el booleano del modelo, también en realtime (HACK sin comparar palabras) | `SpokenYes.admits`: clásico, anunciado antes del hold, palabras de ESE hold en la lista cerrada; realtime nunca; `app:` nunca | **Las dos cosas a la vez**: bajo riesgo **y** `SpokenYes.admits`, nunca `app:`, nunca MCP (`isMCP`), nunca realtime. Una herramienta del navegador, `bridge_session`, `run_shell`, escrituras y `open_url` son `high` y piden clic aunque el sí sea claro y anunciado. |
| C2 | A qué petición llega el sí | `approvalSpoken(requestId:)` resuelve solo si ESA es la que muestra la hoja (primera de la cola) | `approvalSpoken(requestId:)` resuelve la petición nombrada donde esté en la cola | **Nombrada y además la que muestra la hoja.** Un sí admitido para un encargo mientras la hoja enseña otra cosa no resuelve nada; las dos esperan su clic. Ronda 1 de revisión: la voz lo sabe. El reductor emite `approvalFront(requestId:)` cada vez que cambia la primera de la cola y `SessionModel` lo lleva al puerto de voz (`VoiceControlling.approvalFront`); `VoiceSession` guarda `sheetFront`. Si la pendiente de la voz no es la del frente, un sí **o un no** hablado devuelve `.needsClick` y la pendiente sigue armada para cuando llegue al frente. Sin hoja cableada (`sheetFront == nil`, sesión sin reductor) la voz contesta como antes y el reductor sigue siendo el que descarta. |
| C3 | Hoja de MCP en realtime | `SessionModel.onApprovalClosed` → `VoiceSession.approvalClosed(id, approved:)`, reloj propio `mcpApprovalTimeout`, diccionario por id | `ParentToolGuard.decide` sobre el actor `Approvals` (mismo auto-deny que las puertas del padre), id duplicado rechazado, sin actor falla cerrada | **El de feat/ui-gap** (punto único de decisión, duplicado rechazado, falla cerrada). De main se conserva: `isMCP` en la petición, hoja sin "Recordar" y con todos los argumentos, `require_approval: "always"` fijo, y que colgar la sesión cierre las hojas MCP sin mandar nada al servidor (`dropPendingMCPApprovals`, reescrito sobre `mcpGuard.withdraw`). Se retiraron `onApprovalClosed`, `mcpApprovalTimeout` y `mcpApprovalTimers`: el efecto `approvalClosed` del reductor ya lleva el cierre al puerto de voz. Ronda 1 de revisión (HIGH): al pasar MCP por `ParentToolGuard.answer`, la memoria de "Recordar" (clave por nombre de herramienta) alcanzaba a un MCP que se llamara como una local (`run_shell`, `write_file`, `open_url`...): se aprobaba o negaba solo, sin hoja. En main MCP nunca tocaba `Approvals`; el hueco nace de la fusión. Hoy la ruta realtime nombra `servidor/herramienta`, así que no coincidía con ninguna clave, pero nada en `answer` lo impedía. Se cierra en origen: `ApprovalKey.from` devuelve nil para `isMCP` (nunca se consulta ni se guarda), `answer` salta la memoria si `isMCP` (defensa en profundidad para cualquier proveedor) y `resolveNow` no guarda ni dice `remember` para MCP. |
| C4 | No hablado a un MCP | El modelo no debe llamar `resolve_approval` | Un no hablado rechaza la petición MCP más nueva | **El no hablado rechaza** (negar es la dirección segura; nunca aprueba). Se conserva el prompt de 16q-1 ("tarjeta", sí nunca, no sí). Ronda 1 de revisión: la petición entra en `pendingMCPApprovals` antes de que el actor la aparque; un no en esa ventana no retiraba nada y devolvía `.resolved`. `ParentToolGuard.withdraw` ahora dice si retiró algo y, si no, la voz devuelve `.needsClick`. |
| C5 | Negar la primera acción de un encargo | `stop()` total | `stopJob(dueño)`, solo ese encargo | **`stopJob(dueño)`** (16q-1). La regla "MCP y herramientas del navegador no son acciones del encargo" de main se agregó a `isActiveJobs`. |
| C6 | `ActionReceipt` (add/add) | Recibo de 20d con deshacer (`id`, `Kind`, `Undo`) | Recibo de 16h-3: líneas de estado probadas | **Dos tipos.** El de 16h-3 conserva el nombre `ActionReceipt`; el de 20d pasa a `UndoReceipt` (archivo `UndoReceipt.swift`). Solo cambia el nombre del tipo; comportamiento idéntico. |

## 2. Archivos de seguridad

### `Sources/CompanionServices/VoiceSessionApprovals.swift`
- Main: MCP a la hoja por `onApprovalClosed` con reloj propio; `answerPendingApproval` con `ApprovalRisk` y resultado `Bool`; nota limpia en `approvalClosed(_:approved:)`.
- feat/ui-gap: `noteMCPApproval` por `mcpGuard.decide`, duplicado rechazado; `SpokenYes`, `HeardInHold`, `approvalAnnounced`, FIFO de cerradas; resultado `SpokenApproval`.
- Queda: la versión de feat/ui-gap más el filtro `ApprovalRisk.of(...) == .low && !isMCP` dentro de `admitsSpokenYes` (C1), y `dropPendingMCPApprovals()` que retira por el actor (C3). Si una petición MCP ya no está viva cuando el actor contesta (colgada), no se manda nada al servidor; solo se suelta la hoja.

### `Sources/CompanionServices/ParentToolGuard.swift`
- Main: `answer(_:parked:) -> SheetAnswer` (aprobado / negado / vencido / rechazado por tope de hojas) para el cool-down del puente.
- feat/ui-gap: `decide(_:) -> ApprovalResponse` como punto único.
- Queda: `answer` de main es la implementación; `ask` y `decide` son vistas sobre ella (`decide` lleva `timedOut`). Un solo camino hacia el actor.

### `Sources/CompanionCore/SessionMachine.swift` (+ `SessionMachineJobs.swift`, auto-mergeado)
- Main: `approvalSpoken` solo si es la primera; `isJobRequest` excluye MCP y navegador; `.acted` → `actionDone`; recibo con deshacer.
- feat/ui-gap: reducer partido en Jobs/Brakes/Resting/Dictation; `stopJob(dueño)`; `approvalClosed`.
- Queda: estructura de feat/ui-gap; C2 en `approvalSpoken`; `.acted` en `observe` de Jobs; exclusiones de main en `isActiveJobs` (C5). `reduce` pasó de `private` a interno porque `observe` vive en otro archivo del mismo reductor.

### `Sources/CompanionCore/SessionTypes.swift`
- Los dos lados cambiaron `approvalSpoken` a `(requestId:approved:)`; mismo tipo, comentario unido (C2). Campos de main (`receipt: UndoReceipt?`, `actionDone`, `receiptExpired`, `undoPressed`, `scheduleReceiptExpiry`, `undo`) y de feat/ui-gap (`stopVoice`, `stopJob`, `approvalClosed`, etc.) conviven.

### `Sources/CompanionCore/MCPTools.swift`
- Main: prompt "hoja, NO llames resolve_approval"; `requireApproval` fuera; token al Keychain.
- feat/ui-gap: prompt "tarjeta; un sí nunca; un no sí".
- Queda: el prompt de feat/ui-gap (C4) sobre la estructura de main (sin `requireApproval`, `always` fijo).

### `Sources/CompanionServices/RealtimeRuntime.swift`
- Solo el comentario chocaba; el código de main (`isMCP: true`) ya estaba auto-mergeado. Comentario de feat/ui-gap.

### `Sources/CompanionServices/VoiceSession.swift`
- Main: `pendingMCPApprovals` por diccionario, `mcpApprovalTimers`, parámetro `mcpApprovalTimeout`.
- feat/ui-gap: arreglo, `heardThisHold`, `closedApprovals`, `mcpGuard`, `askedAloud`.
- Queda: feat/ui-gap; se quitó el parámetro `mcpApprovalTimeout` del init (C3).

### `Sources/CompanionServices/VoiceSessionTeardown.swift`
- Main: `dropPendingMCPApprovals()`. feat/ui-gap: `voiceClosed` y silenciar avisos.
- Queda: las tres cosas, en ese orden.

### `Sources/CompanionServices/ParentToolRunner.swift` y `Sources/CompanionApp/CompanionMainSensing.swift`
- Main: `onAct` (recibo 20d) y el `ActionUndoer`. feat/ui-gap: `location` y `locationChannelOn`, `islandEvents`.
- Queda: todo. `onAct` se declara ANTES de `location`/`locationChannelOn` para que `locationChannelOn: { ContextPreference.locationChannelOn }` siga siendo el último argumento de `ParentToolRunner(`: el regex de `conformance/location-wiring.regex` (Gate 3) lo exige.

### `Sources/CompanionCore/Sheets.swift`
- Main borró la lista negra `forbidden` (la reemplaza `FormulaPolicy`, allowlist). feat/ui-gap agregó `maxSheetBytes`.
- Queda: `maxSheetBytes` sin la lista negra.

## 3. UI / App

- `Sources/CompanionUI/SessionModel.swift`: `islandEvents`/`report` (feat/ui-gap) y `receiptExpiry`/`onUndo` (main). El `noticeExpired(card)` de feat/ui-gap con los casos de recibo de main. Se retiró `onApprovalClosed` y `notifyClosedApprovals` (C3); `CompanionMainVoice.swift` ya no lo cablea.
- `Sources/CompanionUI/IslandView.swift`: feat/ui-gap partió la isla en archivos; las dos adiciones de main se movieron a su sitio nuevo: la fila del recibo con Deshacer a `Island/Work/IslandView+Status.swift` y `IslandCopy.receipt` a `Island/IslandCopy.swift`. `IslandReceiptRow` (auto-mergeada en `Island/IslandPieces.swift`) usa `CapsuleChipStyle(ink: .island, density: .compact)` porque 16p-2 retiró `IslandChipStyle`.
- `Sources/CompanionUI/CompanionRootView.swift`: `browser:` (main) y `grabber:` (feat/ui-gap).
- `Sources/CompanionApp/CompanionMain.swift` / `CompanionMainWindow.swift`: la firma de `presentWindow` toma `env: LaunchEnvironment` de main sin `choice` (feat/ui-gap retiró `ExecutorChoice`) y con `appTools`; `grabber:` y el guardado de MCP en el Keychain con `log:` conviven.
- `Localizable.strings` en y es: unión de claves, sin duplicados (verificado por script).

## 4. Tests cambiados y por qué

Ningún test se borró. Todo cambio responde a C1-C6.

| Archivo | Lado | Cambio | Motivo |
|---|---|---|---|
| `MCPToolsTests.swift` | main | El arnés `mcpHarness` inyecta un actor `Approvals` con el plazo en vez de cablear `onApprovalClosed`; `answerPendingApproval` se compara con `.resolved`; los cierres directos usan `approvalClosed(requestId:)`; el clic tardío tras colgar se manda como `approvalAnswered` al modelo | C3: el cierre y el clic viajan por el actor; sin actor la petición falla cerrada |
| `ApprovalRiskTests.swift` | main | `Bool` → `SpokenApproval` (`.needsClick`, `.nothingPending`); el cierre llega por el puerto de voz (`Q1SessionVoiceBox`); `testALowRiskRequestStillResolvesByVoice` pasa de realtime a clásico (anunciado, "sí, dale" en el hold siguiente) | C1: realtime nunca acepta un sí; C3 |
| `MCPApprovalCoreTests.swift` | main | El encargo y su acción llevan dueño; se espera `cancelJobByID(dueño)` | C5 |
| `SessionModelTests.swift` | ambos | Se quedó la versión de feat/ui-gap: en realtime el sí no llega al reductor | C1 |
| `SessionMachineTests.swift` | ambos | Se quedó la versión de feat/ui-gap (encargo con dueño, `cancelJobByID`) | C5 |
| `Approvals16q1Rig.swift` | feat/ui-gap | `q1Req` usa `find_places` por defecto; `q1AskedAndSaid` acepta `tool:` | C1: con `run_shell` el filtro de riesgo taparía lo que estas suites prueban (palabras, hold, anuncio) |
| `Approvals16q1Tests.swift` | feat/ui-gap | `sheetRequest` usa `find_places`; `testASpokenYesNeverTouchesAnAppWriteThatIsFirstOnTheSheet` ahora espera que nada se resuelva y las dos peticiones sigan en la hoja | C1, C2 |
| `SpokenApprovalTests.swift` | feat/ui-gap | La hoja de prueba es `find_places`, no `Bash` | C1 |
| `StopParity16qTests.swift` | feat/ui-gap | `testASpokenYesResolvesExactlyTheRequestItNames`: con otra delante no resuelve; una vez en la hoja, sí | C2 |
| `VoiceSessionFakes.swift` | main | Sin el parámetro `mcpApprovalTimeout` | C3 |
| `UndoReceiptTests` (antes `ActionReceiptTests`), `ActionUndoTests`, `NativeExecutorTests`, `ParentDeliverablesTests` | main | `ActionReceipt` → `UndoReceipt` | C6 (solo el nombre) |
| `MergedSpokenYesTests.swift` | nuevo | Un sí claro y anunciado pide clic para `run_shell`, `Bash`, escrituras, `open_url`, todas las herramientas del navegador y `bridge_session`; resuelve `find_places` | Fija C1 |
| `MCPRememberIsolationTests.swift` | nuevo (ronda 1) | Un MCP llamado `run_shell` con `ls` no hereda un sí ni un no recordado para el `run_shell` local: aparca en la hoja y no se contesta solo; sin clave; `answer` no consulta la memoria; recordar su respuesta no guarda nada | Fija C3 (HIGH) |
| `SpokenAnswerFrontTests.swift` | nuevo (ronda 1) | El reductor emite `approvalFront`; `SessionModel` lo lleva a la voz; un sí y un no para una petición detrás del frente piden clic y no la desarman; ya en el frente, resuelven | Fija C2 / §7 |
| `MCPSpokenNoRaceTests.swift` | nuevo (ronda 1) | Un no antes de que el actor aparque la petición MCP pide clic; aparcada, la rechaza | Fija C4 |
| `UndoReceiptTests.swift` | main | Renombrado desde `ActionReceiptTests.swift` (y la función de entrada a `undoReceiptTests`): prueba `UndoReceipt` | C6 (solo el nombre) |
| `BackgroundJobCoreTests.swift` | feat/ui-gap | `testAnUntaggedRequestAfterAStopIsNotDenied`: el único efecto esperado pasa de `[]` a `[.approvalFront("u1")]`; sigue sin negar nada | C2 (ronda 1) |
| `SessionMachineTests.swift` | ambos | `kinds()` filtra `approvalFront` junto a `approvalClosed`: los dos son contabilidad de la voz, no decisiones del reductor | C2 (ronda 1) |
| `Approvals16q1Rig.swift`, `VoicePortsTests.swift`, `VoiceViewModelTests.swift` | ambos | Los falsos de `VoiceControlling` implementan `approvalFront` (sin valor por defecto, como `approvalClosed`) | C2 |

## 5. Gates

- `scripts/gates.sh`: la lista de archivos del reductor ya es la unión (main no agregó extensiones de `SessionMachine`): `SessionMachine(Jobs|Dictation|Brakes|Resting)?.swift`. Main agregó el paso de `node --test` de la extensión; se conserva.

## 6. Invariantes verificados

- Un sí hablado nunca aprueba `app:`, MCP ni una herramienta del navegador (C1; `MergedSpokenYesTests`, `VoiceApprovalTests`, `Approvals16q1Tests`, `MCPToolsTests`).
- Un sí exige lista permitida, su hold, la petición anunciada y nombrada y además la que muestra la hoja (C1, C2).
- Elegir una opción o mencionar una app no es consentimiento (sin cambios de 16q-2).
- Los tres frenos: `stopVoice`, `stopJob` (solo ese encargo), `.stop` (`StopParity16qTests`, `JobStopByIDTests`).
- MCP realtime va a la hoja; id duplicado rechazado (`Approvals16q1ReviewTests`).
- Una decisión recordada nunca contesta una petición MCP, ni una respuesta a un MCP se recuerda (C3; `MCPRememberIsolationTests`).
- Un sí o un no hablado para una petición que la hoja no muestra pide clic y no se reporta como aplicado (C2; `SpokenAnswerFrontTests`).
- Tickets del navegador, bandas de 20d, allowlist del puente, request-id-once y presupuestos: código de main sin tocar; sus suites en verde.
- Ubicación solo ciudad, nunca en el log; `locationChannelOn` sigue cableado (Gate 3).
- UI no importa WebKit (Gate 3).
- Solo el reductor escribe la proyección (Gate 3).

## 7. Pendiente conocido

- ~~Con C2, si la voz pregunta por el permiso de un encargo mientras la hoja enseña otra petición, el sí admitido no resuelve nada y la voz no lo sabe.~~ Cerrado en la ronda 1: además un no hablado se perdía igual (el reductor lo descartaba y la voz lo daba por aplicado). Ahora la voz conoce el frente por `approvalFront` y devuelve `.needsClick` para los dos. Límite conocido: los efectos llegan a la voz en `Task` sin orden garantizado; un frente viejo solo puede hacer que la voz pida clic de más o que el reductor descarte, nunca que resuelva otra petición.
- `testTheCacheKeyCarriesVoiceSpeedAndInstructions` (MouthStyleAndMarksTests) falló una vez en una corrida completa y pasó sola y en los gates: intermitente, fuera de la lista conocida.
