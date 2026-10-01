import AppKit
import CompanionTestKit
import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16p-3: line height by role, and the window / apps / island pins.
// "Measured" values come from docs/research; the rest are Companion's own and
// say so, so a later change knows which ones a capture can overrule.

@Test @MainActor func pins16p3Tests() {
    testEveryRoleCarriesItsMeasuredLeading()
    testRoleSizesAreTheTypeScale()
    testRenderedLineHeightIsTheMeasuredRatio()
    testLineSpacingFollowsTheUserScale()
    testMainWindowPins()
    testAppsPins()
    testAppPanelPins()
    testConnectingSheetPins()
    testIslandDropPins()
    testIslandAttachOwnValuePins()
}

/// Explicit tolerance instead of rounding: half a point is what a line box
/// can drift between the font's own metrics and what SwiftUI lays out.
private let linePitchTolerance: CGFloat = 0.5

/// The numbers themselves are pinned once, in IncredibleTokensTests; here a
/// role must point at the right named constant, not at a copy of its value.
@MainActor func testEveryRoleCarriesItsMeasuredLeading() {
    let want: [TypeRole: CGFloat] = [
        .micro: Leading.micro, .caption: Leading.caption, .body: Leading.body,
        .rowTitle: Leading.rowTitle, .heroBody: Leading.heroBody,
        .sectionTitle: Leading.sectionTitle, .dialogTitle: Leading.dialogTitle,
        .bannerTitle: Leading.bannerTitle, .pageTitle: Leading.pageTitle,
        .display: Leading.display,
    ]
    #expect(want.count == TypeRole.allCases.count, "16p-3: un interlineado por cada papel")
    for role in TypeRole.allCases {
        expectEq(role.leading, want[role] ?? -1, "16p-3 interlineado de \(role)")
    }
}

@MainActor func testRoleSizesAreTheTypeScale() {
    let want: [TypeRole: CGFloat] = [
        .micro: 11, .caption: 12, .body: 13, .rowTitle: 14, .heroBody: 15,
        .sectionTitle: 16, .dialogTitle: 20, .bannerTitle: 22, .pageTitle: 30,
        .display: 30,
    ]
    for role in TypeRole.allCases {
        expectEq(role.size, want[role] ?? -1, "16p-3 tamaño de \(role)")
    }
}

/// SwiftUI's lineSpacing is added to the font's own line height, so the gap
/// has to be the ratio's line minus that. Measured on a real many-line text.
/// Display (1.06) is tighter than SF's own line and SwiftUI ignores a
/// negative spacing, so it bottoms out at the font's 35 pt line.
@MainActor func testRenderedLineHeightIsTheMeasuredRatio() {
    let floored: [TypeRole: CGFloat] = [.display: 35]
    withScale(0) {
        for role in TypeRole.allCases {
            let scaled = TypeScale.apply(role.size)
            let got = renderedLinePitch(role)
            let want = floored[role] ?? role.leading * scaled
            #expect(abs(got - want) <= linePitchTolerance,
                    Comment(rawValue: "16p-3 línea de \(role): medida \(got) pt, esperada \(want) pt (\(role.leading) x \(scaled))"))
        }
    }
}

/// Pitch of a 21-line text: (21 lines minus 1) / 20, so the padding, the first
/// line's ascent and the layout's whole-point rounding average out.
@MainActor private func renderedLinePitch(_ role: TypeRole) -> CGFloat {
    func height(_ lines: Int) -> CGFloat {
        let text = Array(repeating: "Ag", count: lines).joined(separator: "\n")
        let view = Text(text).font(Fonts.sans(role.size)).typeLeading(role).fixedSize()
        return NSHostingView(rootView: view).fittingSize.height
    }
    return (height(21) - height(1)) / 20
}

@MainActor func testLineSpacingFollowsTheUserScale() {
    for role in [TypeRole.body, .micro] {
        var gaps: [CGFloat] = []
        for delta in [-1, 0, 2] {
            withScale(delta) {
                let gap = role.lineSpacing()
                expectEq(gap, Leading.spacing(role.leading, at: TypeScale.apply(role.size), face: .system),
                         "16p-3 \(role) a \(delta): el hueco aplica la escala por dentro")
                gaps.append(gap)
            }
        }
        // The font's own line height jumps by whole points, so between two
        // neighbouring scales the gap can tie; across the range it must grow.
        #expect(gaps[0] <= gaps[1] && gaps[1] <= gaps[2] && gaps[0] < gaps[2],
                Comment(rawValue: "16p-3 \(role): el hueco crece con la escala -1, 0, +2, salió \(gaps)"))
    }
}

