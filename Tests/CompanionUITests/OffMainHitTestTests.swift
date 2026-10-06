import AppKit
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

/// Crash 2026-10-06: the pointer sampler's hit test reached the island's
/// SwiftUI tree on its own queue and tripped the main-actor check.
@Test @MainActor func offMainHitTestNeverReachesSwiftUI() async {
    guard let screen = NSScreen.screens.first else { return }
    let panel = ScreenOverlayPanel(screen: screen, content: Text("x"))
    let point = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    let offMain = await Task.detached { panel.accessibilityHitTest(point) == nil }.value
    expect(offMain, "fuera de main no hay elemento nuestro que señalar")
}
