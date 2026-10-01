# Touch ID en cada aprobacion critica

**Estado: APROBADO** (Karen, 2026-10-01; respuestas registradas al inicio).
Research: `docs/research/self-qa-clic-fuera-de-banda.md`, APROBADO 2026-10-01, decision D3. D4 y D7 tambien estan firmadas. Ese brief va en la rama de cada PR, porque el research-gate lo exige.

Decisiones de Karen (2026-10-01):
- "si, tiene touch id. no uso control por voz para eso, quiero que companion me pida touch id"
- "touch id en cada approve critico"

Respuestas de Karen a la seccion 7 (2026-10-01):
- **Q1:** "no, no se pueden recordar, siempre debe pedir auth". Se aplica el default: un "si" recordado nunca evita la prueba y la hoja no ofrece "Recordar" en lo critico.
- **Q2:** "perfecto". Frase fija sin datos del payload.
- **Q3:** "pide auth con boton sobre el notch como fallback". Esto reemplaza el default: el control es **fail-closed**. Si el puerto falta, o el dialogo del sistema no se pudo mostrar o se cerro, la peticion critica no se aprueba. La tarjeta de aprobacion de la isla muestra un boton "Verificar" que vuelve a pedir la prueba (Touch ID o contrasena). Ver A3b y A10b.

## 1. Objetivo

Cada vez que se aprueba una peticion de banda **critica**, Companion pide la prueba de dueña del sistema antes de que la peticion se resuelva. La prueba es `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`: Touch ID, con la contraseña como alternativa. Da igual por donde llegue el "si":
- un clic en la hoja de la ventana principal;
- un clic en la isla;
- un `AXPress` o un `CGEvent` que ningun humano hizo;
- un "si" hablado.

Si la prueba falla, se cancela o no esta disponible, no se aprueba nada. La hoja sigue abierta y corre su plazo de 60 s. Negar nunca pide Touch ID (D4).

**Que cuenta como critico.** No se inventa ninguna clasificacion: se reusa `ActionBand.classify` (`ActionBand.swift:57-80`). En la hoja ya no hay hechos verificados, asi que se juzga con los hechos que **suben** la banda. Resultado:

| Banda en la hoja | Que entra |
|---|---|
| `.critical` | `run_shell`, `bridge_session`, `write_file`, `edit_file`, `create_document`, `sheet_write`, manos (`click`, `type_text`, `menu`...), toda peticion `isMCP`, toda tool sin clasificar (incluidas las de Claude Code: `Bash`, `Write`...) |
| `.confirm` | `open_url` a un host que la usuaria no dijo, `app:*` |
| `.act` | lecturas (`look`, `see`, `read_focused`, `list_apps`, `read_skill`, `find_places`...) |

### Criterios de aceptacion

Cada criterio tiene su test o su evidencia.

- **A1. Clasificador en la hoja.** `ActionBand.atSheet(_:)` devuelve exactamente la tabla de arriba.
  - Un `isMCP` es `.critical` aunque su nombre sea `look`, porque el nombre lo pone un servidor remoto (`ApprovalMemory.swift:32-35`).
  - Un nombre desconocido es `.critical`.
- **A2. Clic en Permitir sobre una peticion critica.**
  - El reductor no emite `.resolveApproval` y la peticion sigue en `approvalQueue`.
  - Emite `.verifyOwner(requestId:)`.
  - Solo despues de `.ownerVerified(requestId:, confirmed: true)` emite `.resolveApproval(approved: true, remember: false)`.
- **A3. Falla, cancela o no disponible.** `.ownerVerified(confirmed: false)` no resuelve nada, la hoja sigue y el plazo de `ApprovalTiming.autoDeny` niega igual.
- **A3b. Reintento desde la isla (Q3).** Despues de un `.ownerVerified(confirmed: false)`, la tarjeta de aprobacion de la isla muestra "Verificar". Tocarlo emite `.verifyOwner(requestId:)` otra vez, con las mismas reglas de A6. No hay ningun camino que apruebe sin `.ownerVerified(confirmed: true)`.
- **A4. Negar nunca pide Touch ID.** "No permitir", Escape, un "no" hablado y el freno resuelven como hoy, sin `.verifyOwner`, desde cualquier canal.
- **A5. Voz.**
  - Un `.approvalSpoken(id, true)` sobre una peticion critica emite `.verifyOwner` y no `.resolveApproval`.
  - Un "si" hablado sobre una lectura de riesgo bajo resuelve como hoy, sin Touch ID.
  - Invariante con test: ninguna tool de `ApprovalRisk.low` es `.critical` en la hoja.
