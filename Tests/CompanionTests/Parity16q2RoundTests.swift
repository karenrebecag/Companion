import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// 16q-2 review round: the location switch wiring and its fail-closed default,
// hostile and ambiguous card answers, restored threads, what the card shows,
// the choice turn's cache refresh, and the feedback attachment hardening.

// MARK: - Location switch (HIGH 1, MEDIUM 3)

private final class SpyCity: UserLocating, @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []
    var reads: Int { lock.withLock { flags.count } }
    var permissionRequests: Int { lock.withLock { flags.filter { $0 }.count } }
    func current(prompting: Bool) async -> UserLocation? {
        lock.withLock { flags.append(prompting) }
        return UserLocation(city: "Fullerton", country: "USA")
    }
}

private final class NoPlaces: PlacesSearching, @unchecked Sendable {
    func search(_ query: String, near: String?) async -> [FoundPlace] { [] }
}

@Test @MainActor func theRootsSwitchReadsTheStoredChannels() throws {
    let name = "q2-round-\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: name), "suite")
    defer { store.removePersistentDomain(forName: name) }
    let saved = ContextPreference.store
    ContextPreference.store = store
    defer { ContextPreference.store = saved }
    ContextPreference.channels = [.focusedApp]
    expect(!ContextPreference.locationChannelOn, "16q-2: sin .location en los canales, el interruptor esta apagado")
    ContextPreference.channels = [.focusedApp, .location]
    expect(ContextPreference.locationChannelOn, "16q-2: con .location, encendido")
}

@Test @MainActor func nearMeThroughTheRootsSwitchNeverReadsTheSystemWhenChannelIsOut() async throws {
    let name = "q2-round-\(UUID().uuidString)"
    let store = try #require(UserDefaults(suiteName: name), "suite")
    defer { store.removePersistentDomain(forName: name) }
    let saved = ContextPreference.store
    ContextPreference.store = store
    defer { ContextPreference.store = saved }
    ContextPreference.channels = [.focusedApp]
    let city = SpyCity()
    let runner = NativeToolRunner(
        workdir: NSTemporaryDirectory(), places: NoPlaces(),
        location: UserLocationSource(manualCity: { "" }, system: city),
        locationChannelOn: { ContextPreference.locationChannelOn })
    _ = try await runner.execute(tool: "find_places", arguments: ["query": "restaurantes cerca"], approved: false)
    expectEq(city.reads, 0, "16q-2: canal fuera, cero lecturas del sistema")
    expectEq(city.permissionRequests, 0, "16q-2: y cero peticiones de permiso")
}

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()

/// Comments out, then: exactly one `locationChannelOn:` in the file and it sits
/// inside the `ParentToolRunner(` call. The pattern lives in
/// conformance/location-wiring.regex, read by this test and by Gate 3.
private func rootWiresTheStoredSwitch(_ source: String, pattern: String) throws -> Bool {
    let bare = source
        .replacingOccurrences(of: "/\\*.*?\\*/", with: "", options: .regularExpression)
        .replacingOccurrences(of: "//[^\n]*", with: "", options: .regularExpression)
    let uses = bare.components(separatedBy: "locationChannelOn:").count - 1
    let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    let range = NSRange(bare.startIndex..., in: bare)
    return uses == 1 && regex.firstMatch(in: bare, range: range) != nil
}

