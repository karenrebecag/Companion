# Inventario de flakes (2026-10-01, actualizado 2026-10-02)

Doc de trabajo. Estado de cada test inestable conocido, con su PR o su siguiente paso. Las líneas son de `main` en `10341d9`, salvo las filas tocadas el 2026-10-02, que citan `main` en `2ba053c`. Se actualiza al mergear cada PR de la lista.

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
| `NativeExecutorTests`: `nativeExecutorRoundTests`, `iterationLimitPreventsInfiniteLoop`, `riskyToolEmitsApprovalEvent`, `nativeExecutorAcceptsApprovalsDependency` | `NativeExecutorTests.swift` | reloj (tope de 5 s de `runAsync`) y orden (el colector de eventos leía antes de que su consumidor arrancara) | mergeado; la última caída vista (`riskyToolEmitsApprovalEvent`, gates de #106 el 2026-10-01) fue en una rama sin #105 | #105 |

No son flakes pero salen del mismo trabajo:
- #82 y #96: gates de capas, que detectan `.swift` sueltos o que ningún target compila.
- #97: el reporte de Gate 4 y TSan cuando el proceso de tests muere sin resumen.
- #103: ningún test borra el directorio temporal del usuario (`TMPDIR`); un escáner de fuentes lo vigila.

## Abiertos

| Test | Archivo | Familia | Evidencia | Siguiente paso |
|---|---|---|---|---|
| **Prioridad alta.** `dm1cGateTimesOutWithinBudgetWhenTheProviderIsSlow` | `DecisionGateTests.swift:210`; la aserción que cae es `:227` (`elapsed < 1`, presupuesto de 80 ms contra un proveedor que duerme 5 s) | reloj (umbral de pared de 1 s) | Inventario bajo carga, 20 fallos. El 2026-10-02 cayó en las cinco corridas completas de gates de #108, #109 y #110, con `elapsed` entre 1.5 y 5.3 s para un presupuesto de 80 ms; `uptime` marcó un load de 57 al terminar la última. Aislado pasa siempre (3/3 cada vez). Bajo el suite completo en esta Mac ya no es intermitente, sino casi determinista | Brief quick: medir qué espera el gate después del presupuesto (la cancelación del proveedor lento, el árbitro o el runner) antes de tocar el umbral |
| **Prioridad alta.** `aHelloInsideTheDeadlineIsNotClosedLater` | `BrowserChannelTests.swift:163`; la aserción que cae es `:169`, la premisa (`el hello llegó dentro del plazo de 1 s`) | reloj (la conexión y el hello tardan más de 1 s bajo carga) | Inventario bajo carga, 26 fallos; gates con load 50. El 2026-10-02 cayó en las mismas cinco corridas que `dm1c`, y el 2026-10-01 en la segunda corrida de gates de #106; aislado 3/3 | Brief quick: el plazo del test es la medida que se prueba, así que subirlo no basta; ver si la premisa puede medirse desde que el canal recibe el hello y no desde antes de conectar |
| `bridgeListenerTests` (proceso muerto) | `BridgeListenerTests.swift:12` | crash | CI 36903280273 (#85): el log termina en "started", sin resumen; en local, 5/5 verde suelto y la suite completa en serie verde | Con #97 el próximo caso dirá la señal. Si se repite, subir `DiagnosticReports` como artifact, en un PR propio (toca CI, escala) |
| `bridgeConnectionScopeTests`, `approvals16q1Tests` (proceso muerto) | `BridgeConnectionScopeTests.swift:82`, `Approvals16q1Tests.swift:19` | crash | CI 36668333244 y 36728272208, con el mismo patrón | Igual que la fila anterior |
| `diagramPageFailureTests` | `Diagram16m5bRound2Tests.swift:462` | reloj | `weakView == nil` tras un sleep fijo de 1 s; QA lo marcó MEDIUM en #89 | Brief `diagram-page-liberacion` aprobado; fix con `pumpUntil` listo en `test/flake-diagram-page-release`, PR cuando drene la cola de CI |
| `aDrainRacingTheNextTurnThreadsTheCutReplyOnceAndFirst` | `VoiceReconnectTests.swift:696` | orden | Gates locales de #97, pasada 1: llegó `["go", reply]` en vez de `[reply, "go"]` | Brief `drain-racing-orden-del-corte` aprobado: ventana de reentrada en `threadCutReply`, confirmada por un RED determinista con el fake retenido; en la app, con el presentador `@MainActor`, puede no manifestarse; fix listo en `fix/drain-racing-orden-corte`, PR cuando drene la cola de CI |
| `mcpToolsTests` → `testQueuedMCPRequestsAnswerInOrder` | `MCPToolsTests.swift:182` y `:183` | orden | CI 36906986048 (#81, un PR sin código Swift: workflows y docs): got `["req10","req9"]` y `[false,true]`; los dos veredictos llegaron invertidos | Brief quick; sin código hasta que Karen firme |
| `aDropBetweenTheFinalTranscriptAndResponseDoneIsNotACut` | `VoiceReconnectTests.swift:594` | sin clasificar | Inventario bajo carga, 5 fallos | #76 no lo toca |
| `aUserTurnBeatingTheDrainRaisesNoNoticeButKeepsTheOrder`, `aDropWithNothingSaidRaisesNoNotice` | `VoiceReconnectTests.swift:957` y `:850` | sin clasificar | Inventario bajo carga, 6 y 1 fallos | #76 cambia esperas cerca; ver si sigue al mergear |
| `earReviewTests` | `EarReviewTests.swift:12` | main actor (antes); la caída del 2026-10-02 no encaja del todo | RED con una sonda de 600 ms en el main; #86 quita un disparador plausible de 255 ms (no se reprodujo el flake en su base: 0/10 antes y después). El 2026-10-02 cayó en la segunda corrida de gates de #110 en `:43`, `"dictado A: la sesión ya es de B, no pega"`: el dictado A pegó texto después de que B tomara la sesión, no fue B el que dejó de escuchar; aislado 3/3 | Revisar la clasificación con esa aserción antes de retomar la rama `test/flake-ear-review` (en pausa hasta que entre #77; señal de apertura `h.mic.startCount >= 2`) |
| `aReplacedConnectionsBufferedHelloNeverAuthenticatesTheNewOne` | `BrowserChannelHardeningTests.swift:64`; cae en `:85` (`gate.waitUntilParked()`, "window: the actor is parked inside A's handshake") | reloj probable: `waitUntilParked` espera con un `DispatchSemaphore` y un tope propio de 3 s (`:52`) a que el actor entre en la comprobación del token | Segunda corrida de gates de #110, 2026-10-02; aislado 3/3 | Observar; si se repite, ver si 3 s alcanzan para que el actor llegue al token con la Mac cargada, o esperar el estado sin reloj |
| `fanOutTests` → `testHoldWithAKeyWarmsOnce` | `FanOutTests.swift:14`; cae en `:53` (`prewarmed.count`, got 0 want 1) | orden probable (`warmedConnections == 1` se ve antes de que `prewarmed` registre su llamada) | CI de #104, run 36943165970; el orquestador relanzó solo ese job | Leer el orden de `warmConnection` y `prewarm` en el fake antes de clasificarlo |
| `diagramSchedulerTimeoutTests` | `Diagram16m5bRound2Tests.swift:163` | reloj | Gates con load 50: "sin esperar al trabajo colgado" (tope de 8 s) | Pendiente de asignar |
| Resto del inventario bajo carga | `MouthStyleAndMarksTests:73` (3), `VoiceSessionAttachmentTests:9` (2), `MouthLanguageTests:17` (2), `BrowserHostRelayHardeningTests:52` (2), `VoiceReconnectTests:484` (1), `ConversationQualityIslandTests:240` (1) | sin clasificar | Un fallo o pocos | Observar |
| `ProcessGroupTests` en `:67` | `ProcessGroupTests.swift:67` | reloj (teórico) | No se reproduce (0/5 congelando la shell) | Riesgo anotado, sin cambio |

Los conteos "bajo carga" salen de corridas del suite con CPU cargada por otros builds, no de fallos de CI. Miden qué tests son sensibles a carga, no con qué frecuencia fallan en CI.

## Known issues (no son flakes)

| Test | Archivo | Por qué está marcado |
|---|---|---|
| `decisionDatasetTests`, mínimos del conjunto | `DecisionDatasetTests.swift:291` | `withKnownIssue` hasta que Karen reclasifique las órdenes reales (DM0). Hoy: 2% real (4/171) |
| `repoRootRecordsAnIssueWhenNothingIsFound` | `ConformanceTests.swift:169` | `withKnownIssue` a propósito: prueba que `repoRoot` registra un issue cuando no encuentra el repo |
