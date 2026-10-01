# Ajuste en la isla ("cambia mi nombre de usuario")

**Estado: APROBADO** (Karen, 2026-10-01; respuestas registradas al inicio).
Research: `docs/research/ajuste-en-la-isla.md` (APROBADO 2026-10-01: D1-D7 y D9 como recomienda el brief, R8 nueva; D8 resuelta por la spec `velocidad-de-voz-por-conversacion`; "listo" por voz; los pedidos del puente esperan en cola). El brief va en la rama de cada PR, porque el research-gate lo exige.

Respuestas de Karen (2026-10-01): "dale solucion a los pendientes, no me parecen tan importantes como para que nos frenen". Q1-Q8 se resuelven con los defaults de la seccion 6 (Q1: tarjeta con un boton "Abrir en Ajustes"; Q2: `queued` con tope 3; Q3: tabla de extras y `general.talk` como pagina; Q4: "listo" solo con la voz abierta; Q5: el pedido de la usuaria pasa delante; Q6: 20 s, ajustable en A19).

## 1. Objetivo

Cuando la usuaria pide cambiar uno de sus ajustes, Companion no lo cambia. Llama a `show_setting(id)` y trae ese unico control (switch, selector, campo de una linea, slider o stepper) a la isla, y ella lo cambia con un gesto. La peticion puede llegar por voz, por texto o por un agente del puente MCP.

Los ajustes de clase pagina, entre ellos los canales de contexto (D9), y cualquier pedido con la ventana principal delante abren Ajustes en esa pagina con la fila resaltada. Despues de un cambio, la voz dice "listo". El modelo nunca ve el valor.

**R8 (regla del brief, firmada por Karen).** Ninguna tool del modelo ni del puente escribe un ajuste. El unico que escribe es el control que toca la usuaria. `show_setting` solo acepta `id`; Core y Services no conocen las preferencias, porque viven en UI y las capas lo impiden al compilar.

**Fuera de esta spec:** la velocidad de voz. La cubre `velocidad-de-voz-por-conversacion.md`, no hay `SettingID` de velocidad y `SettingsParityTests` sigue igual.

### Criterios de aceptacion

Cada criterio tiene su test o su evidencia.

- **A1. Ids.** `SettingID` vive en Core con raw value `pagina.nombre`. Cada opcion y cada panel de `SettingsInventory` llevan un `id` que no es opcional: si falta, no compila. Un test exige que sean unicos y que cada id no extra aparezca exactamente una vez en el inventario.
- **A2. Clases (D1, D2, D9).**
  - **isla:** `general.dictationKey`, `general.language`, `general.sounds`, `general.screenGlow`, `voice.voice`, `voice.volume`, `vocabulary.add`, `you.name`, `you.city`, `you.appearance`, `you.textSize`.
  - **pagina:** `general.talk` (Q3), `voice.elevenLabs`, `vocabulary.list`, `memory.entries`, `you.photo`, `you.about`, `you.instructions`, `privacy.screen`, `privacy.documents`, `privacy.location`, `privacy.permissions`, `privacy.browser`, `system.version`, `system.welcomeAgain`.
  - **nunca:** `privacy.keys`, `privacy.lendHands`, `system.attachments`.
  - Ningun control que dependa de una clave guardada es de isla. Un test fija las tres listas por id.
  - Grants, destinos y modos de autorizacion (20d) no existen todavia en el inventario. Cuando entren, A1 obliga a darles clase.
- **A3. Contrato.**
  - El esquema de `show_setting` enumera solo ids de isla y de pagina y no tiene mas propiedad que `id`.
  - Un id de clase `never` devuelve `not_surfaceable` sin abrir nada.
  - Un id desconocido devuelve `unknown_setting`.
  - Un argumento roto o con campos extra devuelve `invalid_args` y nunca repite los argumentos.
  - Ningun camino cae a una pagina por defecto (el antiejemplo es `CompanionRootView.swift:242`).
- **A4. Disponibilidad.** `show_setting` se anuncia con Companion delante y sin Accesibilidad, fuera de `readyHands` (`ParentToolRunner.swift:62`).
- **A5. Sin valor.**
  - Respuesta inmediata: `shown`, `opened_page` o `queued` (Q2), o un error. Lleva el id y nunca el valor.
  - Metadato posterior para chat y voz: `IslandEvent.setting(id, outcome)` con `changed`, `dismissed` o `expired`, en la linea de `ContextBlock`, tambien sin valor.
  - Un test con nombre "Ana Prueba" y ciudad "Oaxaca" guardados revisa `output` y `target` (los campos de `BridgeCallResult`, `BridgeProtocol.swift:120-131`).
- **A6. R8 por escaneo de fuente.**
  - Los archivos nuevos de Core y Services no mencionan `UserDefaults`, `VoiceProfile`, `UserProfile` ni `Preference`.
  - En UI, `SettingWriter.` solo aparece en `IslandSettingCard.swift`, `SettingsVoiceSection.swift` (via `updateVoice`) y los tests.
