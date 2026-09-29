import Foundation
import SwiftUI
import Testing
@testable import CompanionUI

// 16p-1: the window chrome (root, settings, dropdown, sidebar) moved panels
// with springs whatever the accessibility setting said. The decision is one
// pure function; the four files may not animate around it.

@Test @MainActor func chromeMotionTests() {
    testReduceMotionDropsTheAnimation()
    testTheFourFilesNeverAnimateAroundTheDecision()
}

@MainActor func testReduceMotionDropsTheAnimation() {
    expect(ChromeMotion.animation(.springSheet, reduceMotion: true) == nil,
           "reduceMotion: sin animación, el cambio es instantáneo")
    expect(ChromeMotion.animation(.springSheet, reduceMotion: false) == .springSheet,
           "sin reduceMotion: el muelle pedido pasa tal cual")
}

@MainActor func testTheFourFilesNeverAnimateAroundTheDecision() {
    guard let root = Conformance.repoRoot() else {
        print("  nota  [chromeMotion] fuera del checkout: no hay que escanear")
        return
    }
    for name in ["CompanionRootView", "SettingsView", "Dropdown", "MainSidebar"] {
        let file = root.appendingPathComponent("Sources/CompanionUI/\(name).swift")
        let lines = Conformance.logicalLines(of: file)
        expect(!lines.isEmpty, "\(name): el archivo se lee")
        expect(lines.contains { $0.contains("accessibilityReduceMotion") },
               "\(name): lee accessibilityReduceMotion")
        let bare = lines.filter {
            ($0.contains("withAnimation(") || $0.contains(".animation("))
                && !$0.contains("ChromeMotion.")
        }
        expectEq(bare, [], "\(name): ninguna animación esquiva ChromeMotion")
    }
}
