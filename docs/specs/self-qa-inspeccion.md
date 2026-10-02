# Autoinspeccion por el puente (`companion_*`)

**Estado: APROBADO** (Karen, 2026-10-01; respuestas registradas al inicio).
Research: `docs/research/self-qa-puente.md` (APROBADO 2026-10-01, D3 y R1-R7) y `docs/research/self-qa-inspeccion-datos.md` (APROBADO 2026-10-01, D1-D7). R8 sale de `docs/research/ajuste-en-la-isla.md:7` (APROBADO). Los tres briefs van en la rama de cada PR.

Respuestas de Karen (2026-10-01): Q1 "vamos con tu recomendacion": cero escrituras; cerrar Ajustes se descarta. Q2-Q6: "dale solucion a los pendientes", se aplican los defaults de la seccion 7.

## 1. Objetivo

Con "Prestar las manos a otros agentes" encendido y la sesion del puente aprobada en la hoja, un agente externo conectado por el MCP puede inspeccionar a Companion:
- estado de la sesion;
- isla pintada;
- pantalla actual;
- ajustes no secretos;
- hilo activo como metadatos;
- ultimas lineas del log principal.

Lo hace con una familia de tools `companion_*` de solo lectura. Funcionan aunque Companion este al frente. Las manos (`click`, `type_text`...) siguen rechazando a Companion con `self_in_front`.

**Lo que esta spec no hace, por escrito:**
- No hay escrituras: ni idioma (R8), ni abrir o cerrar Ajustes (ver Q1).
- El puente nunca pulsa ni teclea sobre Companion (D1 del puente, R1, R2, R4).
- Sin `look` ni `read_focused` sobre Companion (D2 del puente): exige relajar los cinco cierres y tiene su propia spec.
- Sin ids AX (D4), sin captura propia (D6) y sin `show_setting` (D8): cada uno con su brief o spec.
- No se expone la memoria ni la lista de hilos: ninguna prueba del plan las necesita (`self-qa-inspeccion-datos.md:29-38`). Si se agregan, D1 y D2 de ese brief aplican tal cual.
- Sin modo de contenido completo (D7 de inspeccion).

### Criterios de aceptacion

- **A1. Companion al frente.**
  - Con `hands.selfInFront() == true`, todas las `companion_*` responden `ok:true` por el puente.
  - `click`, `menu`, `scroll`, `type_text`, `press_key`, `focus_window`, `look` y `see` siguen devolviendo `self_in_front`.
  - Lo prueba un test de bridge con `CompositeParentTools`.
- **A2. Un solo interruptor.**
  - No hay ajuste nuevo: los archivos `SelfInspection*` no mencionan `UserDefaults` (test que escanea las fuentes).
  - El runner solo entra en la lista del puente (CompanionMain.swift:142), nunca en `conversationTools`.
  - Con el interruptor apagado no hay listener (BridgeHost.swift:101-114, sin cambios).
- **A3. R7.** La primera `companion_*` de una conexion abre la hoja de sesion. Si la usuaria deniega, devuelve `denied_by_user` y no se ejecuta nada.
- **A4. R2.** Toda `companion_*` pasa por la puerta con `said: ""` (`FakeParentTools.saidSeen` todo vacio).
- **A5. R5.**
  - Las `companion_*` estan en `BridgeScope.bridgeTools` y en `BridgePolicy.readTools`.
  - `BridgeAllowlistTests` se edita a proposito con el conjunto nuevo.
  - `BridgePolicy.unbucketed(BridgeScope.bridgeTools)` sigue vacio.
- **A6. R1, R3 y R8: cero escrituras.**
  - Los nombres de los specs del runner son un subconjunto de `readTools`.
  - `approval(for:said:)` devuelve nil para todas.
  - Con una aprobacion pendiente en un `SessionModel` real, llamar todas las `companion_*` deja igual `projection.approval?.requestId`. `ScriptedApprovals` no registra ninguna resolucion.