- **A7. La hoja gana.** Con una aprobacion pendiente no hay tarjeta de ajuste (test puro sobre `IslandState`). Cuando la hoja se va, la tarjeta vuelve.
- **A8. Ventana delante.** Con la ventana principal delante no hay tarjeta. Ajustes abre la pagina, la fila se enciende 1,6 s y la respuesta es `opened_page`.
- **A9. Una tarjeta a la vez.**
  - Un pedido del puente con una tarjeta abierta va a la cola, con tope de 3; pasado el tope, `busy`.
  - Un pedido del puente nunca reemplaza la tarjeta que pidio la usuaria.
- **A10. Anti-clic.** La tarjeta ignora clics durante `ApprovalClickGuard.dwell` (0,6 s, `IslandState.swift:276`).
- **A11. Foco (D5).**
  - Un pedido del puente nunca pide teclado.
  - Un pedido por voz no toma el teclado sin un clic.
  - Desde el campo de la isla, con el panel ya key, el control recibe el foco.
- **A12. Escrituras correctas.**
  - Toda escritura de voz lee `VoiceProfile.settings` fresco.
  - El slider escribe al soltar.
  - Cambiar el idioma publica `companionLanguageDidChange`.
- **A13. Accesibilidad e idioma (D6).**
  - Titulo y subtitulo salen del inventario por `Localized`.
  - Todo id de isla tiene texto en es y en y pasa el filtro de jerga.
  - La tarjeta publica `AccessibilityNotification.Announcement` al aparecer.
  - El control, y la fila de Ajustes, llevan `accessibilityIdentifier = SettingID.rawValue`.
- **A14. Puente (D7).**
  - Solo con sesion abierta: la primera llamada abre la hoja de sesion (`BridgePolicy.admit`, `BridgePolicy.swift:186-188`).
  - La tarjeta dice el nombre que declara el agente, saneado con `loggableName` (`BridgeSession+Calls.swift:237`) y marcado como declarado.
  - Ningun texto del agente llega a la tarjeta.
- **A15. Enfriamiento.**
  - Tres tarjetas del puente cerradas sin cambio (`dismissed`) en 10 minutos hacen que la siguiente llamada devuelva `cooling_down`.
  - Reconectar no reinicia la cuenta.
  - `expired` no cuenta, igual que `countsAsDenial` (`BridgeSession+Calls.swift:200`).
  - `show_setting` gasta del presupuesto de escritura.
- **A16. "Listo".** Tras `changed`, con la voz abierta (Q4), suena una sola vez:
  - en clasico, la frase fija de Core;
  - en realtime, la instruccion equivalente.
- **A17. Cierre del puente.** Al cerrarse la sesion del puente, sus tarjetas (la visible y las de la cola) salen como `expired` y no cuentan.
- **A18. Las paginas no pisan.** Con Tu, Vocabulario o Voz abiertas, un cambio hecho desde la isla sobrevive al siguiente tecleo o eleccion en la pagina (`SettingsPages.swift:126`, `:250`; `SettingsVoiceSection.swift:59-64`).
- **A19. Prueba en vivo de Karen** (app release):
  - "cambia mi nombre", por texto desde la isla y por voz;
  - "activa la ubicacion", que abre la pagina;
  - un agente con "Prestar las manos" pide `general.sounds`;
  - lo mismo con la ventana delante;
  - VoiceOver encendido.
- **Gates:** `scripts/gates.sh` en verde en cada PR (incluye el ratchet de `conformance/ui-contract.json`); code-reviewer, qa-reviewer y security-reviewer, que trata esto como frontera de confianza: puente, isla, teclado y la Config que va al modelo.

## 2. Estado actual (verificado en la rama del brief; re-verificar contra main antes del PR-1)

**Inventario y Ajustes**
- `SettingsInventory` declara 18 opciones (`SettingsInventory.swift:46-69`) y 7 paneles (`:71-79`).
  - "Hablar" (`:47`) no tiene control: solo dibuja la tecla (`HoldSettings.swift:83-89`).
  - El volumen no es opcion: vive en la isla (`IslandPopover.swift:125-147`).
- La busqueda usa `titleKey` como id (`SettingsInventory.swift:91-105`).
- `jump` abre la pagina y enciende la fila 1,6 s (`SettingsView.swift:135-146`, constante en `:17`). La fila se pinta si su `key` coincide (`SettingsPieces.swift:70`).
- `companionOpenSettings` recibe el `rawValue` de la pagina y cae a General en silencio (`CompanionRootView.swift:237-244`). Su nombre esta en `MenuPlan.swift:82`.
- La pagina Tu copia el perfil a `@State` (`SettingsPages.swift:7-13`) y escribe los cuatro campos juntos (`:126-131`). Ya escucha `companionProfileDidChange`, pero solo para el avatar (`:67-69`).
- Vocabulario guarda su copia entera (`SettingsPages.swift:250-253`).
- Voz escribe su copia entera (`SettingsVoiceSection.swift:59-64`).
- Idioma: `LanguagePreference.stored` mas `onChange` (`SettingsLanguageRow.swift:21-24`). La hoja publica `companionLanguageDidChange` (`SettingsView.swift:148-151`).
- La tecla de dictado se escribe leyendo fresco (`HoldSettings.swift:139-145`).
- El setter de `VoiceProfile.settings` reescribe todos los campos de voz (`UserPreferences.swift:257-269`).
- Nombre, sobre ti, instrucciones y ciudad entran en la Config del modelo (`StoredConfigProvider.swift:51-54`).
- `SettingsParityTests` fija el tope de 18 y la ausencia de velocidad (`SettingsParityTests.swift:28-47`) y pasa el filtro de jerga (`:49-77`).

