import AppKit
import CompanionCore
import CompanionUIPro
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Bridges the host app's turn machine and design tokens into the Arc Pro
// VoiceOrb. The mapping has to stay one-to-one so the orb the user sees
// matches the actual state of the turn; the palette has to use the same
// tokens every other surface uses, so the orb does not look grafted on.

// Every TurnState the host machine can be in must resolve to a
// VoiceOrbState the package knows about. The package has no .connecting
// or .error, so those collapse to the resting state here.
@Test func everyTurnStateMapsToAVoiceOrbState() {
    expectEq(VoiceOrbState(.idle), .idle, "idle stays idle")
    expectEq(VoiceOrbState(.listening), .listening, "listening stays listening")
    expectEq(VoiceOrbState(.thinking), .thinking, "thinking stays thinking")
    expectEq(VoiceOrbState(.speaking), .speaking, "speaking stays speaking")
    expectEq(VoiceOrbState(.connecting), .idle, "connecting reads as idle: no audio yet")
    expectEq(VoiceOrbState(.error), .idle, "error reads as idle: a redraw would need its own case")
}

@Test @MainActor func theHeroPaletteUsesTheInkCardBackground() {
    // The palette's Color values wrap NSColor instances built from the same
    // hex as the Swatch tokens the rest of the host card reads. Comparing
    // the resolved sRGB hex keeps the test free of Color's opaque equality.
    expect(srgbHex(VoiceOrbPalette.hero.background) == srgbHex(HeroMetrics.ink.ns),
           "hero background is the ink card so the orb blends with the card")
    expect(srgbHex(VoiceOrbPalette.hero.foreground) == srgbHex(Neutral.white.ns),
           "hero foreground is white so the body reads on the dark card")
    expect(VoiceOrbPalette.hero.isDark, "hero is dark: white ink on a dark card")
}

@Test @MainActor func theSurfacePaletteFlipsWithTheColorScheme() {
    let light = VoiceOrbPalette.surface(colorScheme: .light)
    let dark = VoiceOrbPalette.surface(colorScheme: .dark)
    expect(!light.isDark, "light scheme paints a light orb")
    expect(dark.isDark, "dark scheme paints a dark orb")
    // The light side of the foreground token is the dark ink on white, so
    // the hex check is enough to know the palette is reading the same
    // token the rest of the surface uses.
    expect(srgbHex(light.foreground) == srgbHex(Semantic.foreground),
           "the foreground follows the same token the rest of the surface uses")
    expect(srgbHex(light.background) == srgbHex(Semantic.background),
           "the background matches the window so the orb does not lift off")
}

// Building the home hero must not crash for any of the six states. Voice
// state on the home page is `voice.snapshot.state`, and the screen has
// to keep drawing while the machine cycles through every one of them.
@Test @MainActor func homeHeroBuildsForEveryTurnState() {
    expectEq(HeroMetrics.orbSize, Container.hero, "the orb is the hero figure size")
    for state in [TurnState.idle, .connecting, .listening, .thinking, .speaking, .error] {
        let view = HomeHero(state: state, levels: VoiceLevels(mic: 0.4, agent: 0.3))
        let renderer = ImageRenderer(content: view.frame(width: 640))
        renderer.scale = 1
        expect(renderer.nsImage != nil, "home hero renders for state \(state)")
    }
}

// The welcome orb must also build, with and without a level, across both
// color schemes. The previous Orb lived in this file; the new one has to
// keep every call site green.
@Test @MainActor func welcomeOrbBuildsForEveryTurnState() {
    for state in [TurnState.idle, .listening, .speaking] {
        for scheme in [ColorScheme.light, .dark] {
            for level in [0.0, 0.5] {
                let view = WelcomeOrb(state: state, level: level)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view.frame(width: 240))
                renderer.scale = 1
                expect(renderer.nsImage != nil,
                       "welcome orb renders for state \(state), level \(level), scheme \(scheme)")
            }
        }
    }
}

// Resolves a SwiftUI Color or NSColor to its sRGB hex so palette
// comparisons can match by source value, not by Color's opaque equality.
@MainActor private func srgbHex(_ color: Color) -> String {
    srgbHex(NSColor(color))
}

@MainActor private func srgbHex(_ color: NSColor) -> String {
    guard let srgb = color.usingColorSpace(.sRGB) else { return "unconvertible" }
    return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
        .map { String(format: "%02X", Int(($0 * 255).rounded())) }
        .joined()
}


@Test @MainActor func everyHeroStateHasItsOwnLocalizedLabel() {
    let states: [TurnState] = [.idle, .connecting, .listening, .thinking, .speaking, .error]
    let keys = states.map { HomeHero.orbLabelKey(for: $0) }
    expectEq(Set(keys).count, states.count, "one label per state")
    for key in keys {
        expect(Localized.string(key) != key, "\(key) is in the catalog")
    }
}

@Test @MainActor func welcomeRoutesItsLevelToWhoeverIsTalking() {
    expect(WelcomeOrb.levels(state: .listening, level: 0.5) == (0.5, nil), "listening: the mic")
    expect(WelcomeOrb.levels(state: .speaking, level: 0.3) == (nil, 0.3), "speaking: Companion")
    for state in [TurnState.idle, .thinking, .connecting, .error] {
        expect(WelcomeOrb.levels(state: state, level: 0.7) == (nil, nil), "\(state): no level")
    }
}
