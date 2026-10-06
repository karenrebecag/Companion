import CompanionCore
import CompanionTestKit
import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16l: component measurements taken from Incredible's shipped CSS and
// component variants (docs/research/incredible-componentes.md).

@Test @MainActor func incredibleComponentsTests() {
    testLightPaletteMatchesIncredible()
    testStatePaletteMatchesIncredible()
    testShadowsMatchIncredible()
    testCurvesMatchIncredible()
    testButtonMetricsMatchIncredible()
    testIconButtonAndCloseMatchIncredible()
    testKeycapsMatchIncredible()
}

@MainActor func testLightPaletteMatchesIncredible() {
    expectEq(
        [Palette.canvas, Palette.surface, Palette.surfaceSecondary,
         Palette.surfaceInset, Palette.textPrimary, Palette.textSecondary,
         Palette.textMuted, Palette.textFaint, Palette.borderDefault,
         Palette.borderInput, Palette.borderChrome].map(\.hex),
        ["FCFCFC", "FFFFFF", "F9F9F9", "E5E5EA", "1C1C1E", "6C6C70",
         "727276", "8E8E93", "E5E5EA", "E0E0E5", "EEEEEE"],
        "16l paleta clara")
    expectEq(
        [Palette.statusGreen, Palette.statusOrange, Palette.statusRed,
         Palette.danger, Palette.dangerHover, Palette.link].map(\.hex),
        ["34C759", "FF9500", "FF3B30", "DC2626", "B91C1C", "007AFF"],
        "16l estado y peligro")
}

@MainActor func testStatePaletteMatchesIncredible() {
    expectEq(
        [StateAlpha.hover, StateAlpha.active, StateAlpha.row, StateAlpha.statusMuted,
         StateAlpha.dangerWash, StateAlpha.dangerWashHover, StateAlpha.disabled],
        [0.02, 0.05, 0.05, 0.12, 0.10, 0.15, 0.5],
        "16l estados: hover 2 %, activo 5 %, fila 5 %, estado apagado 12 %")
}

@MainActor func testShadowsMatchIncredible() {
    // CSS blur is twice SwiftUI's radius.
    expectEq(
        Elevation.allCases.map(\.shadowRadius), [0, 5, 10, 24, 50],
        "16l sombras: card / raised / popup / modal")
    expectEq(Elevation.allCases.map(\.shadowY), [0, 4, 6, 16, 32], "16l sombras: y")
    expectEq(Elevation.allCases.map(\.shadowOpacity), [0, 0.04, 0.08, 0.14, 0.2],
             "16l sombras: opacidad")
}

@MainActor func testCurvesMatchIncredible() {
    expectEq(MotionCurve.standard, [0.4, 0, 0.2, 1], "16l curva standard")
    expectEq(MotionCurve.settle, [0.32, 0.72, 0, 1], "16l curva settle")
    expectEq(MotionCurve.glide, [0.22, 1, 0.36, 1], "16l curva glide")
    expectEq(MotionCurve.bounce, [0.34, 1.56, 0.64, 1], "16l curva bounce")
    expectEq(MotionCurve.enter, MotionCurve.glide, "16l la entrada ya era glide")
}

@MainActor func testButtonMetricsMatchIncredible() {
    expectEq(ButtonMetrics.height, 40, "16l botón md: alto 40")
    expectEq(ButtonMetrics.padding, 20, "16l botón md: padding 20")
    expectEq(ButtonMetrics.ghostPadding, 16, "16l ghost: padding 16")
    expectEq([ButtonMetrics.heroPaddingX, ButtonMetrics.heroPaddingY], [24, 12],
             "16l botón hero: 24 × 12")
    expectEq(ButtonMetrics.hoverScale, 1.03, "16l botón: crece 3 % al pasar")
    expectEq(ButtonMetrics.welcomeHeight, 46, "16l botón de bienvenida: alto 46")
    expectEq(ButtonMetrics.welcomePadding, 30, "16l botón de bienvenida: padding 30")

    let primary = ControlLook.button(.primary, .normal)
    expectEq(primary.fill, .ink, "16l primario: negro, no acento")
    expectEq(primary.ink, .onInk, "16l primario: texto blanco")
    let secondary = ControlLook.button(.secondary, .normal)
    expectEq(secondary.fill, .wash, "16l secundario: ghost gris 5 %")
    expectEq(secondary.stroke, .none, "16l secundario: sin borde")
    expectEq(ControlLook.button(.primary, .hover).scale, 1.03, "16l hover: escala")
    expectEq(ControlLook.button(.primary, .hover).elevation, .rest, "16l hover: sin sombra")
    let disabled = ControlLook.button(.primary, .disabled)
    expectEq(disabled.opacity, 0.5, "16l disabled: 50 %")
    expectEq(disabled.fill, .ink, "16l disabled: mismo relleno")
}

