# Inventario de flakes (2026-10-01)

Doc de trabajo. Estado de cada test inestable conocido, con su PR o su siguiente paso. Las líneas son de `main` en `10341d9`. Se actualiza al mergear cada PR de la lista.

Familias que se repiten:
- **Reloj**: una espera fija o un tope de reloj compite con el evento que se espera. Se arregla esperando el estado observable (`pumpUntil`, `TestGate`) o subiendo al tope común de 30 s.
- **Main actor**: un test bloquea el main actor de forma síncrona y los tests `@MainActor` que corren en paralelo se quedan sin turno.
- **Orden**: el test da por hecho un orden que Swift no promete (brief `tests-orden-no-prometido`).
- **Crash**: el proceso de tests muere sin resumen.

## Resueltos o con PR abierto

| Test | Archivo | Familia | Estado | PR |
|---|---|---|---|---|
| esperas de auto-deny MCP (4) | `Approvals16q1Tests.swift`, `Approvals16q1ReviewTests.swift` | reloj (tope de 5 s) | mergeado | #74 |
| 17 esperas de reconexión | `VoiceReconnectTests.swift` | reloj (5 s y 2 s) | abierto | #76 |
| `mentionSelectorTabDuringDialogTests`, `mentionSelectorPermissionRacesTests` | `Mention16m7SelectorTests.swift:269` y `:342` | orden | abierto | #77 |
| `testTheCapRefusesInsteadOfPilingUp` | `ProcessRegistryTests.swift:26` | reloj (`settle(0.08)`); el fix también saca su limpieza del main actor | abierto | #85 |
| `testTerminateAllKillsWhatIsLeft` | `ProcessRegistryTests.swift:73` | main actor (unos 255 ms medidos) | abierto | #86 |
| `diagramSchedulerCancellationTests` | `Diagram16m5bRound2Tests.swift:127` | orden (la cancelación se registra en un turno posterior) | abierto; tumbó el CI de #60, #73 y #77 | #89 |
| `testTheWaitDoesNotBlockTheCaller` | `ProcessGroupTests.swift:75` | reloj (umbral de 0.75 s) | abierto, con paso de CI en pool estricto | #94 |

No son flakes pero salen del mismo trabajo:
- #82 y #96: gates de capas, que detectan `.swift` sueltos o que ningún target compila.
- #97: el reporte de Gate 4 y TSan cuando el proceso de tests muere sin resumen.

## Abiertos

