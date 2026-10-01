import CompanionCore
import CompanionTestKit
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
    testGeistIsTheFixedFaceLikeIncredible()
    testSpaceRamp()
    testTypeLadderIsTheDocumentedRamp()
    testTypeLadderHoldsRatios()
    testTypeFloorHoldsAtSmallest()
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

// MARK: - Escala tipografica (R-01)

/// La rampa nominal es la de Incredible (16k). Su razon de ser desde R-01:
/// en delta 0 la escala documentada es exactamente la que se pinta, sin dos
/// tokens fundidos en el piso.
@MainActor func testTypeLadderIsTheDocumentedRamp() {
    let previous = TypeScale.delta
    defer { TypeScale.delta = previous }
    TypeScale.delta = 0
    expectEq(
        typeLadder().map { TypeScale.apply($0) },
        [CGFloat(11), 12, 13, 14, 15, 16, 20, 22, 30],
        "tipo: delta 0 pinta la rampa de Incredible")
}

/// El control de tamano es multiplicativo, no aditivo: sumar un offset
/// aplasta las razones en los extremos. En todos los pasos la rampa crece y
/// cada razon se mantiene; la desviacion es solo el redondeo a punto entero.
@MainActor func testTypeLadderHoldsRatios() {
    let previous = TypeScale.delta
    defer { TypeScale.delta = previous }
    let ladder = typeLadder()
    let nominal = (1..<ladder.count).map { ladder[$0] / ladder[$0 - 1] }
    for delta in TypeScale.min...TypeScale.max {
        TypeScale.delta = delta
        let rendered = typeLadder().map { TypeScale.apply($0) }
        for i in 1..<rendered.count {
            expect(
                rendered[i] > rendered[i - 1],
                "tipo: delta \(delta) — el escalon \(i) no crece "
                    + "(\(rendered[i - 1]) → \(rendered[i]))")
            let drift = abs(rendered[i] / rendered[i - 1] / nominal[i - 1] - 1)
            expect(
                drift <= 0.05,
                "tipo: delta \(delta) — razon \(i) se desvia "
                    + "\(Int((drift * 100).rounded()))%")
        }
    }
}

/// El piso solo actua en el paso mas pequeno; ese es todo su papel.
@MainActor func testTypeFloorHoldsAtSmallest() {
    let previous = TypeScale.delta
    defer { TypeScale.delta = previous }
    TypeScale.delta = TypeScale.min
    expectEq(
        TypeScale.apply(TypeSize.micro), TypeScale.floor,
        "tipo: en el paso minimo el micro toca el piso")
    TypeScale.delta = 0
    expect(
        TypeScale.apply(TypeSize.micro) > TypeScale.floor,
        "tipo: en delta 0 el piso no recorta nada")
}

/// Funcion y no constante: los tokens estan aislados al MainActor y el
/// inicializador de un global no lo esta.
@MainActor private func typeLadder() -> [CGFloat] {
    [TypeSize.micro, TypeSize.caption, TypeSize.body, TypeSize.rowTitle,
     TypeSize.heroBody, TypeSize.sectionTitle, TypeSize.dialogTitle,
     TypeSize.bannerTitle, TypeSize.pageTitle]
}


/// Wave 16c: Incredible's system is Geist + Geist Mono, fixed. The face is
/// no longer a preference; Inter then the system stay as fallbacks.
@MainActor func testGeistIsTheFixedFaceLikeIncredible() {
    expectEq(FontFallback.sansFamily(registered: ["Geist-Regular", "Inter-Regular"]), "Geist",
             "geist: la familia fija")
    expectEq(FontFallback.sansFamily(registered: ["Inter-Regular"]), "Inter-Regular",
             "geist: sin Geist, Inter")
    expect(FontFallback.sansFamily(registered: []) == nil, "geist: sin nada, el sistema")
    expectEq(FontFallback.monoName(bold: false, registered: ["GeistMono-Regular"]), "GeistMono-Regular",
             "geist mono: regular")
    expectEq(FontFallback.monoName(bold: true, registered: ["GeistMono-Medium"]), "GeistMono-Medium",
             "geist mono: el peso fuerte es Medium")
}