- **A6. Ligado al `requestId`.**
  - Una verificacion de X nunca aprueba Y.
  - Una verificacion que llega cuando X ya salio de la cola (negada, plazo vencido, freno) no aprueba nada.
  - Un segundo clic, o un "si", mientras X se verifica no abre un segundo dialogo.
- **A7. Lo no critico no cambia.** `open_url` a un host no dicho, `app:*` y las lecturas se resuelven como hoy, sin `.verifyOwner`.
- **A8. Recordar (depende de Q1).**
  - Un "si" recordado nunca evita la hoja de una peticion critica.
  - La hoja no ofrece "Recordar" en una peticion critica.
- **A9. Cancelacion.** Si la peticion sale de la hoja mientras se verifica, la tarea de verificacion se cancela y el adaptador llama `LAContext.invalidate()`. Se prueba con un fake que registra la cancelacion.
- **A10. Cableado.**
  - La raiz de composicion inyecta el adaptador real; lo prueba un test que lee el codigo fuente.
  - Ningun camino de Sources resuelve un `approved: true` fuera de `SessionModel` → `Approvals`/`JobRunner`.
- **A10b. Fail-closed (Q3).** Sin puerto, `SessionMachine` igual exige la prueba en lo critico, y `.verifyOwner` contesta `.ownerVerified(confirmed: false)`. Los tests que construyen `SessionModel` sin puerto y aprueban algo critico se migran en un PR propio de solo tests (PR-2b), antes del PR-2.
- **A11. Evidencia en vivo de Karen** (app release):
  - `run_shell` o `bridge_session`: clic, Touch ID, corre.
  - Cancelar Touch ID: la hoja sigue y a los 60 s se niega.
  - `osascript` con `AXPress` sobre "Permitir": aparece Touch ID y nada corre sin dedo ni contraseña.
  - `open_url` a un host no dicho: sin Touch ID.
- **Gates:**
  - `scripts/gates.sh` en verde en cada PR;
  - `swift test --sanitize=thread --filter OwnerCheck` sin avisos;
  - code-reviewer, qa-reviewer y security-reviewer, que revisa como frontera de confianza.

## 2. Estado actual (verificado)

**Bandas y riesgo**
- `ActionBand` tiene tres casos: `act`, `confirm` y `critical` (`Sources/CompanionCore/Tools/ActionBand.swift:6-10`).
- `classify` es una allowlist:
  - lo no clasificado es `.critical` (`:55-56`, `:78`);
  - las manos solo suben a `.critical` con `destructiveTarget` o `inTerminal` (`:62`).
- `ActionFacts` tiene valores por defecto que "suben la banda" (`:12-41`). Sin embargo, `destructiveTarget` e `inTerminal` valen `false` por defecto, asi que con los valores por defecto una mano sale `.act`.
- La banda **solo** se usa para saltarse la hoja (`== .act`):
  - `NativeExecutor.swift:158`;
  - `ParentToolRunner+Deliverables.swift:46,49,110`;
  - `NativeToolRunner+Band.swift:12-35`.

  Una vez en la hoja, la peticion no lleva su banda: `ApprovalRequest` no tiene ese campo (`Sources/CompanionCore/Delegation/AgentStreamCodec.swift:3-23`).
- La spec 20d dice que la banda critica es "siempre hoja + ticket ... nunca por voz, grant, confianza ni plan" (`docs/specs/wave-20d-modos-autorizacion.md:24`), y pone `bridge_session` y `run_shell` en critica (`:40`). Hoy eso se cumple solo porque `ApprovalRisk.low` es un subconjunto de las lecturas; no hay un control explicito.
- `ApprovalRisk.lowTools` son solo lecturas (`ApprovalRisk.swift:13-23`), y todas estan en `ActionBand.reads` (`ActionBand.swift:44-47`).

