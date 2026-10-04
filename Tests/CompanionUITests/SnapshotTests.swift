import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// Wave 16c-16e visual review (spec 16c §3): renders the island, the welcome
// and Settings to PNG, light and dark, to compare against Incredible. Runs
// only with COMPANION_SNAPSHOTS=<dir>; the suite never writes files.

@Test @MainActor func uiSnapshots() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try await Localized.scoped(to: .es) {
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            for (name, view) in await islandStates() {
                // The island is born closed and opens through move()'s async
                // animation; a one-pass ImageRenderer photographs frame zero
                // (just the notch). It needs a live host that settles first.
                try await saveLive(view, scheme: scheme, size: CGSize(width: 640, height: 420),
                                   to: out, "island-\(name)-\(tag)")
            }
            for step in WelcomeStep.allCases {
                try save(await welcome(step), scheme: scheme, size: CGSize(width: 720, height: 640), to: out,
                         "welcome-\(step.rawValue)-\(step)-\(tag)")
            }
            for tab in SettingsTab.allCases {
                try save(await settings(tab), scheme: scheme, size: CGSize(width: 780, height: 760), to: out,
                         "settings-\(tab.rawValue)-\(tag)")
            }
        }
    }
}

@MainActor func island(
    _ chat: ChatViewModel, composing: Bool = false, updates: UpdateState? = nil
) -> AnyView {
    let voice = VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter())
    let hold = HoldSettingsModel(permission: FakeAccessibility(trusted: true))
    hold.holdLearned = true
    return AnyView(IslandView(
        chat: chat, voice: voice, hold: hold, onShowMain: {}, onSize: { _, _ in }, updates: updates))
}

@MainActor private func islandStates() async -> [(String, AnyView)] {
    var states: [(String, AnyView)] = []
    let hover = chat()
    await hover.appendAssistant("## Vuelos a Lima\n\nEl más barato sale el martes por 3.200 MXN.")
    await hover.appendAssistant("Listo, abrí Safari en tu bandeja de entrada.")
    hover.session.send(.hoverEntered)
    states.append(("hover", island(hover)))

    let listening = chat()
    listening.session.send(.pressed)
    listening.session.send(.partialTranscript("abre el correo de Ana y"))
    states.append(("listening", island(listening)))

    let done = chat()
    await done.appendAssistant("## Vuelos a Lima\n\nEl más barato sale el martes por 3.200 MXN.")
    done.session.send(.typedSubmitted)
    done.session.send(.typedReplyFinished)
    states.append(("done", island(done)))

    let nothing = chat()
    nothing.session.send(.pressed)
    nothing.session.send(.released)
    nothing.session.send(.heardNothing)
    states.append(("couldntHear", island(nothing)))

    let keyless = chat()
    keyless.session.send(.voice(TurnSnapshot(state: .error, failure: .noProviders)))
    states.append(("error", island(keyless)))

    // 16m-4: the dictation result and the four system notices.
    let dictation = chat()
    dictation.session.send(.pressed)
    dictation.session.send(.dictating(app: "Slack"))
    dictation.session.send(.released)
    dictation.session.send(.dictated(
        app: "Slack", text: "Te mando el resumen en cuanto termine la revisión, sin cambios de última hora."))
    states.append(("dictation", island(dictation)))

    let limit = chat()
    limit.session.send(.voice(TurnSnapshot(state: .error, failure: .quotaExceeded)))
    states.append(("notice-limit", island(limit)))

    let permission = chat()
    permission.session.send(.voice(TurnSnapshot(state: .error, failure: .micDenied)))
    states.append(("notice-permission", island(permission)))

    let diagnostic = chat()
    diagnostic.session.send(.voice(TurnSnapshot(state: .error, failure: .networkUnavailable)))
    states.append(("notice-diagnostic", island(diagnostic)))

    let updates = UpdateState(checkNow: { nil })
    updates.found(.init(tag: "v0.9.0", pageURL: URL(fileURLWithPath: "/tmp/release")))
    states.append(("notice-update", island(chat(), updates: updates)))

    states += await choiceStates()

    let asking = chat()
    asking.session.send(.job(.started(goal: "ordenar Descargas")))
    asking.session.send(.job(.approvalRequested(ApprovalRequest(
        requestId: "r1", toolName: "Bash", summary: "mv ~/Downloads/*.pdf ~/Documents", inputJSON: "{}"))))
    states.append(("approval", island(asking)))
    return states
}

private final class StillDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { permission != .screenRecording }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

@MainActor private func welcome(_ step: WelcomeStep) async -> AnyView {
    let model = WelcomeModel(devices: StillDevices(), keyReady: { true },
                             defaults: UserDefaults(suiteName: "snap-\(UUID().uuidString)") ?? .standard)
    model.jump(to: step)
    await model.refresh()
    return AnyView(WelcomeView(welcome: model, chat: chat()))
}