@MainActor func testIconButtonAndCloseMatchIncredible() {
    expectEq([IconButtonSize.small.side, IconButtonSize.medium.side], [28, 34],
             "16l botón de icono: 28 / 34")
    expectEq([IconButtonSize.small.glyph, IconButtonSize.medium.glyph], [16, 18],
             "16l botón de icono: glifo 16 / 18")
    expectEq(IconButtonSize.close.side, 32, "16l cerrar: 32")
}

@MainActor func testKeycapsMatchIncredible() {
    let small = KeycapSize.small, large = KeycapSize.large
    expectEq([small.radius, small.paddingX, small.paddingY, small.fontSize],
             [4, 6, 2, 10], "16l keycap sm")
    expectEq([large.radius, large.paddingX, large.paddingY, large.fontSize],
             [12, 16, 8, 16], "16l keycap lg")
}

// MARK: - 16l-2: switch, select, menu

@Test @MainActor func incredibleControlsTests() {
    testSwitchGeometryMatchesIncredible()
    testSelectMatchesIncredible()
    testMenuMatchesIncredible()
}

@MainActor func testSwitchGeometryMatchesIncredible() {
    let md = SwitchGeometry.medium, sm = SwitchGeometry.small
    expectEq([md.width, md.height, md.thumb], [38, 23, 19], "16l switch md")
    expectEq([sm.width, sm.height, sm.thumb], [28, 16, 12], "16l switch sm")
    // The thumb travels the track minus itself and both pads.
    expectEq(md.travel, 15, "16l switch md: recorrido 38 − 19 − 2 × 2")
    expectEq(sm.travel, 12, "16l switch sm: recorrido 28 − 12 − 2 × 2")
    expectEq(SwitchGeometry.offTrackAlpha, 0.16, "16l switch: apagado negro 16 %")
    expectEq(SwitchGeometry.duration, 0.22, "16l switch: 0.22 s settle")
}

@MainActor func testSelectMatchesIncredible() {
    expectEq([SelectMetrics.height, SelectMetrics.smallHeight], [42, 34], "16l select: 42 / 34")
    expectEq([SelectMetrics.paddingX, SelectMetrics.gap, SelectMetrics.radius], [12, 8, 14],
             "16l select: padding 12, gap 8, radio 14")
}

@MainActor func testMenuMatchesIncredible() {
    expectEq([MenuMetrics.padding, MenuMetrics.gap, MenuMetrics.radius], [6, 2, 18],
             "16l menú: padding 6, gap 2, radio 18")
    expectEq([MenuMetrics.itemPaddingY, MenuMetrics.itemPaddingX, MenuMetrics.itemRadius,
              MenuMetrics.itemGap], [8, 10, 8, 10], "16l ítem: 8 × 10, radio 8, gap 10")
    expectEq(MenuMetrics.islandWidth, 230, "16l menú de la isla: 230")
    expectEq(MenuMetrics.enterScale, 0.97, "16l menú: entra desde 0.97")
    expectEq(MenuMetrics.duration, 0.2, "16l menú: 0.2 s")
    expectEq(MenuMetrics.duration, MotionTime.base, "16p menú: la duración sale de MotionTime, no de un literal")
}

// MARK: - 16l-3: cards

@Test @MainActor func incredibleCardsTests() {
    testElevatedCardMatchesIncredible()
    testActionCardMatchesIncredible()
    testActionHaloFollowsThePointer()
    testStatusDotMatchesIncredible()
}

@MainActor func testElevatedCardMatchesIncredible() {
    expectEq(CardChrome.radius, 16, "16l tarjeta elevada: radio 16")
    expectEq(CardChrome.padding, 16, "16l tarjeta elevada: padding 16")
}

@MainActor func testActionCardMatchesIncredible() {
    expectEq([ActionCardMetrics.paddingTop, ActionCardMetrics.paddingX,
              ActionCardMetrics.paddingBottom, ActionCardMetrics.gap, ActionCardMetrics.radius],
             [24, 24, 26, 24, 28], "16l action card: 24/24/26, gap 24, radio 28")
    expectEq(ActionCardMetrics.haloWidth, 1.3, "16l halo: 130 % del ancho")
    expectEq([ActionCardMetrics.haloRest, ActionCardMetrics.haloHover], [0.6, 1],
             "16l halo: 60 % en reposo, 100 % al pasar")
    expectEq(ActionCardMetrics.haloDuration, 0.9, "16l halo: sigue en 0.9 s settle")
}

