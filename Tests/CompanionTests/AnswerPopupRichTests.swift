import CompanionUI
import Foundation
import Testing

// Wave 16m-1: the ovx measures, pinned to the values read off Incredible's
// overlay CSS (docs/research/incredible-isla-componentes.md §1). The ovx ink
// (94/72/46) is NOT the ci ink of 16l (95/64/42): both scales exist in the
// original and each test names its own.

@Test @MainActor func answerPopupRichTests() {
    testAnswerInkMatchesOvx()
    testBlockMeasuresMatchOvx()
    testPopupSurfaceMatchesOvx()
    testCanvasHoldsThePopup()
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
              AnswerBlockMetrics.eyebrowSize], [21, 15.5, 11.5],
             "16m-1 títulos: h1 21, h2 15.5, h3 11.5")
    expectEq([AnswerBlockMetrics.bodySize, AnswerBlockMetrics.bodyLeading],
             [13.5, 1.62], "16m-1 párrafo: 13.5 con interlineado 1.62")
    expectEq(AnswerBlockMetrics.bodyMeasure, 66, "16m-1 párrafo: 66 caracteres de medida")
    expectEq([AnswerBlockMetrics.tableSize, AnswerBlockMetrics.tableLeading],
             [12.5, 1.45], "16m-1 tabla: 12.5 con 1.45")
    expectEq([AnswerBlockMetrics.calloutPaddingY, AnswerBlockMetrics.calloutPaddingX,
              AnswerBlockMetrics.calloutGap], [11, 14, 11], "16m-1 callout: 11×14 gap 11")
    expectEq([AnswerBlockMetrics.calloutTone, AnswerBlockMetrics.calloutBorder],
             [0.11, 0.26], "16m-1 callout: tono 11 % y borde 26 %")
    expectEq(AnswerBlockMetrics.codeBar, 26, "16m-1 código: barra de 26")
    expectEq([AnswerBlockMetrics.inlineCodeSize, AnswerBlockMetrics.inlineCodePaddingY,
              AnswerBlockMetrics.inlineCodePaddingX, AnswerBlockMetrics.inlineCodeRadius],
             [12, 1.5, 6, 6], "16m-1 código en línea: mono 12, 1.5×6, radio 6")
    expectEq([AnswerBlockMetrics.chipSize, AnswerBlockMetrics.chipRadius],
             [11.5, 6], "16m-1 chip de archivo: mono 11.5, radio 6")
    expectEq([AnswerBlockMetrics.quoteSize, AnswerBlockMetrics.quoteLeading,
              AnswerBlockMetrics.quotePaddingY, AnswerBlockMetrics.quotePaddingX],
             [14, 1.55, 10, 16], "16m-1 cita: 14/1.55, 10×16")
    expectEq(AnswerBlockMetrics.innerRadius, 12, "16m-1: radio interior 12 en todos los marcos")
    // 1.62 over 13.5 leaves 8 extra points per line, rounded.
    expectEq(AnswerBlockMetrics.lineSpacing(size: 13.5, leading: 1.62), 8,
             "16m-1: el interlineado CSS se traduce a puntos extra")
}

@MainActor func testPopupSurfaceMatchesOvx() {
    expectEq(AnswerBlockMetrics.surfaceRadius, 20, "16m-1 popup: radio 20")
    expectEq(AnswerBlockMetrics.surfaceBorder, 0.12, "16m-1 popup: borde blanco 12 %")
    expectEq([AnswerPopupMetrics.paddingTop, AnswerPopupMetrics.paddingX,
              AnswerPopupMetrics.paddingBottom], [18, 22, 16], "16m-1 popup: 18/22/16")
    expectEq(AnswerPopupMetrics.width(screen: 1800), 580,
             "16m-1 popup: 580 en una pantalla normal")
    // Review 16m H2: the scroll cap must leave room for the popup's own
    // chrome (top padding, close row, gap, bottom padding) or a tall
    // answer clips at the panel's bottom edge.
    expectEq(AnswerPopupMetrics.chrome, 18 + 22 + 12 + 16,
             "16m-1 popup: el chrome fuera del scroll suma 68")
}

/// The 16f canvas was sized before the popup existed; 580 plus margin is
/// why it grew, and this test is where that decision lives.
@MainActor func testCanvasHoldsThePopup() {
    expect(IslandChrome.canvasWidth >= AnswerPopupMetrics.maxWidth + 2 * 20,
           "16m-1: el lienzo sostiene el popup de 580 con margen")
}