/// The scale lives in UserDefaults and other tests move it: read once first
/// (which runs its one-time migration), set, and put the user's value back.
@MainActor private func withScale(_ delta: Int, _ body: () -> Void) {
    let saved = TypeScale.delta
    TypeScale.delta = delta
    defer { TypeScale.delta = saved }
    body()
}

// MARK: - Pins

@MainActor func testMainWindowPins() {
    expectEq([MainWindowMetrics.detailMaxWidth, MainWindowMetrics.detailMaxHeight,
              MainWindowMetrics.detailSide], [860, 620, 220],
             "16p-3 detalle de tarea: 860 × 620, columna 220 (valores propios)")
}

@MainActor func testAppsPins() {
    expectEq([AppsMetrics.icon, AppsMetrics.iconRadius, AppsMetrics.cardMinHeight,
              AppsMetrics.gridGap, AppsMetrics.formWidth],
             [40, 6, 132, 16, 460],
             "16p-3 apps: icono 40, radio md, tarjeta 132, gap 16, formulario 460 (propios)")
    expectEq(AppsMetrics.searchPause, 0.3, "16p-3 apps: 0,3 s de pausa antes de buscar")
}

@MainActor func testAppPanelPins() {
    expectEq([AppPanelMetrics.maxWidth, AppPanelMetrics.maxHeight],
             [1000, 700], "16p-3 panel de app: máx. 1000 × 700 (spec 16k §9.5)")
    expectEq([AppPanelMetrics.leftWidth, AppPanelMetrics.icon], [430, 44],
             "16p-3 panel de app: columna izquierda 430, icono 44 (spec 16k §9.5)")
}

@MainActor func testConnectingSheetPins() {
    expectEq(ConnectingSheetMetrics.icon, 72, "16p-3 conectando: icono 72 (captura 2026-09-28)")
    expectEq([ConnectingSheetMetrics.maxWidth, ConnectingSheetMetrics.trackWidth,
              ConnectingSheetMetrics.dot], [520, 120, 8],
             "16p-3 conectando: hoja 520, carril 120, punto 8 (propios)")
}

@MainActor func testIslandDropPins() {
    expectEq(IslandDropMetrics.dash, [6, 4], "16p-3 soltar: discontinuo 6 / 4 (propio)")
    expectSRGB(IslandDropMetrics.litFill, [0.06, 0.16, 0.34],
               "16p-3 soltar: zona encendida, relleno medido en la grabación")
    expectSRGB(IslandDropMetrics.litStroke, [0.25, 0.55, 1.0],
               "16p-3 soltar: zona encendida, filete medido en la grabación")
}

@MainActor func testIslandAttachOwnValuePins() {
    expectEq([IslandAttachMetrics.fadeLength, IslandAttachMetrics.stackOffset],
             [20, 3], "16p-3 adjuntos: desvanecido 20 y pila 3 (propios)")
    expectEq(IslandAttachMetrics.stackLayers, 2, "16p-3 adjuntos: 2 capas bajo la captura (propio)")
    expectEq(IslandAttachMetrics.fallbackIcon, 22, "16p-3 adjuntos: icono de respaldo 22 (propio)")
    expectEq(IslandAttachMetrics.thumbnailPixels, 204, "16p-3 adjuntos: miniatura 204 px (2x del lado largo)")
    expectEq(IslandAttachMetrics.thumbnailCacheLimit, 64, "16p-3 adjuntos: caché de 64 miniaturas")
}

/// Compares resolved sRGB components, not Color's own equality, which says
/// nothing about how close two colours are.
private func expectSRGB(_ color: Color, _ want: [CGFloat], _ label: String) {
    guard let ns = NSColor(color).usingColorSpace(.sRGB) else {
        Issue.record("16p-3: \(label): el color no resuelve a sRGB")
        return
    }
    let got = [ns.redComponent, ns.greenComponent, ns.blueComponent]
    for (g, w) in zip(got, want) {
        #expect(abs(g - w) <= 0.001, Comment(rawValue: "\(label) — got: \(got)  want: \(want)"))
    }
}
