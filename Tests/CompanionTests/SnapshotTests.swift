import AppKit
import CompanionCore
@testable import CompanionUI
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
                try save(view, scheme: scheme, size: CGSize(width: 520, height: 420), to: out, "island-\(name)-\(tag)")
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

@MainActor private func chat() -> ChatViewModel {
    ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: Config())
}

@MainActor private func island(_ chat: ChatViewModel, composing: Bool = false) -> AnyView {
    let voice = VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter())
    let hold = HoldSettingsModel(permission: FakeAccessibility(trusted: true))
    hold.holdLearned = true
    return AnyView(IslandView(chat: chat, voice: voice, hold: hold, onShowMain: {}, onSize: { _, _ in }))
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
    case .you: page = AnyView(SettingsYouPage())
    case .privacy: page = AnyView(SettingsPrivacyPage(chat: chat(), welcome: welcome))
    case .system:
        page = AnyView(SettingsSystemPage(
            chat: chat(), updates: nil, welcome: welcome, storageLabel: "12 MB",
            confirmPurge: .constant(false), onClose: {}))
    }
    return AnyView(HStack(alignment: .top, spacing: Space.none) {
        SettingsSidebar(tab: .constant(tab), query: .constant(""), onPick: { _ in })
            .frame(width: SettingsOverlayMetrics.sidebar)
        page.padding(Space.x6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
