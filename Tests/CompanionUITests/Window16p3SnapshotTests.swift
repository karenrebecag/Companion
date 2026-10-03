import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import SwiftUI
import Testing

// Wave 16p-3: the window screens the line-height roles touch (Home hero, the
// app panel, the connecting sheet) had no gallery entry. Same harness rule as
// uiSnapshots: only with COMPANION_SNAPSHOTS=<dir>.
//
// This is a gallery for a human to read, not a measurement: the line heights
// are asserted in Pins16p3Tests.testRenderedLineHeightIsTheMeasuredRatio. It
// still refuses to fail silently, so an empty gallery is never mistaken for a
// clean one.

@Test @MainActor func windowSnapshots16p3() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let app = CatalogApp(
        slug: "slack", name: "Slack",
        description: "Send messages, search channels and keep a team in the loop without leaving the conversation.",
        icon: nil)
    let actions = [
        AppAction(slug: "read", name: "Read channel",
                  description: "Reads the latest messages of a channel so the answer can quote them.", group: .leer),
        AppAction(slug: "post", name: "Post message",
                  description: "Writes a message in a channel or a direct conversation on your behalf.",
                  group: .crearYCambiar),
    ]
    try await Localized.scoped(to: .en) {
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            let chat = ChatViewModel(
                chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                store: MemoryConversationStore(), config: Config())
            try renderHosted(HomePage(chat: chat, voice: VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter()), onOpen: { _ in }, onSettings: { _ in }),
                             scheme: scheme, size: CGSize(width: 1000, height: 700), to: out, "window-home-\(tag)")
            try render(AppPanel(
                app: app, state: .connected, accountName: "karen@atom.test", phase: .ready(actions),
                disconnectPhase: .idle, onConnect: {}, onDisconnectTapped: {}, onConfirmDisconnect: {},
                onCancelDisconnect: {}, onClose: {}),
                       scheme: scheme, size: CGSize(width: 1000, height: 640), to: out, "window-apppanel-\(tag)")
            for (name, phase) in [("waiting", ConnectPoll.Phase.waiting(attempts: 2)),
                                  ("failed", .failed(message: "The browser window closed before it finished."))] {
                try render(ConnectingSheet(
                    app: app, phase: phase, showsHint: true, onOpenAgain: {}, onRetry: {}, onFinish: {},
                    onClose: {}),
                           scheme: scheme, size: CGSize(width: 620, height: 520), to: out,
                           "window-connecting-\(name)-\(tag)")
            }
        }
    }
}

@MainActor private func render<V: View>(
    _ view: V, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        Issue.record("16p-3: \(name) no se pudo renderizar")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}

/// ImageRenderer draws a ScrollView as nothing (Home came out blank), so the
/// pages that scroll go through a hosting view and its own display pass.
@MainActor private func renderHosted<V: View>(
    _ view: V, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) throws {
    let framed = view
        .frame(width: size.width, height: size.height)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let host = NSHostingView(rootView: framed)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds),
          !host.bounds.isEmpty
    else {
        Issue.record("16p-3: \(name) no se pudo renderizar")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        Issue.record("16p-3: \(name) no se pudo codificar")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
