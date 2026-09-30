import CompanionCore
@testable import CompanionUI
import Testing

// Spec 16p §4.1: one primitive per role. Each screen used to draw its own
// keycap, capsule chip, close button and icon button; these pins hold the
// shared ones to Incredible's measures (docs/research/incredible-componentes.md
// §3-§4) so a copy cannot drift back in with other numbers.

@Test @MainActor func primitivesTests() async {
    testOneKeycapCoversEveryKey()
    testOneCapsuleChipTwoDensities()
    testOneCloseButtonPerSurface()
    testIconButtonHasAnIslandSize()
    await testCloseButtonSpeaksOneLabel()
    await testAnswerPopupCloseNamesWhatItCloses()
    testCloseButtonKeepsThePressFeedback()
}

@MainActor func testOneKeycapCoversEveryKey() {
    expectEq(KeycapSize.small.elevation, .rest, "keycap sm: sin sombra, el labio basta (0 1 8 %)")
    expectEq(KeycapSize.large.elevation, .hover, "keycap lg: elevación de la rampa, no sombra a mano")
    expectEq([KeycapSize.small.lip, KeycapSize.large.lip], [Stroke.hairline, Stroke.medium],
             "keycap: labio de 1 en sm y de 2 en lg")
    expectEq(KeycapSize.lipAlpha, 0.08, "keycap: labio negro al 8 %")
    let hero = KeycapSize.hero
    expectEq(hero.side, 72, "keycap de bienvenida: cuadrado de 72")
    expect(hero.mono, "keycap de bienvenida: en mono")
    expectEq(hero.fontSize, TypeSize.title, "keycap de bienvenida: tamaño de título")
    expectEq([hero.radius, hero.lip], [KeycapSize.large.radius, KeycapSize.large.lip],
             "keycap de bienvenida: es el lg, no otra pieza")
    expectEq(hero.elevation, KeycapSize.large.elevation, "keycap de bienvenida: misma elevación que lg")
    expect(KeycapSize.small.side == nil && KeycapSize.large.side == nil,
           "keycap sm/lg: abrazan su texto")
}

@MainActor func testOneCapsuleChipTwoDensities() {
    expectEq([ChipDensity.compact.paddingX, ChipDensity.compact.paddingY], [12, 6],
             "chip compacto (isla): 12 × 6")
    expectEq([ChipDensity.regular.paddingX, ChipDensity.regular.paddingY], [16, 8],
             "chip regular (bienvenida): 16 × 8")
}

@MainActor func testOneCloseButtonPerSurface() {
    expectEq(CloseButtonVariant.window.size, IconButtonSize.close,
             "cerrar ventana: el círculo de 32 de Incredible")
    expectEq(IconButtonSize.close.side, 32, "cerrar ventana: 32")
    expect(IconButtonSize.close.filled, "cerrar ventana: fondo 5 % siempre")
    expectEq(CloseButtonVariant.island.size.side, IslandInk.slotSide, "cerrar isla: 22, el hueco de la isla")
    expect(CloseButtonVariant.island.size.filled, "cerrar isla: con fondo, como el del popup")
    // 16m-3: the only × over a picture is ci-att-card's remove, measured
    // at 24 (incredible-isla-componentes.md §3); it no longer borrows the 22.
    expectEq(CloseButtonVariant.onMedia.size, IconButtonSize.attachmentRemove,
             "cerrar sobre imagen: el quitar de la tarjeta de adjunto, 24 medido")
    expectEq(CloseButtonVariant.window.tone, .window, "cerrar ventana: tinta de ventana")
    expectEq(CloseButtonVariant.island.tone, .island, "cerrar isla: tinta de isla")
    expectEq(CloseButtonVariant.onMedia.tone, .onMedia, "cerrar sobre imagen: disco oscuro")
}

@MainActor func testIconButtonHasAnIslandSize() {
    expectEq([IconButtonSize.island.side, IconButtonSize.island.glyph], [IslandFieldMetrics.tool, 18],
             "botón de icono de isla: llena el hueco de herramienta del campo (30, de la captura), icono 18")
    expectEq(IconButtonSize.island.point, 18,
             "botón de icono de isla: el glifo se dibuja a 18 pt medidos, sin reducción óptica")
    expect(IconButtonSize.island.point >= 16, "botón de icono de isla: nunca más chico que los 16 pt de antes")
    expectEq(IconButtonSize.small.point, 16 * IconButtonSize.opticalScale,
             "botón de icono de ventana: sigue con la reducción óptica")
    expect(!IconButtonSize.small.filled && !IconButtonSize.medium.filled && !IconButtonSize.island.filled,
           "botón de icono: sin fondo en reposo")
    expectEq(IconButtonSize.opticalScale, 0.8, "botón de icono: el glifo SF se dibuja al 80 % de su caja")
}

@MainActor func testCloseButtonSpeaksOneLabel() async {
    await Localized.scoped(to: .en) {
        expectEq(CloseButton.label, "Close", "cerrar: una sola etiqueta, en")
    }
    await Localized.scoped(to: .es) {
        expectEq(CloseButton.label, "Cerrar", "cerrar: una sola etiqueta, es")
    }
}

/// Review 16p-2: the popup's × said "Close the answer" before it joined the
/// shared button; VoiceOver keeps hearing what it closes.
@MainActor func testAnswerPopupCloseNamesWhatItCloses() async {
    await Localized.scoped(to: .en) {
        expectEq(AnswerPopupView.closeLabel, "Close the answer", "popup: cerrar dice qué cierra, en")
    }
    await Localized.scoped(to: .es) {
        expectEq(AnswerPopupView.closeLabel, "Cerrar la respuesta", "popup: cerrar dice qué cierra, es")
        expect(AnswerPopupView.closeLabel != CloseButton.label, "popup: no la etiqueta genérica")
    }
}

/// Review 16p-2: the window ×'s were Pressable before the merge; the shared
/// button keeps that press.
@MainActor func testCloseButtonKeepsThePressFeedback() {
    for variant in [CloseButtonVariant.window, .island, .onMedia] {
        expect(variant.pressable, "cerrar \(variant): cede al pulsar, como antes")
    }
}
