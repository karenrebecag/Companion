import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Wave 16m-1: the ovx measures, pinned to the values read off Incredible's
// overlay CSS (docs/research/incredible-isla-componentes.md §1). The ovx ink
// (94/72/46) is NOT the ci ink of 16l (95/64/42): both scales exist in the
// original and each test names its own.

@Test @MainActor func answerPopupRichTests() {
    testAnswerInkMatchesOvx()
    testBlockMeasuresMatchOvx()
    testAnswerTypeScaleIsOneForEveryRenderer()
    testAnswerTypeUsesOnlyRegularAndMedium()
    testAnswerRhythmSitsOnTheFourGrid()
    testPopupSurfaceMatchesOvx()
    testCanvasHoldsThePopup()
    testCaveatOnlyOnWorldClaims()
}

// The "unverified" caveat undercut numbers that were simply the reply (16m
// snapshot). Only payloads that claim something about the WORLD carry it.
@MainActor func testCaveatOnlyOnWorldClaims() {
    func card(_ payload: CardPayload) -> CardView {
        CardView(card: Card(payload: payload, source: .model))
    }
    expect(card(.locations(LocationsBlock(locations: []))).claimsWorld,
           "16m: un lugar afirma el mundo")
    expect(card(.gallery(GalleryBlock(images: []))).claimsWorld,
           "16m: una imagen afirma el mundo")
    expect(!card(.stats(StatsBlock(items: []))).claimsWorld,
           "16m: las cifras son la respuesta misma")
    expect(!card(.table(TableBlock(columns: [], rows: []))).claimsWorld,
           "16m: la tabla es la respuesta misma")
    expect(!card(.chart(ChartBlock(kind: .bar, labels: [], series: []))).claimsWorld,
           "16m: la gráfica es la respuesta misma")
}

@MainActor func testAnswerInkMatchesOvx() {
    expectEq([AnswerInk.text, AnswerInk.secondary, AnswerInk.muted],
             [0.94, 0.72, 0.46], "16m-1 tinta: 94/72/46 de blanco")
    expectEq([AnswerInk.line, AnswerInk.lineStrong], [0.07, 0.14],
             "16m-1 líneas: 7 y 14 %")
    expectEq([AnswerInk.fill, AnswerInk.fillHover, AnswerInk.fillStrong],
             [0.05, 0.09, 0.13], "16m-1 rellenos: 5/9/13 %")
    expectEq(AnswerInk.accent.hex, "4A9CFF", "16m-1 acento: 4a9cff, no el 78AAFF de la isla")
}

@MainActor func testBlockMeasuresMatchOvx() {
    expectEq([AnswerBlockMetrics.titleSize, AnswerBlockMetrics.sectionSize,
              AnswerBlockMetrics.subheadingSize], [18, 16, 14],
             "escala: h1 18, h2 16, h3 14")
    expectEq([AnswerBlockMetrics.bodySize, AnswerBlockMetrics.bodyLeading],
             [14, 1.4], "escala: párrafo 14 con interlineado 1.4")
    expectEq(AnswerBlockMetrics.bodyMeasure, 66, "16m-1 párrafo: 66 caracteres de medida")
    expectEq([AnswerBlockMetrics.tableSize, AnswerBlockMetrics.tableLeading],
             [12.5, 1.45], "16m-1 tabla: 12.5 con 1.45")
    expectEq([AnswerBlockMetrics.calloutPaddingY, AnswerBlockMetrics.calloutPaddingX,
              AnswerBlockMetrics.calloutGap], [12, 16, 12], "ritmo: callout 12×16 gap 12")
    expectEq([AnswerBlockMetrics.calloutTone, AnswerBlockMetrics.calloutBorder],
             [0.11, 0.26], "16m-1 callout: tono 11 % y borde 26 %")
    expectEq(AnswerBlockMetrics.codeBar, 26, "16m-1 código: barra de 26")
    expectEq([AnswerBlockMetrics.inlineCodeSize, AnswerBlockMetrics.inlineCodePaddingY,
              AnswerBlockMetrics.inlineCodePaddingX, AnswerBlockMetrics.inlineCodeRadius],
             [12, 1.5, 6, 6], "16m-1 código en línea: mono 12, 1.5×6, radio 6")
    expectEq([AnswerBlockMetrics.chipSize, AnswerBlockMetrics.chipRadius],
             [12, 6], "escala: chip de archivo mono 12, radio 6")
    expectEq([AnswerBlockMetrics.quoteSize, AnswerBlockMetrics.quoteLeading,
              AnswerBlockMetrics.quotePaddingY, AnswerBlockMetrics.quotePaddingX],
             [14, 1.4, 8, 16], "ritmo: cita 14/1.4, 8×16")
    expectEq(AnswerBlockMetrics.innerRadius, 12, "16m-1: radio interior 12 en todos los marcos")
    // 1.4 over 14 leaves 5.6 extra points per line, rounded.
    expectEq(AnswerBlockMetrics.lineSpacing(size: 14, leading: 1.4), 6,
             "16m-1: el interlineado CSS se traduce a puntos extra")
}

