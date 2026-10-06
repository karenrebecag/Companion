import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The island's controls in Arc's language: ghost chips with a rim, a raised
// menu with concentric rows, an inverted tooltip, an info badge, and the
// danger tone kept to a whisper until it is the thing being confirmed.

@Test @MainActor func arcMixBlendsOneToneIntoAnother() {
    expectEq(ArcTone.mix(Swatch("FFFFFF"), 0, over: Swatch("000000")).hex, "000000", "0 %: la base")
    expectEq(ArcTone.mix(Swatch("FFFFFF"), 1, over: Swatch("000000")).hex, "FFFFFF", "100 %: el tono")
    expectEq(ArcTone.mix(Swatch("FFFFFF"), 0.5, over: Swatch("000000")).hex, "808080", "a medias")
    expectEq(ArcTone.mix(Swatch("FF0000"), 2, over: Swatch("000000")).hex, "FF0000", "acotado arriba")
}

@Test @MainActor func islandInkIsArcsDarkTheme() {
    expectEq(IslandInk.chipSwatch.hex, ArcTone.surface.hex, "chip: surface")
    expectEq(IslandInk.chipPressedSwatch.hex, ArcTone.surfaceMuted.hex, "chip presionado: surface-muted")
    expectEq(IslandInk.hairlineSwatch.hex, ArcTone.border.hex, "borde: border")
    expectEq(IslandInk.popoverSwatch.hex, ArcTone.surfaceRaised.hex, "menu: surface-raised")
    expectEq(IslandInk.tooltipSwatch.hex, ArcTone.foreground.hex, "tooltip invertido: foreground")
}

@Test @MainActor func islandChipsWearARimAndGiveUnderTheFinger() {
    expect(ChipInk.island.rim != nil, "ghost: lleva borde")
    expectEq(ChipInk.island.pressScale, IslandArc.pressScale, "ghost: cede al presionar")
    expectEq(IslandArc.pressScale, 0.97, "Arc: 0.97")
    expect(ChipInk.islandDestructive.rim != nil, "peligro: borde rojizo")
    expect(ChipInk.choiceConfirm.rim == nil, "confirmar: relleno de acento, sin borde")
    expect(ChipInk.choice(selected: true).rim == nil, "la bienvenida no cambia")
    expectEq(ChipInk.choice(selected: false).pressScale, 1, "la bienvenida no cambia")
}

// confirm-morph's danger: 4 % red at rest, an 18 % red edge, 8 % on hover.
@Test @MainActor func dangerStaysAWhisperUntilConfirmed() {
    expectEq([IslandArc.Danger.fill, IslandArc.Danger.edge, IslandArc.Danger.hover], [0.04, 0.18, 0.08],
             "peligro: 4 / 18 / 8 %")
    expectEq(IslandArc.Danger.fillSwatch.hex,
             ArcTone.mix(ArcTone.danger, 0.04, over: ArcTone.surfaceRaised).hex, "fondo de peligro")
}

@Test @MainActor func theMenuIsArcsDropdown() {
    expectEq(IslandArc.Menu.padding, 5, "menu: padding 5")
    expectEq(IslandArc.Menu.radius, 26, "menu: radio de panel 26")
    expectEq(IslandArc.Menu.itemRadius, IslandArc.Menu.radius - 6, "fila: concentrica")
    expectEq(IslandArc.Menu.itemMinHeight, 36, "fila: 36 de alto")
    expectEq(IslandArc.Menu.itemPaddingX, 11, "fila: 11 a los lados")
    expectEq(IslandArc.Menu.dangerHighlight, 0.08, "fila de peligro: 8 % rojo")
}

@Test @MainActor func theTooltipIsArcsInvertedBubble() {
    expectEq([IslandArc.Tooltip.paddingY, IslandArc.Tooltip.paddingX], [12, 16], "tooltip: 12 x 16")
    expectEq(IslandArc.Tooltip.radius, 18, "tooltip: radio de control")
    expectEq(IslandArc.Tooltip.maxWidth, 240, "tooltip: 15rem")
}

@Test @MainActor func aReferentIsArcsInfoBadge() {
    expectEq([ReferentChipMetrics.paddingLeading, ReferentChipMetrics.paddingTrailing], [8, 8], "badge: 8 a los lados")
    expectEq([ReferentChipMetrics.fill, ReferentChipMetrics.stroke], [0.12, 0.24], "info: 12 % / 24 %")
}

@Test @MainActor func theIslandControlsRender() throws {
    let view = VStack(spacing: 8) {
        IslandPopover { IslandMenuList { _ in } }
        IslandTooltipBubble(text: "Adjuntar archivos")
        ReferentChip(text: "Notas")
        IslandClearConfirm(onClear: {}, onCancel: {})
    }
    .frame(width: IslandGrid.openColumn)
    .background(Color.black)
    let image = try #require(ImageRenderer(content: view).nsImage)
    expect(image.size.height > 0, "se dibujan")
}

// Arc's radio cards: a surface card with a border; checked takes 4 % of the
// control tone and a filled indicator, hover only strengthens the border.
@Test @MainActor func aChoiceIsArcsRadioCard() {
    expectEq(IslandChoiceTile.checkedFill, 0.04, "marcada: 4 % del tono")
    expectEq(IslandChoiceTile.fill(checked: false).hex, ArcTone.surface.hex, "en reposo: surface")
    expectEq(IslandChoiceTile.fill(checked: true).hex,
             ArcTone.mix(ArcTone.accent, 0.04, over: ArcTone.surface).hex, "marcada: acento al 4 %")
    expectEq(IslandChoiceTile.rim(checked: false, hover: false).hex, ArcTone.border.hex, "borde en reposo")
    expect(IslandChoiceTile.rim(checked: false, hover: true).hex != ArcTone.border.hex, "hover: borde mas fuerte")
    expectEq(IslandChoiceTile.indicator(checked: true).hex, ArcTone.accent.hex, "indicador marcado: lleno")
}