**El "si" hablado**
- Exige `ApprovalRisk.low` y `!isMCP` (`VoiceSession+Approvals.swift:222`), mas `SpokenYes.admits` (`Acknowledgement.swift:57-63`).
- En realtime nunca aprueba (`VoiceSession+Approvals.swift:169-173`, `Acknowledgement.swift:60`).
- Termina en `.approvalSpoken` (`VoiceSession+Approvals.swift:205`), que el reductor convierte en `.approvalAnswered` (`SessionMachine.swift:124-129`).

**El unico punto por donde pasa todo "Permitir"**
- La ventana principal (`CompanionRootView.swift:278`) y la isla (`IslandView+Status.swift:99`) llaman a `ChatViewModel.answerApproval` (`ChatViewModel+Jobs.swift:142`), que manda `.approvalAnswered` al reductor (`:145-146`).
- El reductor saca la peticion y emite `.resolveApproval` (`SessionMachine.swift:113-123`).
- `SessionModel.perform` la ejecuta contra `Approvals` o `JobRunner` (`SessionModel.swift:108-117`). `JobRunner.resolveApproval` tambien termina en `approvals.resolve` (`JobRunner.swift:106-107`).
- Hay un solo actor `Approvals` en la app (`CompanionMainProviders.swift:93`), compartido por los jobs, la voz y el puente (`CompanionMain.swift:142`, `CompanionMainSensing.swift:140,218`, `CompanionMainVoice.swift:136`).
- Las demas llamadas a `resolve` con `approved` literal en Sources son `false`:
  - `Approvals.swift:60`;
  - `ParentToolGuard.swift:119`;
  - `SessionMachine.swift:134`;
  - `SessionMachine+Jobs.swift:124,179`;
  - `SessionMachine+Brakes.swift:71`.

  Comprobado con grep.
- `handle` emite `.approvalClosed` por cada peticion que sale de la cola, por cualquier camino (`SessionMachine.swift:57-61`). Ese es el gancho para cancelar el dialogo.
- `Approvals.resolveNow` no hace nada si la entrada ya no existe (`Approvals.swift:75`), y el plazo la saca (`:92-96`). Es la segunda cerradura contra una verificacion tardia.
- `SessionMachine` se construye con `init()` (`SessionMachine.swift:52`) y `SessionModel` con `init(jobs:approvals:voice:sleep:log:)` (`SessionModel.swift:38-52`). La app lo arma en `CompanionMainSensing.swift:139-140`, y `ChatViewModel` crea uno por defecto si no le pasan ninguno (`ChatViewModel.swift:152`).
- El hilo escribe "Aprobado" y el toast **antes** de saber si se resolvio (`ChatViewModel+Jobs.swift:147-150`).

**Recordar**
- `ApprovalKey.from` da clave a `run_shell`, `sheet_write`, `create_document`, `write_file`, `edit_file` y `open_url` (`ApprovalMemory.swift:37-84`). No da clave a `bridge_session` ni a MCP (`:35`, `:85-94`).
- Un "si" recordado salta la hoja:
  - en `ParentToolGuard.answer` (`ParentToolGuard.swift:101-104`);
  - en `NativeExecutor` (`NativeExecutor.swift:186-188`);
  - y la memoria vive en `Approvals.remembered` (`Approvals.swift:87-90`).
- La hoja muestra el toggle segun `ApprovalDisplay.showsRemember` (`ApprovalSheet.swift:72`), que vale `true` en `run_shell`, `write_file` y `sheet_write`, entre otros (`ApprovalCopy.swift:201,208,217`).

**Patrones que se reusan**
- Puerto en Core con adaptador en Services: `AccessibilityChecking` (`Sources/CompanionCore/Perception/Permissions.swift:5-9`). Los puertos de aprobacion viven en `Sources/CompanionCore/Approvals/ApprovalPorts.swift:31-39`.
- Los fakes compartidos viven en `Tests/CompanionCoreTestSupport/`, como regular target con API `package` (`docs/ARCHITECTURE.md:113-125`).
- Caja `@unchecked Sendable` para un objeto de framework no Sendable, por ejemplo `ScreenSight.swift:284`.
- `ToolArguments.parse` (`Sources/CompanionCore/Tools/ToolArguments.swift:9`).