@MainActor func testPopupSurfaceMatchesOvx() {
    expectEq(AnswerBlockMetrics.surfaceRadius, 20, "16m-1 popup: radio 20")
    expectEq(AnswerBlockMetrics.surfaceBorder, 0.12, "16m-1 popup: borde blanco 12 %")
    expectEq([AnswerPopupMetrics.paddingTop, AnswerPopupMetrics.paddingX,
              AnswerPopupMetrics.paddingBottom], [16, 24, 16], "ritmo: popup 16/24/16")
    expectEq(AnswerPopupMetrics.width(screen: 1800), 580,
             "16m-1 popup: 580 en una pantalla normal")
    // Review 16m H2: the scroll cap must leave room for the popup's own
    // chrome (top padding, close row, gap, bottom padding) or a tall
    // answer clips at the panel's bottom edge.
    expectEq(AnswerPopupMetrics.chrome, 16 + 22 + 12 + 16,
             "16m-1 popup: el chrome fuera del scroll suma 66")
}

/// The 16f canvas was sized before the popup existed; 580 plus margin is
/// why it grew, and this test is where that decision lives.
@MainActor func testCanvasHoldsThePopup() {
    expect(IslandChrome.canvasWidth >= AnswerPopupMetrics.maxWidth + 2 * 20,
           "16m-1: el lienzo sostiene el popup de 580 con margen")
}

@MainActor func testAnswerTypeScaleIsOneForEveryRenderer() {
    expectEq([AnswerType.title, AnswerType.section, AnswerType.subheading, AnswerType.body, AnswerType.caption],
             [18, 16, 14, 14, 12], "escala: 18/16/14/14/12")
    // Popup, document and chat read the same tokens, not their own copies.
    expectEq([AnswerBlockMetrics.titleSize, AnswerBlockMetrics.sectionSize, AnswerBlockMetrics.bodySize],
             [DocCardMetrics.titleSize, DocCardMetrics.headingSize, DocCardMetrics.proseSize],
             "escala: popup y documento comparten tamaños")
    expectEq([DocChatMetrics.bodySize, DocChatMetrics.headingSize, DocChatMetrics.captionSize],
             [AnswerType.body, AnswerType.section, AnswerType.caption], "escala: el chat usa la misma")
    expectEq([DocCardMetrics.proseLeading, AnswerBlockMetrics.bodyLeading, AnswerBlockMetrics.quoteLeading],
             [1.4, 1.4, 1.4], "escala: un solo interlineado")
}

@MainActor func testAnswerTypeUsesOnlyRegularAndMedium() {
    expectEq(AnswerType.weights, [.regular, .medium], "pesos: solo regular y medium")
}

@MainActor func testAnswerRhythmSitsOnTheFourGrid() {
    for gap in AnswerType.gaps + [AnswerPopupMetrics.paddingTop, AnswerPopupMetrics.paddingX,
                                  AnswerPopupMetrics.paddingBottom, DocCardMetrics.paragraphGap,
                                  DocCardMetrics.listGapBefore, DocCardMetrics.listGapAfter,
                                  DocCardMetrics.headingGapBefore, DocCardMetrics.headingGapAfter,
                                  DocCardMetrics.blockGap, AnswerBlockMetrics.calloutGap] {
        expectEq(gap.truncatingRemainder(dividingBy: 4), 0, "ritmo: \(gap) es múltiplo de 4")
    }
    expect(AnswerType.headingBefore > AnswerType.headingAfter, "ritmo: el título tiene más aire arriba que abajo")
}