**Isla**
- `IslandState.from` decide en un solo lugar puro. Recibe ofertas ajenas al reductor como parametro: `update:` (`IslandState.swift:116-121`, `:142-144`). La hoja fuerza `.card` y se oculta con `mainInFront` (`:162-165`). `yieldsKeyboard` (`:94`). `ApprovalClickGuard` (`:274-291`).
- `IslandView.state` llama a `from` (`IslandView.swift:92-101`). `status()` elige tarjeta por linea (`IslandView+Status.swift:8-28`).
- La tarjeta de pregunta solo toma el teclado al tocarla (`IslandChoiceCard.swift:70-72`). `AnswerOption` es reutilizable (`:172-221`), igual que `IslandChoiceWidth` (`:247-261`).
- Panel no activante (`IslandChrome.swift:209`) con `becomesKeyOnlyIfNeeded` (`:223`), `canBecomeKey` (`:381`) y `releaseKey` (`:395`).
- `mainInFront` vive en `HoldSettingsModel` (`HoldSettings.swift:29`) y lo actualiza la app (`CompanionMainWindow.swift:133-142`).
- Ningun archivo usa `AccessibilityFocusState` (grep: 0). Los anuncios usan `AccessibilityNotification.Announcement` (por ejemplo `IslandReceiptCard.swift:73`).

**Metadato al modelo**
- `IslandEvent` (`IslandEvents.swift:10-18`), `IslandEventLog` con capacidad 4 (`:35-70`) e `IslandEventBuffer` (`IslandEventBuffer.swift:6-23`), cableados en `CompanionMainSensing.swift:123-141`.
- `ContextBlock.eventLine` es un switch exhaustivo (`ContextBlock.swift:269-280`).
- `SessionModel.report` (`SessionModel.swift:90-92`).

**Tools**
- `ToolSpec.rawParametersJSON` pasa un esquema entero y evita `strict` (`ToolSpec.swift:20-23`, `:156`).
- `ParentToolRunner.specs` anade las manos solo con `readyHands` (`ParentToolRunner.swift:62-65`, `:77-87`).
- `CompositeParentTools` (`AppToolRunner.swift:327-352`).
- La conversacion usa `browserHost.conversationTools(...)` (`CompanionMainSensing.swift:206`). Chat, clasico (`ClassicRuntime.swift:307`) y realtime (`RealtimeRuntime.swift:194`) leen sus specs, y la voz los recibe en `CompanionMainVoice.swift:134`.
- `ContractError` (`ParentTools.swift:6-41`), `ParentToolOutcome` (`:256-286`), `ParentToolExecuting` (`:293-327`).

**Puente**
- `BridgeScope.bridgeTools` es una allowlist (`DeliverableTools.swift:75-97`). `BridgeAllowlistTests` exige la lista exacta (`BridgeAllowlistTests.swift:89-98`) y que un runner completo la cubra (`:68-80`).
- `BridgePolicy.writeTools`/`readTools` (`BridgePolicy.swift:34-70`), con un test de herramientas sin cubeta (`BridgeReadBudgetTests.swift:69`).
- `maxDenials` = 3 en 10 minutos (`BridgePolicy.swift:97-98`), `recordDenial` e `isCoolingDown` (`:130-138`).
- `performCall` ejecuta `tools.execute` sin argumentos de origen (`BridgeSession+Calls.swift:156-185`).
- El chip del puente dice "Claude Code" fijo, no el nombre declarado (`BridgeHost.swift:125-130`).
- Composicion del puente: `CompanionMain.swift:140-142`. `ReceiptRelay` es el patron de un relay tardio (`CompanionMain.swift:233-244`).
- El protocolo solo tiene `hello`, `call` y `bye`, y `BridgeCode.busy` existe (`BridgeProtocol.swift:164-197`).

**Voz**
- `JobAnnouncement` dice una frase fija en clasico y pasa una instruccion en realtime (`Escalation.swift:95-152`). Solo `Escalation.swift` hace switch sobre su `Outcome`.
- `VoiceSession.jobAnnounce` estaciona y espera un hueco, y descarta si la voz esta cerrada (`VoiceSession+Announcements.swift:29-42`).
- `VoicePortBox.session` es accesible desde App (`CompanionMain.swift:248-249`).
- En main, despues de #71, los fakes de `VoiceSession` viven en `Tests/CompanionServicesTestSupport/VoiceSessionFakes.swift`; los tests de sesion de voz, en `CompanionIntegrationTests`. Re-verificar antes del PR-10.

## 3. Archivos y API por capa

### Core (puro)

`Sources/CompanionCore/Settings/SettingID.swift` (nuevo):
- `package enum SettingSurface: Sendable, Equatable { case island, page, never }`
- `package enum SettingID: String, CaseIterable, Sendable, Equatable`: los 28 casos de A2. Son 25 del inventario mas 3 extras (`voice.volume`, `voice.elevenLabs`, `vocabulary.add`; ver Q3).
  - `var surface: SettingSurface`
  - `var page: String`: el prefijo antes del punto, igual a `SettingsTab.rawValue`. Un test de UI lo comprueba.
  - `static func parse(_ raw: String) -> SettingID?`: coincidencia exacta, sin recortar.

