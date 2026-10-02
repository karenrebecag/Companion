import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUI
import Testing

// 16f replaced the docked, resizing window with a fixed canvas under the
// notch (NotchTests). What stays here is the ramp of widths per role.

@Test @MainActor func islandChromeTests() {
    testTheRampGrowsWithTheRole()
}

// K11 (brief isla-ciclo-y-legibilidad, signed by Karen): the canvas grows so
// Incredible's whole column fits under any band up to Incredible's own, and
// the end of a long reply is never cut by the shape.
@Test @MainActor func theCanvasHoldsTheWholeColumn() {
    for band: CGFloat in [24, 32, 38, IslandChrome.bandRoom] {
        expectEq(IslandChrome.columnMaxHeight(bandHeight: band), IslandChrome.columnCap,
                 "banda \(band): la columna entera de Incredible, sin recorte")
    }
    expectEq(IslandChrome.bandRoom, 44, "el alto de la banda de Incredible")
    expectEq(IslandChrome.canvasHeight, 656, "lienzo: banda 44 + espacios 24 + columna 560 + sombra 28")
}

private func notch(band: CGFloat) -> Notch {
    NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 982 - band,
        safeTop: band, leftAuxWidth: 662, rightAuxWidth: 662))
}

// The column fitting is only half of it: the shape the user sees must hold
// band, gaps and the whole column, or the end of the text sits outside it.
@Test @MainActor func theShapeHoldsTheWholeColumn() {
    for band: CGFloat in [24, 32, 38, IslandChrome.bandRoom] {
        let open = band + IslandChrome.columnGaps + IslandChrome.columnMaxHeight(bandHeight: band)
        let shape = IslandChrome.shapeSize(for: .card, contentHeight: open, notch: notch(band: band))
        expectEq(shape.height, open, "banda \(band): la forma no recorta la columna")
    }
    let tallest = IslandChrome.shapeSize(for: .card, contentHeight: 10_000, notch: notch(band: IslandChrome.bandRoom))
    expectEq(tallest.height, 628, "la forma abierta llega a 628, la columna entera bajo la banda de Incredible")
}

// A band taller than Incredible's gives up column height instead of
// pushing the shape past the canvas.
@Test @MainActor func aTallerBandGivesUpColumnHeight() {
    expectEq(IslandChrome.columnMaxHeight(bandHeight: 60), 544, "banda 60: 16 menos de columna")
    var last = CGFloat.infinity
    for band: CGFloat in stride(from: 24, through: 80, by: 4) {
        let column = IslandChrome.columnMaxHeight(bandHeight: band)
        expect(column <= last, "banda \(band): más banda nunca da más columna")
        last = column
    }
}

@MainActor func testTheRampGrowsWithTheRole() {
    expect(IslandChrome.barWidth < IslandChrome.nudgeWidth, "island: la píldora es más angosta que el panel")
    expect(IslandChrome.nudgeWidth <= IslandChrome.cardWidth, "island: la tarjeta es la más ancha")
    expectEq(IslandChrome.cardWidth, 492, "island: el ancho medido en la grabación")
}