@Test func theCompositionRootPassesTheStoredSwitchNotAConstant() throws {
    // App is an executable target with no test seam: the wiring is pinned as
    // text, and Gate 3 in scripts/gates.sh repeats the check with the same
    // pattern file.
    let pattern = try String(contentsOf: repoRoot.appendingPathComponent("conformance/location-wiring.regex"), encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let real = try String(contentsOf: repoRoot.appendingPathComponent("Sources/CompanionApp/CompanionMainSensing.swift"), encoding: .utf8)
    expect(try rootWiresTheStoredSwitch(real, pattern: pattern),
           "16q-2: la raiz de composicion cablea ContextPreference.locationChannelOn dentro de ParentToolRunner(")

    let good = "let x = ParentToolRunner(\n  workspace: w, hands: f(g(h())),\n  locationChannelOn: { ContextPreference.locationChannelOn })"
    let constant = "let x = ParentToolRunner(\n  workspace: w,\n  locationChannelOn: { true })"
    let hiddenInLine = "let x = ParentToolRunner(\n  workspace: w,\n  // locationChannelOn: { ContextPreference.locationChannelOn }\n  locationChannelOn: { true })"
    let hiddenInBlock = "let x = ParentToolRunner(\n  workspace: w, /* locationChannelOn: { ContextPreference.locationChannelOn } */\n  locationChannelOn: { true })"
    let elsewhere = "let x = ParentToolRunner(workspace: w, locationChannelOn: { true })\nlet y = Other(locationChannelOn: { ContextPreference.locationChannelOn })"
    expect(try rootWiresTheStoredSwitch(good, pattern: pattern), "16q-2: el cableado correcto pasa, con parentesis anidados")
    expect(!(try rootWiresTheStoredSwitch(constant, pattern: pattern)), "16q-2: una constante no pasa")
    expect(!(try rootWiresTheStoredSwitch(hiddenInLine, pattern: pattern)), "16q-2: la cadena en un comentario // no engana al pin")
    expect(!(try rootWiresTheStoredSwitch(hiddenInBlock, pattern: pattern)), "16q-2: ni en un comentario /* */")
    expect(!(try rootWiresTheStoredSwitch(elsewhere, pattern: pattern)), "16q-2: ni la cadena en otra llamada")
}

@Test func theSwitchFailsClosedWhenNobodyWiresIt() async throws {
    let city = SpyCity()
    let source = UserLocationSource(manualCity: { "" }, system: city)
    let native = NativeToolRunner(workdir: NSTemporaryDirectory(), places: NoPlaces(), location: source)
    _ = try await native.execute(tool: "find_places", arguments: ["query": "cafe cerca"], approved: false)
    let parent = ParentToolRunner(workspace: FakeWorkspaceOpener(), places: NoPlaces(), location: source)
    _ = await parent.execute(name: "find_places", argumentsJSON: #"{"query":"cafe cerca"}"#)
    expectEq(city.reads, 0, "16q-2: sin cablear el interruptor, no se lee el sistema (default apagado)")
}

@Test @MainActor func theSettingsCopyIsPinnedInFull() {
    expectEq(Localized.string("settings.context.location.subtitle", language: .es),
             "Tu ciudad acompaña cada pedido mientras esto esté encendido. Apagado, deja de acompañarlos y macOS nunca te pregunta por tu ubicación: una búsqueda de algo cerca usa la ciudad de Ajustes › Tú, y si está vacía te pregunta en qué ciudad buscar.",
             "16q-2 (es): el texto completo de Ajustes")
    expectEq(Localized.string("settings.context.location.subtitle", language: .en),
             "Your city travels with every request while this is on. Off, it stops travelling and macOS never asks for your location: a search for something nearby uses the city in Settings › You, and if that is empty it asks which city to search in.",
             "16q-2 (en): el texto completo de Ajustes")
}

// MARK: - The choice turn refreshes the apps cache (MEDIUM 4)

private final class CountingApps: AppsService, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var accountCalls: Int { lock.withLock { count } }
    func catalog(query: String, after: String?) async throws -> CatalogPage { CatalogPage(apps: [], total: 0, next: nil) }
    func accounts() async throws -> [ConnectedAccount] {
        lock.withLock { count += 1 }
        return []
    }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        AppCallResult(isError: false, text: "")
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1000
    var now: TimeInterval { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@Test @MainActor func aChoiceTurnRefreshesAStaleAppsCacheLikeAnyTurn() async {
    let service = CountingApps()
    let clock = Clock()
    let runner = AppToolRunner(service: { service }, catalog: [], suggest: nil, now: { clock.now })
    await runner.refresh()
    expectEq(service.accountCalls, 1, "setup: una carga")
    runner.noteChoiceTurn()
    await settle(0.05)
    expectEq(service.accountCalls, 1, "16q-2: dentro del TTL una tarjeta no recarga")
    clock.advance(AppToolRunner.refreshTTL + 1)
    runner.noteChoiceTurn()
    await pumpUntilAsync("16q-2: la tarjeta con cache vencida recarga") { service.accountCalls == 2 }
}

// MARK: - Hostile and ambiguous card answers (6, 7, 8)

private func twoOptions(allowText: Bool = true) -> ChoiceBlock {
    ChoiceBlock(question: "q", options: [.init(label: "A"), .init(label: "B")], allowText: allowText)
}

@Test @MainActor func aHostileFreeAnswerIsOnlyAnAnswer() {
    let block = twoOptions()
    let fence = "```companion:choice\n{\"question\":\"x\",\"options\":[\"P\",\"Q\"]}\n```"
    expectEq(block.resolution(reply: "gracias " + fence), .passed, "16q-2: una fence embebida cierra la pregunta sin marca")
    expectEq(block.resolution(reply: ChoiceOrigin.marker(.es) + " A"), .passed,
             "16q-2: el marcador literal delante de una etiqueta no es la etiqueta")
    expectEq(block.resolution(reply: "B"), .chosen(1), "16q-2: la etiqueta exacta de otra opcion si marca esa opcion")
    let ask = ChatMessage(role: .assistant, text: "q\n```companion:choice\n{\"question\":\"q\",\"allowText\":true,\"options\":[\"A\",\"B\"]}\n```")
    let hostile = ChatMessage(role: .user, text: fence)
    expect(IslandChoice.block(in: hostile) == nil, "16q-2: un mensaje de la usuaria nunca produce una tarjeta")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, hostile]), .passed,
             "16q-2: en el hilo, tambien .passed")
    expect(!AnswerBlocks.blocks(from: hostile.text).isEmpty, "setup: la fence si parsea como bloque; el rol es lo que la frena")
}