`Sources/CompanionCore/Settings/ShowSetting.swift` (nuevo):
- `package enum SettingRequestOrigin: Sendable, Equatable { case conversation, bridge(client: String) }`
- `package struct SettingCardRequest: Sendable, Equatable, Identifiable { id: UUID; setting: SettingID; origin: SettingRequestOrigin }`
- `package enum SettingCardOutcome: String, Sendable { case changed, dismissed, expired }`
- `package enum ShowSettingReply: Sendable, Equatable { case shown, openedPage, queued, refused(code: String) }`
- `package protocol SettingSurfacing: Sendable { func show(_ id: SettingID, origin: SettingRequestOrigin) async -> ShowSettingReply }`
- `package enum ShowSetting`:
  - `toolName = "show_setting"`;
  - codigos `unknownSetting`, `notSurfaceable`, mas `busy` y `notAvailable` con el mismo texto de cable que `BridgeCode`;
  - `parse(_ argumentsJSON:) -> Result<SettingID, ContractError>`, que rechaza claves distintas de `id`;
  - `outcome(_ reply:, id:) -> ParentToolOutcome`: `target` = `id.rawValue`. El `output` es una frase fija: "esta en la isla, ella lo cambia; no digas que cambio".
- `extension ToolSpec { package static func showSetting(_ language: AppLanguage) -> ToolSpec }`:
  - `rawParametersJSON`: `{"type":"object","properties":{"id":{"type":"string","enum":[ids isla+pagina]}},"required":["id"],"additionalProperties":false}`;
  - la descripcion, en el idioma de la respuesta, dice: usala cuando la usuaria pida cambiar un ajuste suyo; tu no lo cambias; no digas que cambio.

`Sources/CompanionCore/Settings/SettingCardQueue.swift` (nuevo):
- `package struct SettingCardQueue: Sendable, Equatable`
  - constantes: `capacity = 3` (Q2) e `idleLifetime: TimeInterval = 20`. Este ultimo es una ASSUMPTION del brief §9; el comentario dice que no esta medido.
  - estado: `current`, `waiting`.
  - `admit(_:) -> Admission` (`.shown`, `.queued`, `.busy`):
    - conversacion sobre conversacion: reemplaza, y la reemplazada no emite evento;
    - puente con una tarjeta abierta: va a la cola;
    - conversacion sobre una del puente: pasa delante, y la del puente vuelve al frente de la cola (Q5).
  - `finish(_ id: UUID) -> SettingCardRequest?`: devuelve la siguiente.
  - `dropBridge() -> [SettingCardRequest]`.

`Sources/CompanionCore/Island/IslandState.swift`:
- Campo `package var setting: SettingCardRequest?` y parametro `setting: SettingCardRequest? = nil` en `from`. Los llamadores actuales no cambian.
- Regla: se pinta solo si no hay aprobacion, `!mainInFront` y `p.kind != .listening` (Q8). Entonces `size = .card`.

`Sources/CompanionCore/Island/IslandEvents.swift`: nuevo caso `case setting(SettingID, SettingCardOutcome)`.

`Sources/CompanionCore/Perception/ContextBlock.swift`: `eventLine` gana dos casos, por ejemplo "ajuste en la isla general.language: cambiado por la usuaria" y "setting on the island general.language: changed by the user". Sin valor.

`Sources/CompanionCore/Delegation/Escalation.swift`:
- `JobAnnouncement.Outcome` gana `.settingChanged`;
- `spokenLine` = `Escalation.settingChangedSpoken(language)`: "Listo." / "Done.";
- `instruction` = "La usuaria acaba de cambiar un ajuste en la isla. Di solo: Listo.";
- `summarySource` = nil.

### Services

`Sources/CompanionServices/Settings/SettingToolRunner.swift` (nuevo):
- `package struct SettingToolRunner: ParentToolExecuting, Sendable`, con `init(surface: any SettingSurfacing, origin: @escaping @Sendable () -> SettingRequestOrigin)`.
- `specs` = `[ToolSpec.showSetting(language)]`, siempre.
- `handles` solo responde a `show_setting`. `approval` es nil, porque no hay hoja: no escribe nada.
- `execute`:
  - parsea con `ShowSetting.parse`;
  - una clase `never` devuelve `not_surfaceable` sin llamar a `surface`;
  - despues pide `surface.show` y devuelve `ShowSetting.outcome`.
- Revisar en la tarea que metodos de `ParentToolExecuting` (`ParentTools.swift:329+`) tienen default.

`Sources/CompanionServices/Settings/SettingSurfaceRelay.swift` (nuevo):
- `package final class SettingSurfaceRelay: SettingSurfacing, @unchecked Sendable`, con lock, mismo patron que `ReceiptRelay`.
- `connect(_:)`. Mientras no esta conectado responde `.refused(code: notAvailable)`.

`Sources/CompanionServices/Bridge/BridgeSession.swift`:
- Parametro `onHello: @Sendable (String) -> Void = { _ in }`, llamado con `loggableName(client)` al aceptar `hello`.
- `package func recordSettingDismissal() async`: `policy.recordDenial(now:)`. Si queda enfriando, `stop()` y `onState`.