- **A7. Solo metadatos (D1, D2, D5 de inspeccion).** Un fixture con un texto centinela en cada `String` de entrada recorre todas las salidas, y el centinela no aparece en ninguna. Las entradas con centinela son:
  - texto de los mensajes;
  - `summary` e `inputJSON` de la aprobacion;
  - `job.goal` y los pasos;
  - `targets`, `partial`, el texto dictado, `followUp`, `chatError` y los recibos;
  - nombre, sobre ti, instrucciones, ciudad y vocabulario.

  Ademas: el titulo de conversacion no aparece en ningun tipo de salida, y todo `String` asociado de `IslandState.Line` sale como longitud.
- **A8. Oraculo de igualdad (D3).**
  - `companion_last_message_matches` devuelve solo `{"matches": bool}`.
  - Compara contra el ultimo mensaje con rol user del hilo activo (Q2).
  - Tiene limite propio de 10 por minuto (Q4); pasado el limite devuelve `rate_limited`.
  - El texto esperado nunca aparece en el log (test con `Log.capturing(to:)`).
- **A9. Rasgos derivados dentro del proceso (D4).**
  - El idioma de cada mensaje se calcula con `LanguageRecognizing`.
  - Solo salen el codigo y la confianza; el texto no sale.
- **A10. Log (D6).**
  - `companion_log` devuelve las ultimas N lineas del log principal (N por defecto 50, maximo 200, tope de 32 000 bytes).
  - El texto termina con `BridgeCopy.toolDataSuffix`.
  - Ningun camino lee el log de transcripciones de depuracion (test que escanea las fuentes).
- **A11. R6.** La linea `Log.bridge("call ...")` de una `companion_*` lleva `target=` vacio; el runner nunca pone contenido en `target`.
- **A12.** Existe ADR 009 en `docs/DECISIONS.md` (texto en §5; numerado 009 porque main ya tenia un ADR 008).
- **A13. Gates.**
  - `scripts/gates.sh` en verde en cada PR.
  - Pasan por code-reviewer, qa-reviewer y security-reviewer, que lo revisa como frontera de confianza (puente, hoja, canal `said`, Ajustes).
- **A14. Prueba en vivo de Karen** (app release, Claude Code por el shim):
  - con Companion al frente, `companion_state`, `companion_island`, `companion_settings` y `companion_log` responden;
  - `click` sobre Companion sigue rechazado;
  - Karen teclea la frase del guion y `companion_last_message_matches` da `true` (la frase la teclea Karen, segun la decision de `self-qa-inspeccion-datos.md:9`).

## 2. Estado actual (verificado)

**El rechazo**
- `readyHands` devuelve nil sin permiso de Accesibilidad o con Companion al frente: `guard let hands, hands.trusted(), !hands.selfInFront()` (ParentToolRunner.swift:62-65).
- `specs` solo agrega manos y vista con `readyHands` (ParentToolRunner.swift:82-85).
- `unavailability(for:)` devuelve `selfInFront` para manos y vista con Companion al frente (ParentToolRunner.swift:100-107).
- El codigo `self_in_front` esta en BridgeProtocol.swift:187-189 y su mensaje en BridgeSession+Calls.swift:250-251.
- Tests que lo fijan:
  - `testTheHandsAreHiddenWhileCompanionIsInFront` (HandsPolicyTests.swift:133);
  - ParentToolUnavailabilityTests.swift:21-23;
  - BridgeSessionTests.swift:253-257.

**El camino de una llamada**
- Primero la allowlist (BridgeSession+Calls.swift:59-61).
- Despues `handles` / `unavailability` (lineas 62-66) y luego `policy.admit` (linea 68).
- La primera llamada abre la hoja de sesion (lineas 93-151; BridgePolicy.swift:185-188).
- La puerta corre con `said: ""` (BridgeSession+Calls.swift:161-162).
- Al ejecutar dispara `onCall` y, solo para `writeTools`, `onAction` (lineas 176-180). El log lleva solo nombre, ok, target y caracteres (lineas 182-183).
- `hello` publica `tools.specs(...)` filtrado por `BridgeScope.allows` (BridgeSession.swift:279-285).
- El protocolo solo tiene `hello`, `call` y `bye` (BridgeProtocol.swift:9-13).
- `BridgeCallResult` es `ok/output/target/tool`, sin contenido estructurado (BridgeProtocol.swift:120-139).
- `BridgeToolSpec` es plano: nombre, descripcion, propiedades y requeridos, y descarta `rawParametersJSON` (BridgeProtocol.swift:60-79).