| Test | Archivo | Familia | Evidencia | Siguiente paso |
|---|---|---|---|---|
| **Prioridad alta.** `NativeExecutorTests`: `nativeExecutorRoundTests`, `iterationLimitPreventsInfiniteLoop`, `riskyToolEmitsApprovalEvent`, `nativeExecutorAcceptsApprovalsDependency` | `NativeExecutorTests.swift:455` (fallo en `:698`), `:146`, `:65`, `:39` | reloj probable (tope de 5 s de `runAsync`, que espera ocupando el main actor) para los `CancellationError` de `:39`, `:65` y `:146`; `:698` sin clasificar | Tres apariciones el 2026-10-01, en ramas que no tocan el ejecutor: TSan de #91 en `:698` (got `[]`, want `["run_shell"]`); gates locales de #99 (`nativeExecutorAcceptsApprovalsDependency`, `nativeExecutorRoundTests`); gates locales de #100 (`iterationLimitPreventsInfiniteLoop`, `riskyToolEmitsApprovalEvent`, `CancellationError`). Antes: inventario bajo carga, 10 fallos. `runAsync` lanza `CancellationError` cuando vence su espera (`TestKit.swift:82`), pero el mismo error también puede venir del cuerpo del test | Brief quick antes de tocar código: confirmar que el error sale de `TestKit.swift:82` y no del cuerpo; después, si basta con pasar los tres que usan `runAsync` a `async` con `pumpUntil`/`TestGate`, y qué hace que `:698` vea la lista vacía |
| `bridgeListenerTests` (proceso muerto) | `BridgeListenerTests.swift:12` | crash | CI 36903280273 (#85): el log termina en "started", sin resumen; en local, 5/5 verde suelto y la suite completa en serie verde | Con #97 el próximo caso dirá la señal. Si se repite, subir `DiagnosticReports` como artifact, en un PR propio (toca CI, escala) |
| `bridgeConnectionScopeTests`, `approvals16q1Tests` (proceso muerto) | `BridgeConnectionScopeTests.swift:82`, `Approvals16q1Tests.swift:19` | crash | CI 36668333244 y 36728272208, con el mismo patrón | Igual que la fila anterior |
| `diagramPageFailureTests` | `Diagram16m5bRound2Tests.swift:462` | reloj | `weakView == nil` tras un sleep fijo de 1 s; QA lo marcó MEDIUM en #89 | Brief `diagram-page-liberacion` aprobado; fix con `pumpUntil` listo en `test/flake-diagram-page-release`, PR cuando drene la cola de CI |
| `aDrainRacingTheNextTurnThreadsTheCutReplyOnceAndFirst` | `VoiceReconnectTests.swift:696` | orden | Gates locales de #97, pasada 1: llegó `["go", reply]` en vez de `[reply, "go"]` | Brief `drain-racing-orden-del-corte` aprobado: ventana de reentrada en `threadCutReply`, confirmada por un RED determinista con el fake retenido; en la app, con el presentador `@MainActor`, puede no manifestarse; fix listo en `fix/drain-racing-orden-corte`, PR cuando drene la cola de CI |
| `mcpToolsTests` → `testQueuedMCPRequestsAnswerInOrder` | `MCPToolsTests.swift:182` y `:183` | orden | CI 36906986048 (#81, un PR sin código Swift: workflows y docs): got `["req10","req9"]` y `[false,true]`; los dos veredictos llegaron invertidos | Brief quick; sin código hasta que Karen firme |
| `aDropBetweenTheFinalTranscriptAndResponseDoneIsNotACut` | `VoiceReconnectTests.swift:594` | sin clasificar | Inventario bajo carga, 5 fallos | #76 no lo toca |
| `aUserTurnBeatingTheDrainRaisesNoNoticeButKeepsTheOrder`, `aDropWithNothingSaidRaisesNoNotice` | `VoiceReconnectTests.swift:957` y `:850` | sin clasificar | Inventario bajo carga, 6 y 1 fallos | #76 cambia esperas cerca; ver si sigue al mergear |
| `earReviewTests` | `EarReviewTests.swift:12` | main actor | RED con una sonda de 600 ms en el main; #86 quita un disparador plausible de 255 ms (no se reprodujo el flake en su base: 0/10 antes y después) | Rama `test/flake-ear-review`, en pausa hasta que entre #77; señal de apertura `h.mic.startCount >= 2` |
| `aHelloInsideTheDeadlineIsNotClosedLater` | `BrowserChannelTests.swift:163` | reloj | Inventario bajo carga, 26 fallos; también cayó en un gates con load 50 | Pendiente de asignar |
| `dm1cGateTimesOutWithinBudgetWhenTheProviderIsSlow` | `DecisionGateTests.swift:210` | reloj | Inventario bajo carga, 20 fallos | Pendiente de asignar |
| `diagramSchedulerTimeoutTests` | `Diagram16m5bRound2Tests.swift:163` | reloj | Gates con load 50: "sin esperar al trabajo colgado" (tope de 8 s) | Pendiente de asignar |
| Resto del inventario bajo carga | `MouthStyleAndMarksTests:73` (3), `VoiceSessionAttachmentTests:9` (2), `MouthLanguageTests:17` (2), `BrowserHostRelayHardeningTests:52` (2), `VoiceReconnectTests:484` (1), `ConversationQualityIslandTests:240` (1) | sin clasificar | Un fallo o pocos | Observar |
| `ProcessGroupTests` en `:67` | `ProcessGroupTests.swift:67` | reloj (teórico) | No se reproduce (0/5 congelando la shell) | Riesgo anotado, sin cambio |

Los conteos "bajo carga" salen de corridas del suite con CPU cargada por otros builds, no de fallos de CI. Miden qué tests son sensibles a carga, no con qué frecuencia fallan en CI.

## Known issues (no son flakes)

| Test | Archivo | Por qué está marcado |
|---|---|---|
| `decisionDatasetTests`, mínimos del conjunto | `DecisionDatasetTests.swift:291` | `withKnownIssue` hasta que Karen reclasifique las órdenes reales (DM0). Hoy: 2% real (4/171) |
| `repoRootRecordsAnIssueWhenNothingIsFound` | `ConformanceTests.swift:169` | `withKnownIssue` a propósito: prueba que `repoRoot` registra un issue cuando no encuentra el repo |