`Sources/CompanionServices/Voice/Session/VoiceSession+Announcements.swift`: `package func announceSettingChanged(language: AppLanguage) async`, que reusa `jobAnnounce(JobAnnouncement(goal: "", outcome: .settingChanged, language:))`.

`Sources/CompanionCore/Bridge/BridgePolicy.swift`: `"show_setting"` entra en `writeTools`. Es lo que se quiere (brief §8): cambia lo que la usuaria ve.

`Sources/CompanionCore/Deliverables/DeliverableTools.swift`: `"show_setting"` entra en `BridgeScope.bridgeTools`.

### UI

`Sources/CompanionUI/Settings/SettingsInventory.swift`:
- `Option` y `Panel` ganan `id: SettingID`, no opcional.
- `static let extras: [(SettingID, SettingsTab, titleKey, subtitleKey?)]`. Las claves de los extras ya existen: `island.tip.volume`, `settings.voice.eleven.header`, `settings.vocabulary.add`.
- `static func entry(for: SettingID)` devuelve pestana, titulo y subtitulo.
- `static func reveal(_ raw: String?) -> (SettingsTab, String)?`: devuelve nil para un id desconocido, nunca General.
- `static func id(forKey:) -> SettingID?`.

`Sources/CompanionUI/Settings/SettingsPieces.swift`: `SettingsRow` pone `.accessibilityIdentifier(SettingsInventory.id(forKey: key)?.rawValue ?? "")`.

`Sources/CompanionUI/Settings/SettingWriter.swift` (nuevo, `@MainActor enum`):
- `package enum SettingValue { toggle(Bool), choice(String), text(String), level(Double), step(Int) }`
- `static func apply(_ id: SettingID, _ value: SettingValue) -> Bool`: devuelve false fuera de la clase isla o con un tipo que no corresponde.
- Una rama por id, que escribe solo su preferencia:
  - `general.language`: escribe y publica `companionLanguageDidChange`;
  - `general.sounds`: `InterfaceSound` mas `ThinkingSoundPref`, como la pagina;
  - `general.screenGlow`: `ScreenGlowPreference.set`;
  - `you.appearance`: `AppearancePreference.stored`, que ya publica chrome;
  - `you.textSize`: `TypeScale.nudge`;
  - `you.name` y `you.city`: un solo campo de `UserProfile` mas `companionProfileDidChange`;
  - `vocabulary.add`: `Vocabulary.adding` sobre `VocabularyPreference.text` fresco;
  - voz y tecla de dictado: via `updateVoice`.
- `static func updateVoice(_ mutate: (inout VoiceSettings) -> Void)`: lee fresco y escribe.

`SettingsPages.swift`:
- En `companionProfileDidChange`, Tu recarga `ownerName` y `city`.
- `commit` de Vocabulario parte de `VocabularyPreference.text` fresco.

`SettingsVoiceSection.swift`: `update` usa `SettingWriter.updateVoice`.

`Sources/CompanionUI/Island/Setting/IslandSettingCard.swift` (nuevo):
- Tarjeta con `IslandInk` y tokens. Lleva titulo y subtitulo del inventario, origen del puente ("Lo pide «%@», nombre que da el agente") y un solo control.
- Controles:
  - switch: sonidos, brillo;
  - selector como `AnswerOption`: idioma, tecla, voz, aspecto. Se aplican al tocar y la tarjeta se cierra con `changed`;
  - campo de una linea: nombre, ciudad, palabra. Return confirma (`changed`) y Escape cancela (`dismissed`);
  - slider de volumen: escribe al soltar;
  - stepper de tamano de texto: aplica en vivo; al cerrar con X o al expirar informa `changed` si hubo algun cambio.
- X informa `dismissed`. `ApprovalClickGuard` filtra clics. Publica el anuncio a VoiceOver al aparecer.
- `accessibilityIdentifier` = raw value.
- `AccessibilityFocusState` para un pedido por voz: ASSUMPTION; si la prueba en vivo falla, queda solo el anuncio.
- `@FocusState` solo si `takesKeyboard`.
- Helpers puros testeables:
  - `IslandSettingCopy.title/subtitle/origin/announcement`;
  - `IslandSettingControl.kind(for:)`;
  - `IslandSettingKeys`: Return y Escape.
- Para Q1, la variante de clase pagina pedida por el puente: un boton "Abrir en Ajustes".

`Sources/CompanionUI/en.lproj/Localizable.strings` y `es.lproj/Localizable.strings`: claves `island.setting.*` (origen, cerrar, abrir en Ajustes, anuncio).

`Sources/CompanionUI/Island/Setting/SettingCardPresenter.swift` (nuevo; `@Observable @MainActor package final class`):
- `init(mainInFront:, revealPage:, report:, sleep:)`.
- Estado y callbacks: `current`, `onFinished`, `onBridgeDismissed`.
- `present(_:origin:) -> ShowSettingReply`:
  - `never`: rechazo;
  - clase pagina o ventana delante: `revealPage` y `.openedPage` (para el puente, Q1);
  - si no: la cola decide.
- `finish(_:)`: informa `report(.setting)`, llama a `onFinished` y, si es del puente y `dismissed`, a `onBridgeDismissed`.
- `hold(_:)`: el puntero o el foco pausan el reloj.
- `dropBridgeRequests()`.
- `takesKeyboard(origin:, panelKey:) -> Bool`.
- `extension Notification.Name { static let companionRevealSetting }`.