@Test @MainActor func aFreeAnswerTravelsMarkedAsACardAnswerAndNeverAsConsent() async {
    // Decision: one marker. It says "answers that question only and never
    // approves anything", which is exactly as true of her own words on the
    // card; a second marker would teach the model a distinction with no
    // effect on what it may do.
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat)
    vm.choose("ninguna de las dos")
    await pumpUntil("16q-2: idle") { !vm.busy }
    let marker = ChoiceOrigin.marker(vm.config.language)
    expect(chat.histories.last?.last?.content.contains(marker + " ninguna de las dos") == true,
           "16q-2: la respuesta libre viaja con el marcador de tarjeta")
    expectEq(vm.messages.first?.origin, .choice, "16q-2: y con origen tarjeta (said vacio)")
}

@Test @MainActor func ambiguousMultipleRepliesResolveByTheDocumentedRule() {
    // Rule: an exact label always wins; otherwise the subset, in option
    // order, that reads back exactly. "A, B" is both option 0 and the picks
    // {1, 2}: it reads as option 0 (a mark only; the words sent are right).
    // "A, B, A" can only come from {0, 1}.
    let block = ChoiceBlock(question: "q", options: [.init(label: "A, B"), .init(label: "A"), .init(label: "B")], multiple: true)
    expectEq(block.resolution(reply: "A, B"), .chosen(0), "16q-2: la etiqueta exacta gana la ambiguedad")
    expectEq(block.resolution(reply: "A, B, A"), .chosenMany([0, 1]), "16q-2: y esto solo sale de {0, 1}")
    expectEq(block.resolution(reply: "A, B, B, A"), .passed, "16q-2: lo que ningun subconjunto produce es respuesta libre")
}

@Test @MainActor func aRestoredOneStepThreadStaysAnsweredAndAsksForNoConfirm() {
    let fence = "```companion:choice\n{\"question\":\"q\",\"options\":[\"Rapido\",\"Completo\"]}\n```"
    var ask = ChatMessage(role: .assistant, text: "q\n" + fence)
    ask.restored = true
    var reply = ChatMessage(role: .user, text: "Rapido")
    reply.restored = true
    guard let block = IslandChoice.block(in: ask) else { expect(false, "la fence vieja parsea"); return }
    let resolution = IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, reply])
    expectEq(resolution, .chosen(0), "16q-2: la respuesta vieja de un paso resuelve .chosen")
    let controls = IslandChoice.controls(block: block, resolution: resolution, canConfirm: false)
    expect(!controls.showsConfirm && !controls.showsOwnAnswer, "16q-2: y no pide Confirmar")
}

// MARK: - What the card shows (9)