// confirm-morph: one pill, its answers concentric 4 inside it.
@Test @MainActor func aConfirmationIsOnePill() {
    expectEq(IslandMorphMetrics.height, 32, "pildora: alto de control pequeno")
    expectEq(IslandMorphMetrics.actionHeight, IslandMorphMetrics.height - IslandMorphMetrics.inset * 2,
             "respuestas: concentricas")
    expectEq(IslandMorphMetrics.askingEdge, 0.24, "preguntando: borde rojo al 24 %")
    expectEq(IslandMorphMetrics.actionPressScale, 0.95, "respuestas: ceden a 0.95")
}

// QA review: the wiring of the destructive answer, not just its drawing.
@Test @MainActor func clearAsksWithCancelFirstAndOnlyYesClears() {
    var cleared = 0, cancelled = 0
    let answers = IslandClearConfirm.answers(onClear: { cleared += 1 }, onCancel: { cancelled += 1 })
    expectEq(answers.map(\.key), ["island.clear.no", "island.clear.yes"], "primero cancelar, luego borrar")
    expect(answers[0].tone == nil, "cancelar: respuesta secundaria")
    expectEq(answers[1].tone?.hex, ArcTone.danger.hex, "borrar: el unico relleno, en peligro")
    answers[0].action()
    expectEq([cleared, cancelled], [0, 1], "no: solo cancela")
    answers[1].action()
    expectEq([cleared, cancelled], [1, 1], "si: borra una vez")
}

@Test @MainActor func theUndoIsOfferedOnlyWhenThereIsAWayBack() {
    expect(!IslandReceiptRow.offersUndo(UndoReceipt(kind: .created, subject: "plan.md")), "sin camino de vuelta: sin boton")
    let back = UndoReceipt(kind: .created, subject: "plan.md",
                           undo: .trash(path: "/tmp/plan.md", size: 1, modified: Date(timeIntervalSince1970: 0)))
    expect(IslandReceiptRow.offersUndo(back), "con camino de vuelta: Deshacer")
}

// Arc's input: the field is a surface with a border; send waits muted.
@Test @MainActor func theComposerFieldIsArcsInput() {
    expectEq(IslandFieldMetrics.fillSwatch.hex, ArcTone.surface.hex, "campo: surface")
    expectEq(IslandFieldMetrics.rimSwatch.hex, ArcTone.border.hex, "campo: borde")
    expectEq(IslandFieldMetrics.sendIdleSwatch.hex, ArcTone.surfaceMuted.hex, "enviar en espera: surface-muted")
}

// Arc's dark chart series lead the palette; "Otros" stays the quiet grey.
@Test @MainActor func chartsUseArcsDarkSeries() {
    expectEq(IslandChartInk.series.prefix(4).map(\.hex), ["55ADFF", "9C37BE", "E66E00", "00A861"],
             "series de Arc en oscuro")
}

@Test @MainActor func theApprovalRingTakesArcTonesOnTheIsland() {
    expectEq(ApprovalRingInk.islandTrack.hex, ArcTone.border.hex, "anillo: pista en border")
    expectEq(ApprovalRingInk.islandProgress.hex, ArcTone.textSecondary.hex, "anillo: avance en text-secondary")
}

@Test @MainActor func aCopiedCheckIsSuccess() {
    expectEq(IslandDictationMetrics.copiedTint.hex, ArcTone.success.hex, "copiado: check en success")
}

// Review: a long hint wraps inside Arc's 240 instead of running one line.
@Test @MainActor func aLongTooltipWrapsWithinItsCap() throws {
    let short = try #require(ImageRenderer(content: IslandTooltipBubble(text: "Enviar")).nsImage)
    let long = try #require(ImageRenderer(content: IslandTooltipBubble(
        text: "Adjunta archivos, capturas o el portapapeles para que Companion los lea en el siguiente turno")).nsImage)
    expect(long.size.width <= IslandArc.Tooltip.maxWidth + 1, "no pasa de 240: \(long.size.width)")
    expect(long.size.height > short.size.height + 8, "envuelve en varias lineas: \(long.size.height)")
}

// QA review: each channel mixes on its own, and an uneven mix rounds by hand.
@Test @MainActor func arcMixKeepsChannelsApart() {
    expectEq(ArcTone.mix(Swatch("00FF00"), 0.5, over: Swatch("000000")).hex, "008000", "verde solo en G")
    expectEq(ArcTone.mix(Swatch("0000FF"), 0.5, over: Swatch("000000")).hex, "000080", "azul solo en B")
    expectEq(ArcTone.mix(Swatch("FF736D"), 0.04, over: Swatch("1F1F1F")).hex, "282222", "4 % de peligro sobre raised")
    expectEq(ArcTone.mix(Swatch("FFFFFF"), -1, over: Swatch("000000")).hex, "000000", "acotado abajo")
}

// The island is always dark: its text tones read on the surface they sit on.
@Test @MainActor func islandTextReadsOnTheSurface() {
    for tone in [ArcTone.foreground, ArcTone.textSecondary, ArcTone.textMuted] {
        expect(Contrast.ratio(hex: tone.hex, hex: ArcTone.surface.hex) >= 4.5, "\(tone.hex) sobre surface: 4.5:1")
    }
    expect(Contrast.ratio(hex: IslandArc.borderStrong.hex, hex: ArcTone.surface.hex)
           > Contrast.ratio(hex: ArcTone.border.hex, hex: ArcTone.surface.hex), "border-strong destaca mas que border")
}