`IslandView.swift`: parametro `settings: SettingCardPresenter? = nil`; pasa `setting: settings?.current` a `IslandState.from`.

`IslandView+Status.swift`: primera rama `if let setting = state.setting { settingCard(setting) }`.

`CompanionRootView.swift`: escucha `companionRevealSetting`, usa `SettingsInventory.reveal` y abre Ajustes con `settingsReveal`. Si el id es desconocido, registra en el log y no abre nada.

`SettingsView.swift`: `reveal: Binding<String?>`. Al cambiar, ejecuta el mismo camino que `jump` y lo vuelve a nil.

### App

- `CompanionMain.swift`:
  - propiedad `var settingCards: SettingCardPresenter?`;
  - el puente se compone con `CompositeParentTools([bridgeTools(...), SettingToolRunner(surface: relay, origin: { .bridge(client: clientBox.value) })])`, y se conecta `settingCards?.onBridgeDismissed`. Asignarlo donde existan los dos objetos; el orden de creacion no esta verificado.
- `CompanionMainSensing.swift`:
  - crea `SettingSurfaceRelay` y `SettingToolRunner(origin: { .conversation })`;
  - `conversationTools = CompositeParentTools([browserHost.conversationTools(...), settingTools])`;
  - expone `settingRelay` en `SensingAndModel`.
- `CompanionMainWindow.swift`:
  - crea el presentador con `mainInFront: { holdSettings.mainInFront }`, `revealPage: { showMain(); post(.companionRevealSetting, id.rawValue) }` y `report: sessionModel.report`;
  - lo conecta al relay y lo pasa a `IslandView`;
  - `onFinished`: si `changed` y `sessionModel.projection.voice != .off`, llama a `voicePort.session?.announceSettingChanged(language:)`.
- `BridgeHost.swift`: `onHello` llena el `clientBox`; `settingDismissed()` llama a `session.recordSettingDismissal()`; si el estado pasa a cerrado, llama a `onClosed` y este a `dropBridgeRequests`.

## 4. Plan TDD (primero RED)

Solo en los targets actuales: `CompanionCoreTests`, `CompanionServicesTests`, `CompanionUITests`, `CompanionIntegrationTests` y los `*TestSupport`. Antes de cada PR se confirma en main en que target vive cada archivo que se extiende.

**Core**, `Tests/CompanionCoreTests/SettingIDTests.swift`:
- `rawValuesArePageDotName`
- `islandListMatchesD1`
- `pageListMatchesD1AndD9`
- `neverListHoldsKeysLendHandsAndAttachments`
- `elevenLabsBrowserAndWelcomeArePage`
- `noSpeechSpeedID`

**Core**, `Tests/CompanionCoreTests/ShowSettingContractTests.swift`:
- `wireNameIsShowSettingInBothLanguages`
- `schemaEnumListsOnlyIslandAndPageIDs`
- `schemaHasOnlyIDAndNoExtraProperties`
- `encodeChatNeverMarksStrictOnRawSchema`
- `parseRejectsMissingNonStringAndExtraKeys`
- `parseUnknownIsUnknownSetting`
- `parseNeverIsNotSurfaceable`
- `invalidArgsNeverEchoesArguments`
- `outcomeTargetIsIDAndOutputNeverClaimsChange`

**Core**, `Tests/CompanionCoreTests/SettingCardQueueTests.swift`:
- `firstRequestIsShown`
- `conversationReplacesConversationCard`
- `bridgeWithCardOpenIsQueued`
- `bridgeNeverReplacesUsersCard`
- `usersRequestOverBridgeCardRequeuesItFirst`
- `fullQueueAnswersBusy`
- `finishShowsNextInOrder`
- `dropBridgeRemovesShownAndQueued`
- `islandStateHidesSettingWhileApprovalPending`
- `islandStateHidesSettingWithMainInFront`
- `islandStateSettingIsCardSize`
- `islandStateSettingWaitsWhileListening`

**Core**, `Tests/CompanionCoreTests/IslandSettingEventTests.swift`:
- `settingLineNamesIDAndOutcomeInEsAndEn`
- `settingLineNeverCarriesAValue`
- `repeatedSettingEventFoldsUntilDelivered`

**Core**, `Tests/CompanionCoreTests/SettingChangedAnnouncementTests.swift`:
- `spokenLineIsListoAndDone`
- `instructionAsksForThatWordOnly`
- `noSummarySource`

**UI**, `Tests/CompanionUITests/SettingIDInventoryTests.swift`:
- `everyOptionAndPanelHasAUniqueID`
- `everyNonExtraIDAppearsOnceInInventory`
- `everyIDPageIsASettingsTab`
- `everyIslandIDHasTitleInBothCatalogsAndNoJargon`, que reusa la lista `forbidden` de `SettingsParityTests`
- `revealOfUnknownIsNilNeverGeneral`
- `rowKeyMapsToSettingIDForAccessibility`

**UI**, `Tests/CompanionUITests/SettingWriterTests.swift`. Guarda y restaura cada clave de `UserDefaults.standard` que toca; verificar si hay un helper existente.
- `volumeWriteKeepsOtherVoiceFields`
- `dictationKeyWriteKeepsVolume`
- `languageWritePostsLanguageDidChange`
- `soundsWriteSetsBothSoundPrefs`
- `nameWriteTouchesOnlyNameAndPostsProfileDidChange`
- `vocabularyAddStartsFromFreshText`
- `writerRefusesPageAndNeverIDs`
- `writerIsCalledOnlyFromCardAndVoiceSection` (escaneo de fuente, R8)