**Politica y allowlist**
- La allowlist es `BridgeScope.bridgeTools`, y `decided` = permitida o solo local (DeliverableTools.swift:75-98).
- Los cubos de presupuesto:
  - `writeTools` (BridgePolicy.swift:34-49);
  - `readTools` (lineas 60-70);
  - `unbucketed` (lineas 72-75);
  - lecturas a 60 por minuto (linea 83).
- Una sesion en pausa devuelve `busy` (BridgePolicy.swift:194-195). `BridgeHost` pausa en todo turno de Karen (BridgeHost.swift:86-95).
- Patron de limite por ventana: `BridgeSheetLimit` (BridgePolicy.swift:270-283).
- Tests de guardia:
  - `everyToolTheRunnerOffersHasABridgeDecision` y el conjunto exacto `everyToolTheBridgeAlreadySupportedStaysSupported` (BridgeAllowlistTests.swift:68-80, 88-108);
  - BridgeReadBudgetTests.swift:69-78.

**Composicion**
- `CompositeParentTools`: gana el primer runner que maneja el nombre, y `unavailability` recorre todos (AppToolRunner.swift:327-389).
- El puente recibe `CompositeParentTools([parent, bridgeRunner])` (BrowserHost.swift:144-146), cableado en `installBridge` (CompanionMain.swift:130-163, linea 142).
- `installBridge` corre antes que `presentWindow` (CompanionMain.swift:93-98).
- `ParentToolExecuting` y sus valores por defecto: ParentTools.swift:293-347. `approval` por defecto delega en `ParentToolGate`, que solo pide hoja para `open_url` (ParentToolPolicy.swift:185-201).
- No existe ninguna tool `companion_*` (grep).

**De donde sale cada dato**
- Sesion: `SessionModel.projection` (SessionModel.swift:12) de tipo `SessionProjection` (SessionTypes.swift:69-131). Es Core y solo tiene enums, salvo:
  - `partial`, `targets`, `touched` y `dictation`;
  - `job.goal`;
  - `approvalQueue[].summary/inputJSON` (AgentStreamCodec.swift:3-11).
- Cada transicion de sesion ya va al log principal: `logTransition` → `log("session: a -> b")` (SessionModel.swift:164-165), cableado a `Log.app` (CompanionMainSensing.swift:139-140).
- Isla:
  - el estado pintado se calcula dentro de la vista con entradas locales y no se expone (IslandView.swift:92-103);
  - `IslandGeometry` es el objeto que la App ya comparte con la vista (IslandChrome.swift:143; CompanionMainWindow.swift:145);
  - casos de `Line` con texto asociado: IslandState.swift:14-56;
  - `IslandCopy.line` mezcla copia del catalogo con contenido (goal en 25-28, `followUp` en 39, `chatError` en 46, recibo en 47) y es `internal` (IslandCopy.swift:5-48).
- Pantalla: `showSettings`, `settingsTab` y `page` son `@State` privados de `CompanionRootView` (CompanionRootView.swift:21-22, 26). `MainPage` no tiene `rawValue` (MainSidebar.swift:7-10).
- Hilo activo: `ChatViewModel.messages` (ChatViewModel.swift:12). `ChatMessage` lleva `role`, `isStatus`, `text`, `attachments`, `card`, `origin`, `isFailure` y `restored` (ChatMessage.swift:37-57). `MessageOrigin` es `typed` o `choice` (lineas 32-35).
- Ajustes: `LanguagePreference.stored/current` (UserPreferences.swift:14, 22), `UserProfile.ownerName/about/instructions/city` (34-50) y `HandsLendingPreference.enabled` (321), entre otros.
- Idioma: puerto `LanguageRecognizing` / `DetectedLanguage` (MouthLanguageGate.swift:5, 17) y adaptador `NaturalLanguageRecognizer` (NaturalLanguageRecognizer.swift:9-23).
- Log:
  - `Log` no tiene API de lectura;
  - escribe una linea saneada (Log.swift:54-73) en un archivo de 1 MB con una generacion `.1` (lineas 14, 118-130);
  - la ruta es `~/Library/Logs/<identidad>` (CompanionMainEnvironment.swift:37-39).