/// The sheet's ScrollView does not render offscreen; the pages do, with
/// the sidebar drawn beside them as the sheet lays it out.
@MainActor private func settings(_ tab: SettingsTab) async -> AnyView {
    let welcome = WelcomeModel(devices: StillDevices(), keyReady: { true },
                               defaults: UserDefaults(suiteName: "snap-\(UUID().uuidString)") ?? .standard)
    await welcome.refresh()
    let page: AnyView
    switch tab {
    case .general: page = AnyView(SettingsGeneralPage(accessibility: nil, onLanguageChange: {}))
    case .voice: page = AnyView(SettingsVoiceSection(preview: nil))
    case .vocabulary: page = AnyView(SettingsVocabularyPage())
    case .memory: page = AnyView(SettingsMemoryPage(memory: SnapMemory()))
    case .you: page = AnyView(SettingsYouPage(welcome: welcome))
    case .privacy: page = AnyView(SettingsPrivacyPage(chat: chat(), welcome: welcome))
    case .system:
        page = AnyView(SettingsSystemPage(
            chat: chat(), updates: nil, storageLabel: "12 MB", confirmPurge: .constant(false)))
    }
    return AnyView(HStack(alignment: .top, spacing: Space.none) {
        SettingsSidebar(tab: .constant(tab), query: .constant(""), onPick: { _ in })
            .frame(width: SettingsRailMetrics.width)
        page
            .padding(.leading, SettingsPaneMetrics.leading)
            .padding(.trailing, SettingsPaneMetrics.trailing)
            .padding(.top, SettingsPaneMetrics.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(Semantic.background).environment(DropdownHost()))
}

private struct SnapMemory: MemoryBrowsing {
    func entries() -> [MemoryEntry] {
        [MemoryEntry(id: "sessions/a.md", kind: .session, day: "2026-09-24", text: "## hoy\n- ordenó Descargas"),
         MemoryEntry(id: "notes/b.md", kind: .note, day: "2026-09-01", text: "prefiere respuestas cortas")]
    }
    func forget(_ id: String) throws {}
}

/// Hosts the view in an offscreen window so the full runtime runs — the
/// island's onChange fires, move()'s task opens the shape, contentVisible
/// lands — then captures the settled frame. ImageRenderer cannot do this:
/// it takes one synchronous pass and the island opens asynchronously.
@MainActor func saveLive(
    _ view: AnyView, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) async throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.94))
        .environment(\.colorScheme, scheme)
    // The hosting view's body evaluates on the run loop, outside this
    // task's Localized.scoped pin (review 16m: the first live captures came
    // out in English). The process-wide default is what those evaluations
    // read, so it is pinned for the capture and restored after.
    let previous = Localized.language
    Localized.language = { .es }
    defer { Localized.language = previous }
    let host = NSHostingView(rootView: framed)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = host
    // Far outside every screen: hosted (so SwiftUI attaches and animates)
    // without ever being visible.
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    // The open choreography finishes well under a second; the margin is
    // for the content fade that starts after the last shape step.
    try await Task.sleep(for: .seconds(1.5))
    window.displayIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        expect(false, "16c snapshot: \(name) no rindió un bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        expect(false, "16c snapshot: \(name) no rindió PNG")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

@MainActor private func save(
    _ view: AnyView, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.94))
        .environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { return }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

/// 16m-6: the question card open, answered and answered by typing; the two
/// notices with their own grid (consent, sign in); the longest question the
/// caps allow.
@MainActor private func choiceStates() async -> [(String, AnyView)] {
    let fence = """
    ¿Cómo prefieres que lo prepare?

    ```companion:choice
    {"question":"¿Cómo prefieres que lo prepare?","options":[{"label":"Resumen rápido","detail":"Cinco líneas, listo en un minuto"},{"label":"Informe completo","detail":"Con tablas y fuentes"},{"label":"Solo los números"}]}
    ```
    """
    let six = """
    Tengo seis rutas.

    ```companion:choice
    {"question":"¿Qué ruta tomamos para llegar a la oficina de Ana esta tarde, considerando el tráfico de la avenida y la lluvia?","options":[{"label":"Metro línea 1 hasta Insurgentes y caminar los últimos diez minutos por la calle principal","detail":"La más barata, pero con el tramo final a pie y bajo la lluvia"},"Taxi por la avenida","Bicicleta compartida","Autobús 214","Caminar",{"label":"Llamar a Ana y pedirle que baje"}]}
    ```
    """
    var states: [(String, AnyView)] = []
    let open = chat()
    await open.appendAssistant(fence)
    open.session.send(.hoverEntered)
    states.append(("choice-open", island(open)))

    let picked = chat()
    await picked.appendAssistant(fence)
    await picked.appendUser("Informe completo")
    picked.session.send(.hoverEntered)
    states.append(("choice-picked", island(picked)))

    let typed = chat()
    await typed.appendAssistant(fence)
    await typed.appendUser("mejor otra cosa")
    typed.session.send(.hoverEntered)
    states.append(("choice-passed", island(typed)))

    let crowded = chat()
    await crowded.appendAssistant(six)
    crowded.session.send(.hoverEntered)
    states.append(("choice-six", island(crowded)))

    // The whole gallery is built before the first picture is taken (~1 min),
    // so a notice that fades on its own must have a clock that never fires.
    func steady() -> ChatViewModel {
        ChatViewModel(
            chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
            store: MemoryConversationStore(), config: Config(),
            session: SessionModel(jobs: nil, approvals: nil, sleep: { _ in
                try await Task.sleep(for: .seconds(3600))
            }))
    }
    let connect = steady()
    connect.session.send(.connectAppSuggested(slug: "notion", name: "Notion"))
    states.append(("notice-consent", island(connect)))

    let signIn = steady()
    signIn.session.send(.signInAppSuggested(slug: "gmail", name: "Gmail"))
    states.append(("notice-signin", island(signIn)))
    return states
}