**UI**, `Tests/CompanionUITests/IslandSettingCardTests.swift`:
- `controlKindCoversEveryIslandID`
- `languageChoicesAreSystemEnglishSpanish`
- `bridgeOriginSaysDeclaredName`
- `announcementIsTitleAndSubtitle`
- `clicksInsideDwellAreIgnored`
- `returnCommitsEscapeCancels`

**UI**, `Tests/CompanionUITests/SettingCardPresenterTests.swift`:
- `islandIDWithMainBehindIsShown`
- `mainInFrontRevealsPageAndAnswersOpenedPage`
- `pageIDRevealsPage`
- `bridgePageIDWithMainBehindShowsOpenButton` (Q1)
- `changedReportsEventAndCallsOnFinished`
- `idleLifetimeExpiresWithInjectedSleep`
- `holdPausesExpiry`
- `bridgeDismissedCallsOnBridgeDismissed`
- `bridgeExpiredDoesNot`
- `dropBridgeRequestsExpiresWithoutCounting`
- `takesKeyboardOnlyFromKeyPanelAndNeverFromBridge`

**Services**, `Tests/CompanionServicesTests/SettingToolRunnerTests.swift`. Usa un `SettingSurfacing` falso privado.
- `offeredWithoutHandsAndWithSelfInFront`, en composicion con `ParentToolRunner` sin manos
- `unknownIDPresentsNothing`
- `neverIDPresentsNothing`
- `needsNoSheet`
- `unwiredRelayIsNotAvailable`
- `bridgeRunnerTagsDeclaredClient`
- `runnerAndCoreSourcesNeverNamePreferences` (escaneo de fuente, R8)

**Services**, `Tests/CompanionServicesTests/BridgeSettingDismissalTests.swift`:
- `threeDismissalsInTenMinutesCoolTheCaller`
- `reconnectDoesNotResetTheCount`
- `expiredCardsDoNotCount`
- `helloReportsSanitizedClientName`
- `showSettingDrawsFromWriteBudget`

**Services**, `BridgeAllowlistTests.swift` (edicion):
- `expected` gana `show_setting`;
- la union del guard gana `SettingToolRunner.specs`;
- test nuevo: `showSettingOpensSessionSheetOnFirstCall`.

**Integracion**, `Tests/CompanionIntegrationTests/ShowSettingFlowTests.swift`:
- `chatCallRaisesCardThroughComposite`
- `repliesNeverCarryNameOrCity`, con `UserProfile` = "Ana Prueba"/"Oaxaca", guardado y restaurado
- `approvalPendingHidesCardThenReturns`
- `changedReachesNextTurnContext`

**Integracion**, `Tests/CompanionIntegrationTests/SettingChangedVoiceTests.swift`, con los fakes de sesion de voz que existan en main:
- `classicSaysListoOnce`
- `droppedWhenVoiceClosed`

**Deben seguir en verde sin editarse:** `SettingsParityTests`, `LocalizedTests` (paridad de claves), `BridgeReadBudgetTests`, `BrowserToolScopeTests`.

## 5. Restricciones y PRs (en orden)

Reglas para todos los PR:
- Comentarios solo con el POR QUE.
- Sin dependencias nuevas.
- Sin tocar configs raiz.
- `CHANGELOG.md` en espanol, con fecha del dia del merge, en `[Unreleased] / Added`.
- El brief APROBADO va en cada rama.
- Cada PR se puede mergear solo y deja la app como estaba hasta que se enciende.

**No cabe en "max 3 PRs por sesion":** son 14 PRs, unas cinco sesiones. No se agrupa mas, porque varios PRs ya estan en 5 archivos.

| PR | Archivos | Depende de |
|---|---|---|
| PR-0 Docs | esta spec, el brief, CHANGELOG (3) | nada |
| PR-1 Ids y contrato | `SettingID.swift`, `ShowSetting.swift`, `SettingIDTests`, `ShowSettingContractTests`, CHANGELOG (5) | PR-0 |
| PR-2 Cola e isla | `SettingCardQueue.swift`, `IslandState.swift`, `SettingCardQueueTests`, CHANGELOG (4) | PR-1 |
| PR-3 Metadato al modelo | `IslandEvents.swift`, `ContextBlock.swift`, `IslandSettingEventTests`, CHANGELOG (4) | PR-1 |
| PR-4 Inventario con id | `SettingsInventory.swift`, `SettingsPieces.swift`, `SettingIDInventoryTests`, CHANGELOG (4) | PR-1 |
| PR-5 Un solo escritor | `SettingWriter.swift`, `SettingsPages.swift`, `SettingsVoiceSection.swift`, `SettingWriterTests`, CHANGELOG (5) | PR-4 |
| PR-6 Tarjeta | `IslandSettingCard.swift`, en y es `Localizable.strings`, `IslandSettingCardTests`, CHANGELOG (5) | PR-5 |
| PR-7 Tool | `SettingToolRunner.swift`, `SettingSurfaceRelay.swift`, `SettingToolRunnerTests`, CHANGELOG (4) | PR-1 |
| PR-8 Presentador e isla | `SettingCardPresenter.swift`, `IslandView.swift`, `IslandView+Status.swift`, `SettingCardPresenterTests`, CHANGELOG (5) | PR-2, PR-3, PR-6 |
| PR-9 Pagina resaltada | `CompanionRootView.swift`, `SettingsView.swift`, CHANGELOG (3) | PR-4, PR-8 |
| PR-10 "Listo" | `Escalation.swift`, `VoiceSession+Announcements.swift`, `SettingChangedAnnouncementTests`, `SettingChangedVoiceTests`, CHANGELOG (5) | nada |
| PR-11 Encender en chat y voz | `CompanionMain.swift`, `CompanionMainSensing.swift`, `CompanionMainWindow.swift`, `ShowSettingFlowTests`, CHANGELOG (5) | PR-7 a PR-10 |
| PR-12 Puente: enfriamiento y nombre | `BridgeSession.swift`, `BridgePolicy.swift`, `BridgeSettingDismissalTests`, CHANGELOG (4) | PR-1 |
| PR-13 Encender en el puente | `DeliverableTools.swift`, `BridgeAllowlistTests.swift`, `CompanionMain.swift`, `BridgeHost.swift`, CHANGELOG (5) | PR-11, PR-12 |