- Marco de datos: `BridgeCopy.toolDataSuffix` (BridgeCopy.swift:69-76). Precedente de anadirlo a la salida: BrowserToolRunner.swift:206.
- Fakes: `FakeParentTools` con `saidSeen` y `executeCalls`, y `ScriptedApprovals` (ToolFakes.swift:71-160, 169).

Las citas de linea se tomaron en la rama del brief; antes del PR-1 se re-verifican contra main (despues de #71).

## 3. Archivos y API por capa

### Core (puro)

`Sources/CompanionCore/Bridge/SelfInspection.swift` (nuevo; si pasa de 400 lineas, se parte en `SelfInspection+Projection.swift`):

```swift
package enum CompanionTool: String, CaseIterable, Sendable {
    case state = "companion_state"
    case island = "companion_island"
    case settings = "companion_settings"
    case thread = "companion_thread"
    case lastMessageMatches = "companion_last_message_matches"
    case log = "companion_log"
    /// Nombre fijo; descripcion en el idioma de la respuesta + toolDataSuffix.
    package func spec(_ language: AppLanguage) -> ToolSpec
}

/// Puerto de lectura. Sin ningun metodo que escriba: R1/R3/R8 por forma.
package protocol SelfInspecting: Sendable {
    func session() async -> SessionProjection
    func island() async -> PaintedIsland?
    func screen() async -> InspectedScreen?
    func settings() async -> SettingsInspection
    func activeThread() async -> [ThreadMessageInput]
}

package struct PaintedIsland: Sendable, Equatable { var state: IslandState; var catalogText: String? }
/// Entrada con texto: NO Codable a proposito; description redactada (patron DictatedText).
package struct ThreadMessageInput: Sendable, Equatable, CustomStringConvertible { ... text: String ... }

// Salidas: Encodable, sin ningun String de la usuaria.
package struct SessionInspection: Encodable, Equatable { init(_ p: SessionProjection) }
package struct IslandInspection: Encodable, Equatable { init(_ painted: PaintedIsland) }
package struct InspectedScreen: Sendable, Encodable, Equatable { settingsOpen: Bool; settingsTab: String?; page: String }
package struct SettingsInspection: Sendable, Encodable, Equatable { /* init toma Strings libres y guarda solo longitudes */ }
package struct MessageInspection: Encodable, Equatable { init(_ input: ThreadMessageInput, detected: DetectedLanguage?) }

package enum LastMessageMatch {
    package static let maxExpectedScalars = 2_000
    /// Trim de espacios y saltos; igualdad de String (canonica), sin plegar mayusculas.
    package static func matches(_ expected: String, in thread: [ThreadMessageInput]) -> Bool
}
package struct EqualityCheckLimit: Sendable, Equatable {  // forma de BridgeSheetLimit
    package static let perMinute = 10
    package mutating func admit(now: Date) -> Bool
}
extension IslandState.Line { package var carriesText: Bool }  // true si algun valor asociado es texto
```

**Reglas de proyeccion:**
- `SessionInspection` lleva:
  - kind y fase, estado de la voz, pipeline, `holding` y si hay dictado;
  - del trabajo: si esta activo, numero de pasos y longitud de la meta;
  - numero de trabajos en cola;
  - de la aprobacion: `toolName`, `isMCP` y el tamano de la cola, nunca `summary` ni `inputJSON`;
  - nombres de caso de `notice`, `cards` e `interruption`;
  - numero de targets, `handsLentTo` (nombre que declaro el agente), `handsActing` y si hay recibo.
- `IslandInspection` lleva:
  - tamano, medidor y nombre de caso de la linea;
  - longitudes de cada texto asociado;
  - `catalogText` solo si `!carriesText`;
  - luz, nombre de la accion y `showsStop`;
  - de la aprobacion, solo `toolName`;
  - chip de manos, si hay recibo y longitud de `partial`.
- `SettingsInspection` es una lista cerrada:
  - idioma guardado (null = sistema) e idioma efectivo;
  - aspecto, voz, volumen, modo de voz y tecla de dictado;
  - sonidos, sonido de espera, decision y manos;
  - orden de proveedores;
  - longitudes de nombre, sobre ti, instrucciones y ciudad;
  - numero de palabras del vocabulario.

  Nada del Keychain, ni siquiera si hay una clave. Hay que verificar al implementar que `DictationKey` tenga un nombre de caso serializable.

### Services

`Sources/CompanionServices/Bridge/SelfInspectionRunner.swift` (nuevo):

```swift
package struct SelfInspectionRunner: ParentToolExecuting, Sendable {
    package init(source: any SelfInspecting,
                 recognizer: any LanguageRecognizing = NaturalLanguageRecognizer(),
                 language: @escaping @Sendable () -> AppLanguage,
                 logTail: @escaping @Sendable (Int) -> [String] = { Log.tail(lines: $0) },
                 now: @escaping @Sendable () -> Date = { Date() })
}
```

- `specs` = `CompanionTool.allCases`.
- `handles` = el nombre es una `CompanionTool`. No depende de `readyHands`.
- `execute` llama al puerto, proyecta y devuelve `ParentToolOutcome(ok:, output: <JSON compacto con claves ordenadas>, target: "", tool: name)`.
- Errores: `invalid_args` (N fuera de rango o `expected` que no es texto o es demasiado largo), `not_available` (isla o pantalla todavia sin pintar) y `rate_limited`.
- `EqualityCheckLimit` vive en una caja `final class @unchecked Sendable` con lock.
- `approval` usa el valor por defecto (nil).

`Sources/CompanionServices/Platform/Log.swift`: `package static func tail(lines: Int) -> [String]`, que lee `sink.fileURL` con el lock, y `tail(lines:from:)` sobre una URL para los tests. Solo el archivo actual, nunca `.1` ni el log de transcripciones.

`Sources/CompanionCore/Deliverables/DeliverableTools.swift` y `Sources/CompanionCore/Bridge/BridgePolicy.swift`: los seis nombres entran en `bridgeTools` y en `readTools` (PR-3).

### UI

`Sources/CompanionUI/Inspection/SelfInspectionSource.swift` (nuevo):
- `@MainActor package final class InspectionMirror`, con `island: PaintedIsland?`, `screen: InspectedScreen?` y `paint(_ state: IslandState)`, que calcula `catalogText` con `IslandCopy.line` solo si `!carriesText`.
- `@MainActor package final class SelfInspectionSource: SelfInspecting`, con `init(session: SessionModel, chat: ChatViewModel, mirror: InspectionMirror)`.
- Queda por verificar con el compilador que una clase `@MainActor` cumple el protocolo async `Sendable`. Si no, metodos `nonisolated` con `await MainActor.run`.

`IslandView.swift` gana `mirror: InspectionMirror? = nil` y escribe con `.onChange(of: state, initial: true)`. `CompanionRootView.swift` hace lo mismo para `showSettings`, `settingsTab` y `page`, sin plain `@Observable`, para no repintar.

### App

- `CompanionMain.swift`:
  - el delegado crea `let inspection = InspectionMirror()`;
  - `installBridge` pasa `CompositeParentTools([sensing.browserHost.bridgeTools(parent: sensing.parentTools), SelfInspectionRunner(source: SelfInspectionSource(session: sensing.sessionModel, chat: sensing.model, mirror: inspection), language: { env.configProvider.current.language })])`.
- `CompanionMainWindow.swift` pasa `mirror:` a `IslandView` y a `CompanionRootView`.

## 4. Plan TDD (primero RED)

**Core:** `Tests/CompanionCoreTests/SelfInspectionTests.swift`
- `companionToolWireNamesAreStableInBothLanguages`
- `everyCompanionToolDescriptionEndsWithDataSuffix`
- `sessionInspectionNamesApprovalToolButNeverSummaryOrInput`
- `sessionInspectionJobGoalAndTargetsAreCountsOnly`
- `islandInspectionNamesEveryLineCase`
- `islandAssociatedTextBecomesLength`
- `islandCatalogTextOnlyForLinesWithoutText`
- `settingsInspectionFreeTextIsLengthOnly`
- `settingsInspectionHasNoSecretField`
- `threadInputTypeIsNotEncodable` (`!(ThreadMessageInput.self is Encodable.Type)`)
- `threadInputDescriptionIsRedacted`
- `messageInspectionCarriesRoleOriginFlagsAndLength`
- `lastMessageMatchTrimsButIsCaseSensitive`
- `lastMessageMatchOnlyAgainstLastUserMessage`
- `lastMessageMatchWithNoUserMessageIsFalse`
- `equalityLimitAdmitsTenPerMinuteThenRefuses`
- `encodedOutputsNeverContainSentinel`

**Services, runner:** `Tests/CompanionServicesTests/SelfInspectionRunnerTests.swift`, con `FakeSelfInspecting` en `Tests/CompanionCoreTestSupport/SelfInspectionFakes.swift`.
- `runnerOffersEveryCompanionTool`
- `runnerNeverAsksApproval`
- `runnerOutcomeTargetIsAlwaysEmpty`
- `threadToolDetectsLanguageInProcessAndDropsText`
- `matchesToolReturnsBoolOnly`
- `matchesToolNeverLogsExpected` (con `Log.capturing`)
- `matchesToolRejectsNonStringOrOversizeExpected`
- `matchesToolPastLimitIsRateLimited`
- `islandToolBeforeFirstPaintIsNotAvailable`
- `logToolReturnsLastLinesWithDataSuffix`
- `logToolCapsLinesAndBytes`
- `logTailReadsOnlyTheGivenFile`
- `selfInspectionSourcesNeverMentionTranscriptDebugLogOrUserDefaults`

**Services, puente:** `Tests/CompanionServicesTests/SelfInspectionBridgeTests.swift`
- `companionToolsAreAllowlistedAndReadBucketed`
- `firstCompanionCallOpensSessionSheetAndDenialRunsNothing` (R7)
- `companionCallsReachTheGateWithEmptySaid` (R2, `saidSeen`)
- `companionToolsServeWhileCompanionIsInFrontAndHandsStaySelfInFront` (A1, `ParentToolRunner` con `selfInFront: { true }` + runner)
- `companionCallLogLineHasEmptyTarget` (R6)
- Se edita `BridgeAllowlistTests.swift`: el conjunto esperado suma las seis, y `fullRunner()` se une con los specs de `SelfInspectionRunner` para que la guarda no sea vacia.

**UI:** `Tests/CompanionUITests/SelfInspectionSourceTests.swift`
- `sourceReadsProjectionAndThreadWithoutTitle`
- `sourceSettingsReadsLanguageStoredAndEffective`
- `mirrorPaintKeepsCatalogTextOnlyForTextFreeLines`
- `mirrorScreenMapsMainPageAndSettingsTab`

**Integracion:** `Tests/CompanionIntegrationTests/SelfInspectionFlowTests.swift`
- `pendingApprovalIsUntouchedByEveryCompanionTool` (R1, `SessionModel` real con `.job(.approvalRequested(...))` y `ScriptedApprovals` sin resoluciones)
- `sentinelNeverLeavesThroughTheBridge` (A7 de punta a punta, `BridgeSession.handle(line:)`)

Antes de escribir cada test se confirma en main en que target vive hoy el archivo que se extiende (`git ls-tree origin/main Tests/`).

**Deben seguir en verde sin editarse:** `HandsPolicyTests`, `ParentToolUnavailabilityTests`, `BridgeSessionTests`, `BridgeReadBudgetTests`, `BrowserToolScopeTests`, `LocalizedTests` y `SettingsParityTests`.

## 5. ADR para `docs/DECISIONS.md`

```markdown
## ADR 009 — Companion se deja inspeccionar, no manejar, por el puente

**Fecha:** 2026-10-01 · **Estado:** BORRADOR (spec self-qa-inspeccion; briefs self-qa-puente D3, self-qa-inspeccion-datos D1-D7)

**Contexto.** En el QA en vivo del 2026-10-01 el orquestador intento probar
Companion por su propio puente y toda accion devolvio `self_in_front`; recurrio
a UI scripting con System Events. Es el fallo observado que la regla de ADR 001
exige antes de sumar tools. Abrir las manos sobre Companion no es la salida: la
hoja de aprobacion vive en la misma ventana, el chat convierte texto en palabras
de la usuaria y Ajustes guarda grants y modos.

**Decision.** Una familia `companion_*` de SOLO LECTURA, servida unicamente por
el puente, detras del mismo "Prestar las manos" y de la hoja de sesion. Devuelve
metadatos: nombres de caso, conteos, longitudes, marcas, idioma detectado dentro
del proceso. El texto de la usuaria no sale; para el turno de texto hay un
oraculo de igualdad que contesta un bool, solo contra su ultimo mensaje y con
limite propio. El log principal sale como datos marcados, nunca el de
transcripciones. Ninguna `companion_*` escribe un ajuste ni pulsa nada (R1-R8).
Cada nombre entra por `BridgeScope` y `readTools` con su test.

**Lo que no se hizo.** Ni denylist sobre `click` (falla abierta ante cada
control nuevo), ni canal solo en debug (Karen prueba el release), ni contenido
completo de hilos (sale a un tercero sin consentimiento propio).

**Consecuencias.** La isla y la pantalla se leen de un espejo que la UI escribe
al pintar: lo que se inspecciona es lo pintado, no una reconstruccion. Mientras
Karen habla el puente esta en pausa, asi que la secuencia de un turno se lee
despues, del log. Disparador de revision: una prueba cuyo oraculo no quepa en
metadato, igualdad o rasgo derivado (D7 de self-qa-inspeccion-datos).
```

## 6. PRs (en orden; como mucho 5 archivos cada uno)

Reglas para todos los PR:
- Comentarios solo con el porque.
- Sin dependencias nuevas y sin tocar configs raiz.
- Los briefs APROBADOS van en la rama.
- Entrada en `CHANGELOG.md` en espanol, con fecha, bajo `[Unreleased] / Added`.

| PR | Archivos | Depende de | Que queda |
|---|---|---|---|
| PR-1 Core: contrato y ADR | `SelfInspection.swift`, `SelfInspectionTests.swift`, `DECISIONS.md`, esta spec, CHANGELOG (5) | nada | nada se sirve todavia |
| PR-2 Runner y lectura del log | `SelfInspectionRunner.swift`, `Log.swift`, `SelfInspectionFakes.swift`, `SelfInspectionRunnerTests.swift`, CHANGELOG (5) | PR-1 | no esta en la allowlist |
| PR-3 Allowlist | `DeliverableTools.swift`, `BridgePolicy.swift`, `BridgeAllowlistTests.swift`, `SelfInspectionBridgeTests.swift`, CHANGELOG (5) | PR-2 | todavia sin cablear en la App |
| PR-4 UI: fuente y espejo | `SelfInspectionSource.swift`, `SelfInspectionSourceTests.swift`, CHANGELOG (3) | PR-1 | con el espejo vacio, isla y pantalla dan `not_available` |
| PR-5 UI: la isla y la ventana escriben el espejo | `IslandView.swift`, `CompanionRootView.swift`, tests, CHANGELOG (4) | PR-4 | |
| PR-6 App: cableado | `CompanionMain.swift`, `CompanionMainWindow.swift`, `SelfInspectionFlowTests.swift`, CHANGELOG (4) | PR-3 y PR-5 | la funcionalidad queda viva |
| PR-7 (opcional) Solapamiento del corte (D4) | `SelfInspection.swift`, `SelfInspectionRunner.swift`, tests, CHANGELOG (4) | PR-6 y Q5 | campo `cutOverlap` en `companion_thread` |

CHANGELOG del PR-6: "**Con 'Prestar las manos' encendido, un agente puede revisar Companion aunque este al frente (fecha).** Solo mira: no pulsa, no escribe y no ve lo que escribes. Las manos siguen sin tocar Companion."

Fuera de alcance: D2, D4, D6 y D8 del puente; memoria; lista de hilos; cualquier escritura; el cambio en `companion-mcp`.

## 7. Riesgos y preguntas abiertas

**Q1 (bloquea la firma). Escrituras.**
- La D3 del puente incluia abrir una pagina de Ajustes, cerrarla y cambiar el idioma.
- R8 (ajuste-en-la-isla.md:7) prohibe la de idioma, y abrir una pagina ya es `show_setting` (`opened_page`).
- **Default:** cero escrituras. Cerrar Ajustes: ¿se descarta o va a `show_setting`?

**Q2. Contra que compara la igualdad.**
- D3 dice "el ultimo mensaje del hilo activo" (`self-qa-inspeccion-datos.md:23`); la tabla dice "ultimo mensaje con rol user y origen tecleado" (linea 34).
- **Default:** el ultimo mensaje user. Nunca se compara contra la respuesta del modelo.

**Q3. `structuredContent` y `outputSchema`** (checklists de ambos briefs).
- Exige ampliar `BridgeCallResult` y `BridgeToolSpec` y que el shim de `companion-mcp` los reenvie.
- **Default:** JSON en `output`, y una spec entre los dos repos despues. El punto del checklist queda abierto.

**Q4. Limite de la igualdad.** Default: 10 por minuto por proceso, ademas del presupuesto de lectura de 60.

**Q5 (gate del PR-7).** Hay que verificar que el parcial enhebrado tras un corte se distingue por una marca y no solo por su texto: leer `RealtimeRuntime`, `ClassicRuntime.swift:447` y `VoiceReconnectTests` (ASSUMPTION de `self-qa-inspeccion-datos.md:124`). Sin eso, el PR-7 no entra.

**Q6.** Sin verificar que el shim reenvia la lista de `hello` (ASSUMPTION de ambos briefs). Hay que leer `tools/list` de `companion-mcp` antes de A14.

**Riesgos:**
- **La pausa durante el turno de Karen** (BridgePolicy.swift:194-195) impide inspeccionar en vivo.
  - Mitigacion: la secuencia de fases se lee despues en `companion_log` (SessionModel.swift:164-165).
  - Sin verificar: que cada caso de linea de la isla tambien quede en el log. Si no queda, ese oraculo es solo el estado final.
- **Bucle de retroalimentacion.** Cada `companion_*` exitosa dispara `onCall` → aura sobre `lastOtherPID` (BridgeHost.swift:69-74), asi que `handsActing` refleja la propia inspeccion. El brief lo acepta como dato (`self-qa-puente.md:145`); se documenta en la descripcion de `companion_state`.
- **Oraculo de confirmacion.** Un agente puede probar hipotesis sobre lo que tecleo Karen. Mitigacion: bool, solo el ultimo mensaje user, limite propio y nunca se registra.
- **Lineas del log no confiables** (Log.swift:52-59). Mitigacion: marco fijo de datos y tope de bytes.
- **`NLLanguageRecognizer` con respuestas cortas** no esta medido (`self-qa-inspeccion-datos.md:126`). Sale la confianza junto al codigo.
- **Datos que no existen hoy, y que no se inventan:**
  - el conteo de reconexiones no es un campo; sale del log;
  - la banda de una aprobacion no esta en `ApprovalRequest` (AgentStreamCodec.swift:3-11), asi que se omite.
- **Sin verificar que los turnos de voz entren en `ChatViewModel.messages`.** Si no entran, `companion_thread` solo cubre el chat escrito.
- **D7 del puente** (un cliente AX fuera de banda que pulsa la hoja) no cambia con esta spec.