@Test @MainActor func theCardShowsConfirmAndTheOwnAnswerOnlyWhileOpen() {
    let plain = twoOptions(allowText: false)
    let free = twoOptions(allowText: true)
    let open = IslandChoice.controls(block: plain, resolution: .open, canConfirm: false)
    expect(open.showsConfirm && !open.confirmEnabled, "16q-2: abierta, Confirmar se ve y esta apagado sin seleccion")
    expect(IslandChoice.controls(block: plain, resolution: .open, canConfirm: true).confirmEnabled,
           "16q-2: con seleccion, Confirmar se enciende")
    expect(!open.showsOwnAnswer, "16q-2: sin allowText no hay campo")
    expect(IslandChoice.controls(block: free, resolution: .open, canConfirm: false).showsOwnAnswer, "16q-2: con allowText, campo")
    for done in [ChoiceBlock.Resolution.chosen(0), .chosenMany([0, 1]), .passed] {
        let controls = IslandChoice.controls(block: free, resolution: done, canConfirm: true)
        expect(!controls.showsConfirm && !controls.showsOwnAnswer && !controls.confirmEnabled,
               "16q-2: respondida (\(done)), ni Confirmar ni campo, aunque quede seleccion")
    }
}

// MARK: - Feedback attachments (2, 5, LOW)

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test @MainActor func aSymlinkAFolderOrAPackageIsNotAFileSheChose() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = dir.appendingPathComponent("secret.txt")
    try Data("x".utf8).write(to: text)
    let link = dir.appendingPathComponent("shot.png")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: text)
    let folder = dir.appendingPathComponent("x.png", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let real = dir.appendingPathComponent("real.png")
    try Data(count: 8).write(to: real)
    let live = SystemFeedbackAttachments()
    expect(!live.isRegularFile(link), "16q-2: un symlink no es un archivo suyo")
    expect(!live.isRegularFile(folder), "16q-2: una carpeta llamada x.png tampoco")
    expect(live.isRegularFile(real), "16q-2: un archivo normal si")
    expect(live.isImage(real), "16q-2: el tipo sale del sistema, no solo de la extension")
    expect(!live.isImage(text), "16q-2: un texto no es imagen")
}

@Test @MainActor func theModelRefusesWhatIsNotARegularFile() async {
    let attachments = FakeRoundAttachments()
    let link = URL(fileURLWithPath: "/Users/k/shot.png")
    attachments.sizes[link] = 10
    attachments.notRegular = [link]
    attachments.chosen = [[link]]
    let feedback = FeedbackModel(grabber: nil, delivery: RoundDelivery(), attachments: attachments)
    await feedback.addFiles()
    expect(feedback.captures.isEmpty, "16q-2: un symlink no entra")
    expectEq(feedback.note, Localized.string("feedback.note.unreadable"), "16q-2: y se dice")
}

@Test @MainActor func aFailedPasteIsNotReportedAsAnEmptyClipboard() {
    let attachments = FakeRoundAttachments()
    attachments.pasted = [.empty, .failed, .tooBig]
    let feedback = FeedbackModel(grabber: nil, delivery: RoundDelivery(), attachments: attachments)
    feedback.addPasted()
    expectEq(feedback.note, Localized.string("feedback.note.noPaste"), "16q-2: vacio dice vacio")
    feedback.addPasted()
    expectEq(feedback.note, Localized.string("feedback.note.pasteFailed"), "16q-2: un fallo al escribir dice que fallo")
    expect(feedback.note != Localized.string("feedback.note.noPaste"), "16q-2: distinto de vacio")
    feedback.addPasted()
    expectEq(feedback.note, Localized.string("feedback.note.tooBig"), "16q-2: uno demasiado grande dice el tope")
    expect(feedback.captures.isEmpty && attachments.discarded.isEmpty, "16q-2: nada entro y nada que borrar")
    for language in [AppLanguage.en, .es] {
        expect(Localized.string("feedback.note.pasteFailed", language: language) != "feedback.note.pasteFailed",
               "16q-2 (\(language)): la nota existe")
    }
}

@Test @MainActor func pastingAfterTheModalClosedReadsNothing() {
    let attachments = FakeRoundAttachments()
    attachments.pasted = [.image(URL(fileURLWithPath: "/tmp/companion-feedback-paste/1.png"))]
    let feedback = FeedbackModel(grabber: nil, delivery: RoundDelivery(), attachments: attachments)
    feedback.cancel()
    feedback.addPasted()
    expectEq(attachments.clipboardReads, 0, "16q-2: cerrado el modal, ni se lee el portapapeles")
    expect(feedback.captures.isEmpty, "16q-2: y no entra nada")
}