**Plataforma**
- Ningun archivo importa LocalAuthentication; Services solo usa `Security` (`KeychainBackend.swift:2`).
- `gates.sh` prohibe ciertos imports en Core (`scripts/gates.sh:116`) y en Services solo prohibe SwiftUI (`:118`). LocalAuthentication en Services pasa el gate. En Core no va, por la regla "no Apple frameworks beyond Foundation" (`docs/ARCHITECTURE.md:12-13`).
- `bundle.sh` genera el Info.plist (`scripts/bundle.sh:71-101`) y firma sin entitlements ni hardened runtime (`:107-118`).
- La plataforma minima es macOS 26 (`Package.swift:9`).

## 3. Archivos y API por capa

### Core (puro)

`Sources/CompanionCore/Tools/ActionBand.swift`:
- `ActionFacts.unverified` (static): todos los hechos en la direccion que sube la banda.
  - `pathExists: true`, `inWorkZone: false`, `rangeHasValues: nil`;
  - `hostSaid: false`, `destructiveTarget: true`, `inTerminal: true`.
- `ActionBand.atSheet(_ request: ApprovalRequest) -> ActionBand`:
  - si `request.isMCP`, devuelve `.critical`;
  - si no, devuelve `classify(toolName:arguments: ToolArguments.parse(inputJSON) ?? [:], facts: .unverified)`.

`Sources/CompanionCore/Session/SessionTypes.swift`:
- Evento nuevo `SessionEvent.ownerVerified(requestId: String, confirmed: Bool)`.
- Efecto nuevo `SessionEffect.verifyOwner(requestId: String)`.

`Sources/CompanionCore/Session/SessionMachine.swift`:
- Sin parametro nuevo: la maquina siempre exige la prueba en lo critico (Q3, fail-closed).
- Estado privado `verifying: String?`.
- En `.approvalAnswered(id, true, _)`, si `ownerCheck` y `atSheet == .critical`:
  - si `verifying == id`, devuelve `[]`;
  - si no, `verifying = id`, la peticion **no** se saca y devuelve `[.verifyOwner(requestId: id)]`.
- `.ownerVerified(id, confirmed)`:
  - limpia `verifying`;
  - si `confirmed` y la peticion sigue en la cola, corre el camino actual de aprobar, con `remember: false`;
  - si no, devuelve `[]`.
- Un `.approvalAnswered(id, false, _)` mientras se verifica niega como hoy y limpia `verifying`.
- El archivo pasa de unas 379 a unas 410 lineas. `gates.sh:57-58` solo avisa por encima de 400. Si el revisor lo pide, la logica sale a `SessionMachine+OwnerCheck.swift` en un PR aparte.

`Sources/CompanionCore/Approvals/ApprovalPorts.swift`:
- `package enum OwnerCheck: Sendable, Equatable { case confirmed, refused, unavailable }`.
- `package protocol OwnerVerifying: Sendable { func verify(reason: String) async -> OwnerCheck }`.
  - Contrato: cancelar la tarea que llama cierra el dialogo.
  - Si ni Touch ID ni contraseña estan disponibles, devuelve `unavailable`; nunca `confirmed`.

`Sources/CompanionCore/Approvals/ApprovalCopy.swift` (PR-5, depende de Q1):
- `display(for:)` pone `showsRemember = false` cuando `ActionBand.atSheet(request) == .critical`.
- `ApprovalCopy.ownerReason(_ language: AppLanguage) -> String` es una frase fija; su texto depende de Q2.

No se usa `Presence` en ningun nombre: ya existe `BrowserPresence` (`BrowserChannel.swift:7`), con otro significado.

### Services

`Sources/CompanionServices/Approvals/LocalAuthOwnerCheck.swift` (nuevo):
- `package struct LocalAuthOwnerCheck: OwnerVerifying`.
- Crea un `LAContext` nuevo en cada llamada, para que nunca se reuse una prueba anterior. `touchIDAuthenticationAllowableReuseDuration` se queda en su valor por defecto.
- `canEvaluatePolicy(.deviceOwnerAuthentication)` en falso devuelve `.unavailable` y registra el codigo `LAError` en el log.
- Llama `evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)` dentro de `withTaskCancellationHandler`; el `onCancel` llama `context.invalidate()` a traves de una caja `@unchecked Sendable`.
- Mapeo puro y testeable, `static func check(for code: LAError.Code) -> OwnerCheck`:
  - `userCancel`, `systemCancel`, `appCancel`, `authenticationFailed` y `userFallback` dan `.refused`;
  - el resto da `.unavailable`.
