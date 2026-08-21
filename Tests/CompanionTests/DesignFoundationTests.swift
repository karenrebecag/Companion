import CompanionCore
import CompanionUI
import Foundation
import SwiftUI
import Testing

@Test @MainActor func designFoundationTests() {
    testElevationScaleIsMonotonic()
    testBodyContrastPassesAA()
    testMutedContrastPassesAA()
    testAccentOnLimePassesAA()
    testDestructiveContrastPassesAA()
    testFontFallbackDegradesToInterThenSystem()
    testSpaceRamp()
}

@MainActor func testElevationScaleIsMonotonic() {
    let steps = Elevation.allCases.sorted()
    expectEq(steps, [.rest, .hover, .panel, .sheet, .popover],
             "elevation: orden rest < hover < panel < sheet < popover")
    let radii = steps.map(\.shadowRadius)
    for i in 1..<radii.count {
        expect(radii[i] >= radii[i - 1],
               "elevation: radio no decrece en \(steps[i])")
    }
}

@MainActor func testBodyContrastPassesAA() {
    expect(Contrast.passesAA(hex: "0A0A0A", hex: "FAFAFA"),
           "AA: n950 sobre n50 (texto en light)")
    expect(Contrast.passesAA(hex: "FAFAFA", hex: "0A0A0A"),
           "AA: n50 sobre n950 (texto en dark)")
}

@MainActor func testMutedContrastPassesAA() {
    expect(Contrast.passesAA(hex: "525252", hex: "FAFAFA"),
           "AA: n600 sobre n50 (muted light)")
    expect(Contrast.passesAA(hex: "A3A3A3", hex: "0A0A0A"),
           "AA: n400 sobre n950 (muted dark)")
}

@MainActor func testAccentOnLimePassesAA() {
    expect(Contrast.passesAA(hex: "0A0A0A", hex: "C9FE6E"),
           "AA: tinta sobre lima")
}

@MainActor func testDestructiveContrastPassesAA() {
    expect(Contrast.passesAA(hex: "FFFFFF", hex: "DC2626"),
           "AA: blanco sobre destructive light")
    expect(Contrast.passesAA(hex: "0A0A0A", hex: "F87171"),
           "AA: n950 sobre destructive dark")
}

@MainActor func testFontFallbackDegradesToInterThenSystem() {
    expectEq(
        FontFallback.postScriptName(.inter, registered: ["Inter-Regular"]),
        "Inter-Regular",
        "fonts: Inter empaquetada")
    expectEq(
        FontFallback.postScriptName(.inter, registered: []),
        nil,
        "fonts: sin Inter → sistema")
    expectEq(
        FontFallback.postScriptName(
            .hypodermic, registered: ["Hypodermic-Regular"]),
        "Hypodermic-Regular",
        "fonts: propietaria local")
    expectEq(
        FontFallback.postScriptName(
            .hypodermic, registered: ["Inter-Regular"]),
        "Inter-Regular",
        "fonts: sin Hypodermic → Inter")
    expectEq(
        FontFallback.postScriptName(.hypodermic, registered: []),
        nil,
        "fonts: sin nada → sistema")
    expectEq(
        FontFallback.postScriptName(.serif, registered: ["Inter-Regular"]),
        nil,
        "fonts: serif es New York del sistema")
}

@MainActor func testSpaceRamp() {
    expectEq(
        [Space.x1, Space.x2, Space.x3, Space.x4, Space.x6],
        [CGFloat(4), 8, 12, 16, 24],
        "space: rampa 4/8/12/16/24")
    _ = (Semantic.background, Semantic.surface, Semantic.foreground,
         Semantic.mutedForeground, Semantic.border, Semantic.accent,
         Semantic.destructive, Font.uiTitle, Font.uiBody, Font.uiCaption)
}
