import CompanionUI
import CoreGraphics
import Testing

@Test @MainActor func iconGlyphTests() {
    testHouseSetIsFourGlyphs()
    testEveryGlyphPathIsNonEmpty()
    testPathScalesWithRect()
    testStrokeIsHairlineMiter()
    testDefaultSizeIsSixteen()
}

@MainActor func testHouseSetIsFourGlyphs() {
    expectEq(
        CompanionIcon.allCases,
        [.check, .clock, .cross, .folder],
        "iconos: el set de la casa, no SF")
}

@MainActor func testEveryGlyphPathIsNonEmpty() {
    let rect = CGRect(
        origin: .zero,
        size: CGSize(
            width: CompanionIconShape.viewBox,
            height: CompanionIconShape.viewBox))
    for icon in CompanionIcon.allCases {
        let path = CompanionIconShape(icon: icon).path(in: rect)
        expect(!path.isEmpty, "iconos: \(icon) tiene trazo")
    }
}

@MainActor func testPathScalesWithRect() {
    let small = CompanionIconShape(icon: .check).path(
        in: CGRect(x: 0, y: 0, width: 24, height: 24))
    let large = CompanionIconShape(icon: .check).path(
        in: CGRect(x: 0, y: 0, width: 48, height: 48))
    expect(
        large.boundingRect.width > small.boundingRect.width,
        "iconos: el path escala con el rect, no se redibuja")
}

@MainActor func testStrokeIsHairlineMiter() {
    expectEq(
        CompanionIconShape.lineWidth, Stroke.hairline,
        "iconos: trazo 1 pt fijo")
    expectEq(CompanionIconShape.miterLimit, 10, "iconos: miter 10")
}

@MainActor func testDefaultSizeIsSixteen() {
    expectEq(IconGlyph.defaultSize, 16,
             "iconos: default 16, no TypeSize")
}