- Sin `try?`: el error se registra.

`Sources/CompanionServices/Approvals/Approvals.swift` (PR-5, depende de Q1):
- `remembered(_:)` devuelve `nil` en lugar de `true` cuando `ActionBand.atSheet(approval) == .critical`. Un "no" recordado sigue valiendo.
- `resolveNow` no guarda `remember` de una peticion critica.

### UI

`Sources/CompanionUI/Voice/SessionModel.swift`:
- `init(..., ownerCheck: (any OwnerVerifying)? = nil)`; construye `SessionMachine(ownerCheck: ownerCheck != nil)`.
- `.verifyOwner(id)`: guarda `verification = (id, Task { ... })`. La tarea llama `ownerCheck.verify(reason: ApprovalCopy.ownerReason(Localized.language()))` y, ya en `MainActor`, hace `send(.ownerVerified(requestId: id, confirmed: result == .confirmed))`. Registra en el log `requestId` y el resultado, nunca los argumentos.
- `.approvalClosed(id)`: si `verification?.id == id`, cancela la tarea.
- Sin puerto, `.verifyOwner` contesta `.ownerVerified(confirmed: false)` (Q3, fail-closed); la isla ofrece "Verificar" (A3b).

`Sources/CompanionUI/Chat/ChatViewModel+Jobs.swift`:
- `answerApproval` escribe "Aprobado" y el toast solo si los efectos traen `.resolveApproval`.
- Si traen `.verifyOwner`, no escribe nada. La hoja sigue a la vista y el dialogo del sistema es el aviso.

`ApprovalSheet.swift`, `CompanionRootView.swift` y la isla no cambian.

### App

`Sources/CompanionApp/CompanionMainSensing.swift:139-140`: pasa `ownerCheck: LocalAuthOwnerCheck()` a `SessionModel`.

### Docs

`docs/ARCHITECTURE.md`: seccion "Security" nueva con el riesgo residual de D7. Un proceso con Accesibilidad que conoce la contraseña, o que tiene a la usuaria tocando Touch ID por otra razon, sigue pudiendo aprobar.

### Entitlements e Info.plist

- **Sin cambios esperados.** En macOS, LocalAuthentication no pide entitlement a una app sin sandbox ni clave de uso en el Info.plist. `NSFaceIDUsageDescription` es de Face ID en iOS.
- **Sin verificar en vivo:** se confirma en A11.
- Si hiciera falta una clave, el cambio va en `scripts/bundle.sh:71-101`. No es config raiz, pero cambia el bundle instalado y tiene un test que lo compara con `ProductIdentity` (`bundle.sh:18-19`), asi que lo aprueba Karen aparte.
- Ningun PR toca `Package.swift` ni agrega dependencias: LocalAuthentication es un framework del sistema.

## 4. Plan TDD (primero RED)

Rutas despues de #71: el target `CompanionTests` ya no existe en main.

**Core:** `Tests/CompanionCoreTests/ActionBandTests.swift` (existe; se agregan casos)
- `atSheetRunShellAndBridgeSessionAreCritical`
- `atSheetHandsAreCriticalWithoutFacts`
- `atSheetWritesAreCriticalWithoutFacts`
- `atSheetUnsaidOpenURLAndAppToolsAreConfirm`
- `atSheetReadsAreAct`
- `atSheetMCPIsCriticalWhateverItsName`
- `atSheetUnknownAndClaudeCodeNamesAreCritical`
- `lowRiskToolsAreNeverCriticalAtSheet` (invariante A5)

**Core:** `Tests/CompanionCoreTests/SessionOwnerGateTests.swift` (nuevo)
- `criticalAllowEmitsVerifyOwnerAndKeepsRequest`
- `confirmedVerificationResolvesApprovedWithoutRemember`
- `refusedVerificationResolvesNothingAndSheetStays`
- `verificationForAnotherIdApprovesNothing`
- `lateVerificationAfterDenyApprovesNothing`
- `lateVerificationAfterDropApprovesNothing`
- `secondAllowWhileVerifyingIsIgnored`
- `denyWhileVerifyingDeniesAndClosesRequest`
- `spokenYesOnCriticalGoesThroughOwnerCheck`
- `spokenYesOnLowRiskResolvesWithoutOwnerCheck`
- `nonCriticalAllowIsUnchanged`
- `criticalNeverResolvesWithoutConfirmedVerification`