@MainActor func testActionHaloFollowsThePointer() {
    let size = CGSize(width: 300, height: 200)
    expectEq(ActionCardHalo.center(pointer: CGPoint(x: 40, y: 60), in: size),
             CGPoint(x: 40, y: 60), "16l halo: dentro, sigue al cursor")
    expectEq(ActionCardHalo.center(pointer: nil, in: size), CGPoint(x: 300, y: 0),
             "16l halo: sin cursor, descansa en la esquina superior derecha")
    expectEq(ActionCardHalo.center(pointer: CGPoint(x: 500, y: -20), in: size),
             CGPoint(x: 300, y: 0), "16l halo: nunca sale de la tarjeta")
}

@MainActor func testStatusDotMatchesIncredible() {
    expectEq(StatusDot.side, 8, "16l punto de estado: 8")
}

// MARK: - 16l-4: island pieces

@Test @MainActor func incredibleIslandTests() {
    testIslandInkMatchesIncredible()
    testAnswerOptionMatchesIncredible()
    testReferentChipMatchesIncredible()
    testCaptureCardsMatchIncredible()
    testAnswerPopupMatchesIncredible()
    testActingLineSplitsVerbAndReferents()
}

@MainActor func testIslandInkMatchesIncredible() {
    expectEq([IslandPalette.accent.hex, IslandPalette.error.hex],
             [ArcTone.accent.hex, ArcTone.danger.hex], "isla Arc: acento y error son los tonos de Arc")
    expectEq(IslandMetrics.sendSide, 30, "16l isla: enviar 30")
    expectEq(IslandMetrics.openRadius, 28, "16l isla: radio abierta 28")
}

@MainActor func testAnswerOptionMatchesIncredible() {
    expectEq([AnswerOptionMetrics.paddingY, AnswerOptionMetrics.paddingX,
              AnswerOptionMetrics.radius, AnswerOptionMetrics.gap], [11, 12, 12, 11],
             "16l opción: 11 × 12, radio 12, gap 11")
}

@MainActor func testReferentChipMatchesIncredible() {
    expectEq([ReferentChipMetrics.paddingLeading, ReferentChipMetrics.paddingTrailing,
              ReferentChipMetrics.paddingY, ReferentChipMetrics.size, ReferentChipMetrics.maxWidth],
             [8, 8, 2, 12.5, 230], "chip de referencia: badge info de Arc")
    expectEq([ReferentChipMetrics.fill, ReferentChipMetrics.stroke], [0.12, 0.24],
             "badge info: acento al 12 %, borde al 24 %")
}

@MainActor func testCaptureCardsMatchIncredible() {
    expectEq([CaptureCardMetrics.height, CaptureCardMetrics.radius], [64, 6], "16l captura: 64, radio 6")
    expectEq(CaptureKind.allCases.map(\.width), [120, 96, 120, 140],
             "16l captura: texto 120, pantalla 96, archivo 120, tarea 140")
}

@MainActor func testAnswerPopupMatchesIncredible() {
    expectEq(AnswerPopupMetrics.maxWidth, 580, "16l popup: 580")
    expectEq(AnswerPopupMetrics.width(screen: 600), 456, "16l popup: 76 % de la pantalla si es menor")
    expectEq([AnswerPopupMetrics.paddingTop, AnswerPopupMetrics.paddingX,
              AnswerPopupMetrics.paddingBottom], [18, 22, 16], "16l popup: 18/22/16")
}

@MainActor func testActingLineSplitsVerbAndReferents() {
    let parts = ReferentLine.parts(["Safari", "", "Notas"], language: .es)
    expectEq(parts.verb, "Abriendo", "16l acting: el verbo va en texto")
    expectEq(parts.referents, ["Safari", "Notas"], "16l acting: cada objetivo es un chip")
    expectEq(ReferentLine.parts([], language: .en).verb, "Acting…", "16l acting: sin objetivos, la frase de siempre")
}

// MARK: - Review 16l: a disabled switch stays disabled for VoiceOver

@Test @MainActor func incredibleSwitchDisabledTests() {
    expectEq(IncredibleSwitch.write(true, over: false, enabled: false), false,
             "16l switch: desactivado, VoiceOver no lo cambia")
    expectEq(IncredibleSwitch.write(true, over: false, enabled: true), true,
             "16l switch: activo, el cambio pasa")
}
