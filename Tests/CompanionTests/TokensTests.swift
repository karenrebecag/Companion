import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func tokensTests() {
    testNeutralRamp()
    testAccentColors()
    testHighlightEnum()
    testSemanticRoles()
}

@MainActor func testNeutralRamp() {
    expectEq(Neutral.n50.hex, "FAFAFA", "n50 es casi blanco")
    expectEq(Neutral.n950.hex, "0A0A0A", "n950 es casi negro")
    expectEq(Neutral.white.hex, "FFFFFF", "white es blanco puro")
    expectEq(Neutral.black.hex, "000000", "black es negro puro")

    // Verify ordering: each step should be progressively darker
    let ramp = [Neutral.n50, Neutral.n100, Neutral.n150, Neutral.n200,
                Neutral.n300, Neutral.n400, Neutral.n500, Neutral.n600,
                Neutral.n700, Neutral.n770, Neutral.n800, Neutral.n850,
                Neutral.n870, Neutral.n900, Neutral.n950]
    var prev: UInt32 = 0xFFFFFFFF
    for swatch in ramp {
        let current = UInt32(swatch.hex, radix: 16) ?? 0
        expect(current < prev || prev == 0xFFFFFFFF,
               "Neutral ramp should be ordered light to dark: \(swatch.hex)")
        prev = current
    }
}

@MainActor func testAccentColors() {
    expectEq(Accent.lime.hex, "C9FE6E", "lima es marca")
    expectEq(Accent.blue.hex, "0A84FF", "blue es sistema")
    expectEq(Accent.green.hex, "30D158", "green es sistema")
    expectEq(Accent.yellow.hex, "FFD60A", "yellow es sistema")
    expectEq(Accent.pink.hex, "FF375F", "pink es sistema")
    expectEq(Accent.orange.hex, "FF9F0A", "orange es sistema")
    expectEq(Accent.purple.hex, "BF5AF2", "purple es sistema")
}

@MainActor func testHighlightEnum() {
    expect(!Highlight.allCases.isEmpty, "Highlight debe tener opciones")
    expect(Highlight.stored == .standard, "Highlight default es standard")

    // Test that standard returns nil (system primary)
    expect(Highlight.standard.ns == nil, "standard.ns es nil (dynamic primary)")

    // Test that other colors return NSColor
    let blue = Highlight.blue
    expect(blue.ns != nil, "blue.ns no es nil")
    expectEq(blue.label, "Azul", "blue label es Azul")

    // Test dark ink colors
    expect(Highlight.yellow.usesDarkInk, "yellow usa dark ink")
    expect(Highlight.white.usesDarkInk, "white usa dark ink")
    expect(Highlight.lime.usesDarkInk, "lima usa dark ink")
    expect(!Highlight.blue.usesDarkInk, "blue no usa dark ink")
}

@MainActor func testSemanticRoles() {
    // Test background roles can be accessed without crashing
    let _ = Semantic.background
    let _ = Semantic.surface
    let _ = Semantic.surfaceOverlay

    // Test text roles
    let _ = Semantic.foreground
    let _ = Semantic.muted
    let _ = Semantic.mutedForeground

    // Test accent roles
    let _ = Semantic.accent
    let _ = Semantic.accentForeground
    let _ = Semantic.accentText

    // Test destructive roles
    let _ = Semantic.destructive
    let _ = Semantic.destructiveForeground

    // Test borders
    let _ = Semantic.border
    let _ = Semantic.borderStrong

    expect(true, "all semantic roles accessible")
}