**Soporte:** `Tests/CompanionCoreTestSupport/OwnerCheckFakes.swift` (nuevo)
- `FakeOwnerCheck`, con resultado programable, contador de llamadas y registro de cancelacion.

**Services:** `Tests/CompanionServicesTests/LocalAuthOwnerCheckTests.swift` (nuevo)
- `cancelCodesMapToRefused`
- `unavailableCodesMapToUnavailable`
- `everyKnownCodeMapsToNonConfirmed`

El dialogo real no se puede afirmar desde la suite: no hay Touch ID en CI (brief §8).

**Services:** `Tests/CompanionServicesTests/ApprovalsTests.swift` (existe; PR-5)
- `rememberedYesNeverAnswersCriticalRequest`
- `rememberedNoStillAnswersCriticalRequest`
- `criticalResolveDoesNotStoreRemember`

**Core:** `Tests/CompanionCoreTests/ApprovalCopyTests.swift` (existe; PR-5)
- `criticalRequestsNeverOfferRemember`
- `ownerReasonIsFixedInBothLanguages`

**UI:** `Tests/CompanionUITests/SessionModelOwnerCheckTests.swift` (nuevo)
- `verifyOwnerCallsPortAndFeedsResultBack`
- `requestLeavingSheetCancelsVerification`
- `noPortRefusesCriticalAndOffersRetry`
- `answerApprovalWritesNoApprovedLineWhileVerifying`

**Integration:** `Tests/CompanionIntegrationTests/OwnerCheckWiringTests.swift` (nuevo)
- `criticalJobApprovalWaitsForOwnerThenResolves`: `Approvals` real, `SessionModel`, `FakeOwnerCheck`, `run_shell`.
- `refusedOwnerLeavesApprovalsPendingUntilDeadline`: con `MockClock` y timeout corto.
- `compositionRootWiresLocalAuthOwnerCheck`: lee el codigo de `CompanionMainSensing.swift`.
- `noOtherSourceResolvesApprovalWithTrue`: lee Sources. Solo admite `approved: false` literal, o el reenvio de `SessionModel.swift` y `JobRunner.swift`.

Antes de escribir cada test se confirma en main en que target vive hoy el archivo que se extiende (`git ls-tree origin/main Tests/`).

**Deben seguir en verde sin editarse:**
- `ApprovalSheetTests`, incluido el test de "Permitir sin atajo";
- `NativeActionBandTests`, `SpokenYes16qTests`, `BridgeSessionTests` y `JobRunnerTests`.

**Excepcion:** en el PR-5 cambian a proposito los tests que hoy afirman `showsRemember: true`, o un "si" recordado que salta la hoja, sobre una tool critica. Esos tests se enumeran en el PR.

## 5. PRs (en orden)

Reglas para todos los PR:
- Comentarios solo con el POR QUE.
- Sin dependencias nuevas.
- Sin tocar configs raiz.
- `CHANGELOG.md` en `[Unreleased]`, en español y con fecha, en cada PR.
- El brief APROBADO va en cada rama.
- Cada PR se puede mergear solo. Ojo: con Q3 fail-closed, el PR-2 enciende la exigencia en la maquina; por eso PR-3 (puerto) y PR-4 (cableado en UI) van inmediatamente despues, y PR-6 se adelanta si hace falta para no dejar main sin poder aprobar lo critico.

| PR | Archivos | Depende de |
|---|---|---|
| PR-1 Critico en la hoja | `ActionBand.swift`, `ActionBandTests.swift`, CHANGELOG (3) | nada |
| PR-2b Migrar tests | los tests que construyen `SessionModel` y aprueban algo critico pasan a un `FakeOwnerCheck` que confirma (solo tests; puede pasar de 5 archivos por ser mecanico, se divide si el revisor lo pide) | PR-3 |
| PR-2 Reductor | `SessionTypes.swift`, `SessionMachine.swift`, `SessionModel.swift` (solo el case nuevo, fail-closed), `SessionOwnerGateTests.swift`, CHANGELOG (5) | PR-1, PR-2b |
| PR-3 Puerto y adaptador | `ApprovalPorts.swift`, `LocalAuthOwnerCheck.swift`, `OwnerCheckFakes.swift`, `LocalAuthOwnerCheckTests.swift`, CHANGELOG (5) | nada |
| PR-4 Cableado en UI | `SessionModel.swift`, `ChatViewModel+Jobs.swift`, `SessionModelOwnerCheckTests.swift`, CHANGELOG (4) | PR-2, PR-3 |
| PR-5 Recordar (Q1) | `Approvals.swift`, `ApprovalCopy.swift`, `ApprovalsTests.swift`, `ApprovalCopyTests.swift`, CHANGELOG (5) | PR-1 |
| PR-6 Encendido | `CompanionMainSensing.swift`, `OwnerCheckWiringTests.swift`, `docs/ARCHITECTURE.md` (D7), CHANGELOG (4) | PR-4 y PR-5. El PR-5 va antes para que un "si" recordado no evite Touch ID el dia del encendido. |

