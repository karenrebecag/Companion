import AppKit
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

// Gap 3 review: the status text next to the strip takes all the room it is
// offered, and the strip must keep Incredible's 180 regardless.

@MainActor private final class Measured {
    var width: CGFloat = -1
}

@Test @MainActor func theStripAsksForIncrediblesWidth() {
    let controller = NSHostingController(rootView: VoiceLevelWaveform(amplitude: 0))
    let size = controller.sizeThatFits(in: NSSize(width: 1_000, height: 100))
    expectEq(size.width, VoiceLevelWaveformMetrics.maxWidth, "la tira pide 180, no lo que le ofrecen")
}

@Test @MainActor func aGreedyStatusLineDoesNotSqueezeTheStrip() async throws {
    let measured = Measured()
    let row = HStack(spacing: Space.none) {
        VoiceLevelWaveform(amplitude: 0)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { measured.width = $0 })
        Text(verbatim: String(repeating: "Escucho ", count: 40))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    let host = NSHostingView(rootView: row.frame(width: IslandChrome.barWidth, height: 40))
    host.frame = NSRect(x: 0, y: 0, width: IslandChrome.barWidth, height: 40)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.orderBack(nil)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(200))
    expectEq(measured.width, VoiceLevelWaveformMetrics.maxWidth, "con texto largo al lado, la tira conserva 180")
}
