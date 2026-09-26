import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16k: every value below was measured in Incredible's shipped CSS
// (docs/research/incredible-tipografia.md). A drift here is a parity loss,
// not a style choice.

@Test @MainActor func incredibleTokensTests() {
    testTypeRolesMatchIncredible()
    testLeadingPerRoleMatchesIncredible()
    testDisplayIsFluidBetween30And42()
    testTrackingMatchesIncredible()
    testSpaceMatchesIncredible()
    testRadiusMatchesIncredible()
    testContainersMatchIncredible()
    testControlMetricsMatchIncredible()
}

@MainActor func testTypeRolesMatchIncredible() {
    expectEq(
        [TypeSize.micro, TypeSize.caption, TypeSize.body, TypeSize.rowTitle,
         TypeSize.heroBody, TypeSize.sectionTitle, TypeSize.dialogTitle,
         TypeSize.bannerTitle, TypeSize.pageTitle, TypeSize.display],
        [CGFloat(11), 12, 13, 14, 15, 16, 20, 22, 30, 30],
        "16k tipo: la escala por papel de Incredible")
    // Old names stay as aliases until every view moves to its role.
    expectEq(TypeSize.base, TypeSize.body, "16k tipo: base = body")
    expectEq(TypeSize.strong, TypeSize.sectionTitle, "16k tipo: strong = sectionTitle")
    expectEq(TypeSize.title, TypeSize.bannerTitle, "16k tipo: title = bannerTitle")
}

@MainActor func testLeadingPerRoleMatchesIncredible() {
    expectEq(
        [Leading.micro, Leading.caption, Leading.body, Leading.rowTitle,
         Leading.heroBody, Leading.sectionTitle, Leading.dialogTitle,
         Leading.bannerTitle, Leading.pageTitle, Leading.display],
        [CGFloat(1.35), 1.4, 1.5, 1.4, 1.5, 1.3, 1.2, 1.2, 1.2, 1.06],
        "16k interlineado: uno por papel")
    expectEq(
        [Leading.tight, Leading.snug, Leading.normal, Leading.relaxed],
        [CGFloat(1.25), 1.375, 1.5, 1.625],
        "16k interlineado: los cuatro con nombre")
    // SwiftUI's lineSpacing is the gap added between lines, not the ratio.
    expectEq(Leading.spacing(1.5, at: 13), 6.5, "16k interlineado: 13 × 1.5 deja 6.5 de hueco")
}

@MainActor func testDisplayIsFluidBetween30And42() {
    expectEq(TypeSize.display(forWidth: 600), 30, "16k display: piso 30")
    expectEq(TypeSize.display(forWidth: 1125), 36, "16k display: 3.2 % del ancho")
    expectEq(TypeSize.display(forWidth: 2000), 42, "16k display: techo 42")
}

@MainActor func testTrackingMatchesIncredible() {
    expectEq(
        [Tracking.tighter, Tracking.tight, Tracking.snug, Tracking.normal,
         Tracking.wide, Tracking.caps, Tracking.wider],
        [CGFloat(-0.03), -0.025, -0.01, 0, 0.025, 0.06, 0.08],
        "16k tracking")
}

@MainActor func testSpaceMatchesIncredible() {
    expectEq(
        [Space.x0_5, Space.x1, Space.x1_5, Space.x2, Space.x2_5, Space.x3,
         Space.x3_5, Space.x4, Space.x5, Space.x6, Space.x7, Space.x8,
         Space.x9, Space.x10, Space.x12, Space.x14],
        [CGFloat(2), 4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32, 36, 40, 48, 56],
        "16k space: base 4")
    expectEq(
        [Space.gutter, Space.section, Space.cardEnd, Space.indent],
        [CGFloat(56), 40, 24, 18],
        "16k space: los cuatro semanticos")
}

@MainActor func testRadiusMatchesIncredible() {
    expectEq(
        [Radius.sm, Radius.md, Radius.badge, Radius.chip, Radius.control,
         Radius.lg, Radius.cardSm, Radius.xl, Radius.dialog, Radius.card,
         Radius.panel],
        [CGFloat(4), 6, 8, 10, 14, 16, 18, 20, 20, 22, 28],
        "16k radio")
}

@MainActor func testContainersMatchIncredible() {
    expectEq(
        [Container.narrow, Container.medium, Container.wide, Container.content],
        [CGFloat(384), 448, 576, 960],
        "16k contenedores")
    // D3: settings keep their own panel widths; only chat reads at 960.
    expectEq(Container.sheet, 520, "16k contenedores: la hoja de ajustes no cambia")
}

@MainActor func testControlMetricsMatchIncredible() {
    expectEq(
        [ControlMetrics.switchWidth, ControlMetrics.switchHeight,
         ControlMetrics.switchThumb, ControlMetrics.switchSmallWidth,
         ControlMetrics.switchSmallHeight, ControlMetrics.switchSmallThumb,
         ControlMetrics.switchPad, ControlMetrics.selectSmallHeight],
        [CGFloat(38), 23, 19, 28, 16, 12, 2, 34],
        "16k controles: switch y select")
}

// MARK: - 16k-2: the window speaks the system face, the island and welcome Geist

@Test @MainActor func incredibleFaceTests() {
    let registered: Set<String> = ["Geist-Regular", "Inter-Regular"]
    expect(FontFallback.sansFamily(for: .system, registered: registered) == nil,
           "16k-2 ventana: fuente del sistema, como Incredible")
    expectEq(FontFallback.sansFamily(for: .geist, registered: registered), "Geist",
             "16k-2 isla y bienvenida: Geist")
    expectEq(FontFallback.sansFamily(for: .geist, registered: ["Inter-Regular"]), "Inter-Regular",
             "16k-2 sin Geist: Inter")
}