@Test @MainActor func pastingWhileThePickerIsOpenKeepsTheLimit() async {
    let attachments = FakeRoundAttachments()
    attachments.delay = .milliseconds(120)
    let files = (1 ... 3).map { URL(fileURLWithPath: "/Users/k/\($0).png") }
    for url in files { attachments.sizes[url] = 10 }
    let pasted = URL(fileURLWithPath: "/tmp/companion-feedback-paste/1.png")
    attachments.sizes[pasted] = 10
    attachments.chosen = [files]
    attachments.pasted = [.image(pasted)]
    let feedback = FeedbackModel(grabber: nil, delivery: RoundDelivery(), attachments: attachments)
    async let picker: Void = feedback.addFiles()
    await pumpUntilAsync("picker abierto") { attachments.pickerOpened == 1 }
    feedback.addPasted()
    await picker
    expectEq(feedback.captures.count, 3, "16q-2: pegar con el selector abierto no pasa del tope")
    expect(feedback.captures.contains(pasted) && Set(feedback.captures).count == 3, "16q-2: la pegada se queda y sin repetidos")
}

@Test @MainActor func aPasteBiggerThanTheCapIsRefusedBeforeItIsWritten() {
    expect(SystemFeedbackAttachments.fits(pngByteCount: FeedbackDraft.maxCaptureBytes), "16q-2: 4 MB caben")
    expect(!SystemFeedbackAttachments.fits(pngByteCount: FeedbackDraft.maxCaptureBytes + 1), "16q-2: un byte mas, no se escribe")
}

@Test @MainActor func thePasteFolderIsPrivateEvenIfItAlreadyExisted() throws {
    let dir = try tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
    try SystemFeedbackAttachments(directory: dir).prepareDirectory()
    let mode = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
    expectEq(mode, 0o700, "16q-2: una carpeta que ya existia con 0755 queda en 0700")
}

private final class RoundDelivery: FeedbackDelivering, @unchecked Sendable {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery { .opened }
}

private final class FakeRoundAttachments: FeedbackAttaching, @unchecked Sendable {
    private let lock = NSLock()
    var chosen: [[URL]] = []
    var pasted: [PastedImage] = []
    var sizes: [URL: Int] = [:]
    var notRegular: Set<URL> = []
    var delay: Duration?
    private(set) var pickerOpened = 0
    private(set) var clipboardReads = 0
    private(set) var discarded: [URL] = []
    @MainActor func chooseImages() async -> [URL] {
        let next = lock.withLock { () -> [URL] in
            pickerOpened += 1
            return chosen.isEmpty ? [] : chosen.removeFirst()
        }
        if let delay { try? await Task.sleep(for: delay) }
        return next
    }
    @MainActor func pastedImage() -> PastedImage {
        lock.withLock {
            clipboardReads += 1
            return pasted.isEmpty ? .empty : pasted.removeFirst()
        }
    }
    func isRegularFile(_ url: URL) -> Bool { lock.withLock { !notRegular.contains(url) } }
    func byteSize(of url: URL) -> Int? { lock.withLock { sizes[url] } }
    func isImage(_ url: URL) -> Bool { true }
    func discard(_ url: URL) { lock.withLock { discarded.append(url) } }
}

// MARK: - ParentToolRunner keeps the switch when it builds the native lookup

@Test func theParentsNearMeSearchUsesTheSystemCityWhenTheChannelIsOn() async {
    let system = SpyCity()
    let places = RecordingNear()
    let runner = ParentToolRunner(
        workspace: FakeWorkspaceOpener(), places: places,
        location: UserLocationSource(manualCity: { "" }, system: system),
        locationChannelOn: { true })
    let outcome = await runner.execute(name: "find_places", argumentsJSON: #"{"query":"restaurantes cerca"}"#)
    expect(outcome.ok, "16q-2 padre: con el canal encendido hay resultados")
    expectEq(system.permissionRequests, 1, "16q-2 padre: encendido, la busqueda puede pedir permiso una vez")
    expectEq(places.nears, ["Fullerton, USA"], "16q-2 padre: y busca en la ciudad del sistema")
}

private final class RecordingNear: PlacesSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String?] = []
    var nears: [String?] { lock.withLock { seen } }
    func search(_ query: String, near: String?) async -> [FoundPlace] {
        lock.withLock { seen.append(near) }
        return [FoundPlace(name: "Los Arcos", address: "Centro", lat: 18.9, lng: -99.2)]
    }
}