**Fuera de alcance:**
- la velocidad de voz (otra spec);
- el metadato posterior al puente: el protocolo no empuja eventos, y las tools `companion_*` son de la spec `self-qa-inspeccion`;
- el shim `companion-mcp` (otro repo);
- grants, destinos y modos de 20d, hasta que existan;
- campos de varias lineas en la isla.

## 6. Riesgos y preguntas abiertas

**Preguntas para Karen** (default entre parentesis):
- **Q1 (bloquea la firma).** Un agente pide un ajuste de clase pagina con la ventana principal detras. Abrir la ventana activa la app y le quita el teclado a lo que ella hacia, lo que choca con D5. (Default: tarjeta en la isla con un solo boton "Abrir en Ajustes"; respuesta `shown`.) Un pedido por voz de clase pagina si abre la pagina, como dice D4, porque ella lo pidio.
- **Q2.** La cola necesita una respuesta inmediata que D3 no tiene. (Default: `queued`, con tope de 3 en cola; pasado el tope, `busy`.)
- **Q3.** Hay ids sin encaje en D1 o en "1:1 con el inventario". `general.talk` ("Hablar", sin control): ¿que clase? (Default: pagina.) Y los tres extras que no son filas: `voice.volume` (isla), `vocabulary.add` (isla) y `voice.elevenLabs` (pagina). (Default: tabla `extras`.)
- **Q4.** ¿"Listo" tambien en un chat escrito sin la voz abierta? (Default: solo si `projection.voice != .off`.)
- **Q5.** La usuaria pide un ajuste mientras se ve uno del puente. (Default: el suyo pasa delante y el del puente vuelve al frente de la cola sin contar como cierre.)
- **Q6.** Vida de la tarjeta: 20 s sin puntero ni foco, ASSUMPTION del brief. Probar 10, 20 y 30 s en A19.
- **Q7.** ¿El shim `companion-mcp` reenvia la lista de `hello` o la fija? Si la fija, hace falta un cambio en ese repo.
- **Q8.** Mientras ella habla (hold) la barra gana y la tarjeta espera; mientras Companion piensa o habla, la tarjeta se ve. Confirmar en A19.

**Riesgos y mitigaciones:**
- **Panel no activante con un campo de texto.** La isla ya escribe desde su campo (`IslandChrome.swift:223`); la tarjeta solo pide el foco con el panel ya key, y nunca desde el puente.
- **`AccessibilityFocusState` sin probar en un panel que no es key.** Se valida en A19 con Accessibility Inspector; si falla, queda solo el anuncio.
- **Las paginas abiertas pisan cambios.** Lo cubre PR-5, que ademas corrige un bug parecido de hoy con el volumen de la isla y la pagina de Voz (`SettingsVoiceSection.swift:59-64`).
- **Voz e idioma pueden no oirse hasta la siguiente sesion,** porque la Config se arma al abrirla (`UserPreferences.swift:216-218`). ASSUMPTION del brief; se verifica en A19.
- **La isla puede no repintar en el idioma nuevo sin un contador.** ASSUMPTION; si falla, el presentador sube un contador al recibir `companionLanguageDidChange`.
- **Doble confirmacion** (el modelo dice "listo" antes del cambio): la descripcion y el `output` lo prohiben; si aparece en vivo, se filtra con `Acknowledgement.isNeeded`.
- **El nombre del cliente no es una identidad** (`BridgeSession+Calls.swift:85-92`). Por eso la tarjeta lo marca como declarado.
- **Tests que escriben en `UserDefaults.standard`.** Se guardan y restauran las claves.
- **El tope de 4 eventos en `ContextBlock`:** los eventos de ajuste pueden desplazar otros. Se acepta.
- **Sin verificar:**
  - que `SettingsSwitch` (`SettingsPieces.swift:148`) se vea sobre la tinta de la isla;
  - que metodos de `ParentToolExecuting` tienen default;
  - en que orden se crean `bridgeHost` y la ventana en `AppDelegate`.
