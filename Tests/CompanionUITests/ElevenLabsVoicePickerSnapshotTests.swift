import AppKit
import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The ElevenLabs voice picker in Settings > Voz, light and dark. Same
// harness rule as the other galleries: only with COMPANION_SNAPSHOTS=<dir>.
// The section loads its state in .onAppear, so it renders inside a real
// window; a bare hosting view never fires onAppear. Run it on its own
// filter: it swaps the global ElevenLabsVoicePreference.store across awaits,
// and elevenLabsVoiceSettingsTests swaps the same store, so the two
// interleave and read each other's voice.

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func elevenLabsVoicePickerSnapshots() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let longID = String(repeating: "aB3dE6gH9k", count: 6) + "mNpQ"
    // No Spanish frame: Localized.scoped is task-local and SwiftUI renders
    // outside the test's task, so it would draw English under an es name.
    let states: [(String, String?)] = [
        ("eleven-voice-default", nil),
        ("eleven-voice-custom", "XyZ0123456789"),
        ("eleven-voice-custom-long", longID),
    ]
    for (name, stored) in states {
        for scheme in [ColorScheme.light, .dark] {
            let suite = "eleven-voice-snap-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            ElevenLabsVoicePreference.store = defaults
            defer { ElevenLabsVoicePreference.store = .standard }
            if let stored { ElevenLabsVoicePreference.voiceID = stored }
            try await renderInWindow(
                SettingsElevenLabsVoice(
                    preview: nil, secrets: TestSecretStore([.elevenLabs: "sk_test"]),
                    fallbackVoice: VoiceID.allCases[0])
                    .padding(Space.x6),
                scheme: scheme, size: CGSize(width: 560, height: 620), to: out,
                "\(name)-\(scheme == .light ? "light" : "dark")")
        }
    }
}

@MainActor private func renderInWindow<V: View>(
    _ view: V, scheme: ColorScheme, size: CGSize, to dir: URL, _ name: String
) async throws {
    let framed = view
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Semantic.background)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let host = NSHostingView(rootView: framed)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    // A closed window that is also released by ARC is a double release.
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    window.contentView = host
    window.orderBack(nil)
    defer { window.close() }
    // Let .onAppear run and its state change re-render before capturing.
    try await Task.sleep(for: .milliseconds(300))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), !host.bounds.isEmpty else {
        Issue.record("eleven-voice: \(name) could not be rendered")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        Issue.record("eleven-voice: \(name) could not be encoded")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
