import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Waveform VAD brief (docs/research/waveform-vad-voiced.md): the mic strip fed
// room noise, then speech, then silence. A gallery for looking at, opt-in like
// the others; the behaviour itself is pinned in VoiceActivityGateTests.
//
// The view scrolls on wall time, so a live capture depends on how the test
// process schedules its sleeps: a late frame left a column empty and drew a
// dot mid-speech that the app would not. The view's own tape is fed instead,
// one frame every 85 ms on a stepped clock, and drawn by the view's renderer.

/// One mic frame (2048 frames at 24 kHz, MicCapture's tap); shorter than an
/// 89 ms column, so every column gets at least one frame.
private let frameSeconds = 0.085

private let roomNoise = (0..<16).map { $0.isMultiple(of: 2) ? 0.11 : 0.13 }
private let speech = [0.32, 0.45, 0.58, 0.41, 0.6, 0.36, 0.52, 0.3, 0.47, 0.55, 0.38, 0.5]
private let silence = (0..<7).map { $0.isMultiple(of: 2) ? 0.12 : 0.115 }
private let script = roomNoise + speech + silence

private let stripSize = CGSize(width: 220, height: 60)

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func waveformVADSnapshots() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let width = Double(VoiceLevelWaveformMetrics.maxWidth)
    for scheme in [ColorScheme.light, .dark] {
        try capture(scripted(width: width), scrolls: true, scheme: scheme, to: out,
                    "waveform-\(scheme == .dark ? "dark" : "light")")
    }
    // accessibilityReduceMotion cannot be set from a test; this is what the
    // view draws with it on: no scroll, only the live column.
    try capture(scripted(width: width), scrolls: false, scheme: .dark, to: out, "waveform-reduce-motion")
}

@MainActor private func scripted(width: Double) -> WaveformTape {
    let tape = WaveformTape()
    for (index, meter) in script.enumerated() {
        tape.ingest(meter: meter, at: Double(index) * frameSeconds)
        tape.history.advance(elapsed: frameSeconds, width: width)
    }
    return tape
}

@MainActor private func capture(_ tape: WaveformTape, scrolls: Bool, scheme: ColorScheme,
                                to dir: URL, _ name: String) throws {
    // The tape's first draw advances by zero and re-feeds the last frame at
    // its own instant, which changes nothing: the picture is the script.
    let now = Double(script.count - 1) * frameSeconds
    let strip = Canvas { context, size in
        tape.draw(now: now, meter: script[script.count - 1], size: size, scale: 2, scrolls: scrolls, in: &context)
    }
    .frame(width: VoiceLevelWaveformMetrics.maxWidth, height: VoiceLevelWaveformMetrics.height)
    // The view's fade-in of the oldest columns.
    .mask {
        HStack(spacing: Space.none) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: VoiceLevelWaveformMetrics.fade)
            Rectangle()
        }
    }
    .frame(width: stripSize.width, height: stripSize.height)
    .background(IslandInk.panel)
    .environment(\.colorScheme, scheme)
    let host = NSHostingView(rootView: strip)
    host.frame = NSRect(origin: .zero, size: stripSize)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        Issue.record("waveform gallery: \(name) did not render a bitmap")
        return
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        Issue.record("waveform gallery: \(name) did not encode as PNG")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
