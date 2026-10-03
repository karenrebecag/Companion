import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionUITestSupport
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Spec self-qa-inspeccion, PR-5: the island and the window write the mirror
// as they paint. Hosted for real, because the writes live in `onChange`,
// which only runs inside a live SwiftUI hierarchy.

private final class NoDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { true }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { true }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

/// An offscreen window so SwiftUI attaches the view and runs its `onChange`
/// handlers; the caller closes it.
@MainActor private func hosted(_ view: some View) -> NSWindow {
    let host = NSHostingView(rootView: view.frame(width: 800, height: 600))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    window.orderBack(nil)
    host.layoutSubtreeIfNeeded()
    return window
}

@Test @MainActor func islandViewPaintsTheMirrorAsItChanges() async {
    let mirror = InspectionMirror()
    let model = chat()
    let view = IslandView(
        chat: model, voice: VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter()),
        hold: HoldSettingsModel(permission: FakeAccessibility(trusted: true)),
        onShowMain: {}, onSize: { _, _ in }, mirror: mirror)
    let window = hosted(view)
    defer { window.orderOut(nil) }
    await pumpUntil("isla: el primer pintado llega al espejo") { mirror.island != nil }
    let first = mirror.island?.state
    model.followUp = "seguir con el informe"
    await pumpUntil("isla: un cambio de estado vuelve a escribir el espejo") { mirror.island?.state != first }
    expectEq(mirror.island?.state, view.state, "isla: el espejo guarda lo que la vista pinta")
    // Same size, different line: a write keyed on anything narrower than
    // the whole state would miss this one.
    let size = mirror.island?.state.size
    model.followUp = "otra tarea"
    await pumpUntil("isla: un cambio de linea sin cambio de tamano tambien llega") {
        mirror.island?.state.line == .followUp("otra tarea")
    }
    expectEq(mirror.island?.state.size, size, "isla: el tamano no cambio, solo la linea")
}

@Test @MainActor func rootViewWritesPageAndSettingsTabToTheMirror() async {
    let mirror = InspectionMirror()
    let welcome = WelcomeModel(
        devices: NoDevices(), keyReady: { true },
        defaults: UserDefaults(suiteName: "mirror-\(UUID().uuidString)") ?? .standard)
    let view = CompanionRootView(
        chat: chat(), voice: VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter()),
        welcome: welcome, mirror: mirror)
    let window = hosted(view)
    defer { window.orderOut(nil) }
    await pumpUntil("ventana: la pantalla inicial llega al espejo") {
        mirror.screen == InspectedScreen(settingsOpen: false, settingsTab: nil, page: "home")
    }
    NotificationCenter.default.post(name: .companionOpenSettings, object: SettingsTab.privacy.rawValue)
    await pumpUntil("ventana: abrir Ajustes en una pestana llega al espejo") {
        mirror.screen == InspectedScreen(settingsOpen: true, settingsTab: "privacy", page: "home")
    }
    // Settings already open: only the tab changes this time.
    NotificationCenter.default.post(name: .companionOpenSettings, object: SettingsTab.voice.rawValue)
    await pumpUntil("ventana: cambiar de pestana con Ajustes abierto llega al espejo") {
        mirror.screen?.settingsTab == "voice"
    }
    NotificationCenter.default.post(name: .companionOpenApps, object: nil)
    await pumpUntil("ventana: cambiar de pagina llega al espejo") { mirror.screen?.page == "apps" }
}