Fuera de alcance:
- D1 y D2: el clasificador de origen por pid y el experimento de la seccion 9 del brief;
- cualquier cambio en `ApprovalSheet` o en `ApprovalClickGuard`;
- grants y destinos de confianza (20d D/E).

## 6. Riesgos y mitigaciones

- **Friccion.** `bridge_session` pide Touch ID en cada conexion (brief §6) y cada permiso de Claude Code tambien, porque sus nombres caen en `.critical`. Es lo que dice el clasificador vigente y lo que Karen pidio; si molesta en vivo, se reabre con evidencia.
- **Puerto sin inyectar.** Con Q3 fail-closed, olvidar el puerto bloquea lo critico en vez de abrirlo; lo cubren el test de cableado y A11.
- **Verificacion tardia.** Hay dos cerraduras: el reductor exige la peticion en la cola, y `Approvals.resolveNow` exige la entrada pendiente (`Approvals.swift:75`).
- **Dialogo huerfano.** Se cierra con `.approvalClosed` → cancelacion de la tarea → `invalidate()`.
- **Hilo del dialogo.** La respuesta llega en una cola del framework (brief §8). Vuelve a `MainActor` porque la tarea vive en `SessionModel`, y el resultado viaja como evento.
- **Ack hablado prematuro.** Hoy no puede pasar (A5, invariante). Si alguien sube una tool critica a `ApprovalRisk.low`, el control sigue pidiendo Touch ID, pero la voz diria "aprobado" antes de tiempo. El test de invariante lo detecta.
- **Residuo aceptado (D7).** Un atacante con la contraseña, o con la usuaria tocando Touch ID por otra razon.

## 7. Preguntas abiertas y puntos sin verificar

**Preguntas para Karen**
- **Q1 (bloquea el PR-5 y el PR-6).** Recordar en lo critico.
  - **Default:** un "si" recordado nunca evita Touch ID y la hoja no ofrece "Recordar" en lo critico.
  - **Alternativa:** dejarlo, pero entonces la aprobacion no es "en cada approve".
- **Q2.** Texto de `localizedReason`.
  - **Default:** una frase fija, sin datos del payload; por ejemplo "aprobar una accion critica" / "approve a critical action".
  - **Alternativa:** sumar el sujeto de la hoja, que ya va limitado a 80 caracteres.
- **Q3.** Puerto ausente.
  - **Default:** puerto ausente = control apagado, mas el test de cableado. Asi ningun test existente cambia.
  - **Alternativa:** fail-closed. Obliga a migrar los tests que construyen `SessionModel`, unos 17 archivos con 41 llamadas (grep), y exige su propio PR de solo tests.

**Sin verificar**
- Que la variante `async throws` de `evaluatePolicy(_:localizedReason:)` este en el SDK de macOS 26 tal como se usa. Se confirma al compilar el PR-3.
- Si `LAContext` es `Sendable` en el SDK actual y si `invalidate()` es seguro desde otro hilo. La caja con lock lo cubre de todos modos.
- Que el dialogo no se pueda aprobar con un `AXPress` de otro proceso (brief §9). Con Touch ID o contraseña, lo unico que un `AXPress` podria hacer es cancelar. Se prueba en A11.
- La redaccion exacta con que macOS muestra la razon (prefijo del sistema mas el nombre de la app).
- No se rastreo por que camino se limpia la cola en cada auto-negacion (jobs, MCP, puente). El diseño no depende de eso gracias a las dos cerraduras.
