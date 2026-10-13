import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// The home hero shows the voice's state as a still glyph where the animated
// orb was (Karen chose performance over the sphere, 2026-10-13).

// Building the home hero must not crash for any of the six states. Voice
// state on the home page is `voice.snapshot.state`, and the screen has
// to keep drawing while the machine cycles through every one of them.
@Test @MainActor func homeHeroBuildsForEveryTurnState() {
    for state in [TurnState.idle, .connecting, .listening, .thinking, .speaking, .error] {
        let renderer = ImageRenderer(content: HomeHero(state: state).frame(width: 640))
        renderer.scale = 1
        expect(renderer.nsImage != nil, "home hero renders for state \(state)")
    }
}

@Test @MainActor func everyHeroStateHasItsOwnLocalizedLabel() {
    let states: [TurnState] = [.idle, .connecting, .listening, .thinking, .speaking, .error]
    let keys = states.map { HomeHero.orbLabelKey(for: $0) }
    expectEq(Set(keys).count, states.count, "one label per state")
    for key in keys {
        expect(Localized.string(key) != key, "\(key) is in the catalog")
    }
}

// The glyph is the only thing on the card that tells the states apart, so
// the ones the voice moves through must not share one, and each must exist.
@Test @MainActor func theHeroGlyphTellsTheVoiceStatesApart() {
    let shown: [TurnState] = [.idle, .listening, .thinking, .speaking, .error]
    let symbols = shown.map { HomeHero.symbol(for: $0) }
    expectEq(Set(symbols).count, shown.count, "one glyph per state the voice shows")
    for symbol in symbols {
        expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) is an SF Symbol")
    }
}
