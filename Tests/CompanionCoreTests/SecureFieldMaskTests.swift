import CompanionCore
import CompanionTestKit
import CoreGraphics
import Foundation
import Testing

// AX boxes are global points with a top-left origin; the image is pixels of
// one display. Each case pins the mapping for one display arrangement.

@Test func secureFieldMaskTests() {
    testRetinaPointsMapToDoublePixels()
    testSecondaryDisplayAboveMainUsesItsOwnOrigin()
    testSecondaryDisplayLeftOfMainHasNegativeOrigin()
    testScaledCaptureUsesTheRealImageSize()
    testFieldOffEveryDisplayIsDropped()
    testFieldCrossingTheEdgeIsClipped()
    testUnreadableReadWithholdsTheFrame()
    testNoSecureFieldSendsTheFrameUnmasked()
    testTheTwoReadsContributeEveryBox()
    testAnIncompleteReadWithholdsWhicheverSideItIsOn()
}

private let retinaMain = CGRect(x: 0, y: 0, width: 1440, height: 900)

func testRetinaPointsMapToDoublePixels() {
    // 100,50 pt at 2x is 200,100 px; padding grows the box by 2 px a side.
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: 100, y: 50, width: 200, height: 30)],
        display: retinaMain, imageWidth: 2880, imageHeight: 1800)
    expectEq(rects, [CGRect(x: 198, y: 98, width: 404, height: 64)],
             "mascara: Retina duplica puntos a pixeles")
}

func testSecondaryDisplayAboveMainUsesItsOwnOrigin() {
    // Above the main display, so AX y is negative; the image starts at its top.
    let secondary = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: 500, y: -1000, width: 200, height: 30)],
        display: secondary, imageWidth: 1920, imageHeight: 1080)
    expectEq(rects, [CGRect(x: 498, y: 78, width: 204, height: 34)],
             "mascara: pantalla arriba de la principal usa su propio origen")
}

func testSecondaryDisplayLeftOfMainHasNegativeOrigin() {
    let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: -1820, y: 40, width: 300, height: 20)],
        display: secondary, imageWidth: 1920, imageHeight: 1080)
    expectEq(rects, [CGRect(x: 98, y: 38, width: 304, height: 24)],
             "mascara: pantalla a la izquierda, origen negativo en X")
}

func testScaledCaptureUsesTheRealImageSize() {
    // `maxSide` shrinks the image below native: the ratio comes from the image.
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: 720, y: 450, width: 144, height: 90)],
        display: retinaMain, imageWidth: 1280, imageHeight: 800)
    expectEq(rects, [CGRect(x: 638, y: 398, width: 132, height: 84)],
             "mascara: captura reducida usa el tamano real de la imagen")
}

func testFieldOffEveryDisplayIsDropped() {
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: 5000, y: 5000, width: 50, height: 20)],
        display: retinaMain, imageWidth: 2880, imageHeight: 1800)
    expect(rects.isEmpty, "mascara: un campo en otra pantalla no pinta nada aqui")
}

func testFieldCrossingTheEdgeIsClipped() {
    let secondary = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let rects = SecureFieldMask.pixelRects(
        for: [CGRect(x: -1920, y: 0, width: 50, height: 20)],
        display: secondary, imageWidth: 1920, imageHeight: 1080)
    expectEq(rects, [CGRect(x: 0, y: 0, width: 52, height: 22)],
             "mascara: el campo que cruza el borde se recorta a la imagen")
}

func testUnreadableReadWithholdsTheFrame() {
    let plan = SecureFieldMask.plan(
        read: .incomplete("window list unreadable"), display: retinaMain,
        imageWidth: 2880, imageHeight: 1800)
    expectEq(plan, .withhold("window list unreadable"),
             "mascara: sin lectura completa, el cuadro no sale")
}

func testNoSecureFieldSendsTheFrameUnmasked() {
    let plan = SecureFieldMask.plan(
        read: .fields([]), display: retinaMain, imageWidth: 2880, imageHeight: 1800)
    expectEq(plan, .mask([]), "mascara: sin campos seguros el cuadro sale tal cual")
}

func testTheTwoReadsContributeEveryBox() {
    let before = SecureFieldMask.Read.fields([CGRect(x: 0, y: 0, width: 10, height: 10)])
    let after = SecureFieldMask.Read.fields([CGRect(x: 50, y: 50, width: 10, height: 10)])
    expectEq(SecureFieldMask.union(before, after),
             .fields([CGRect(x: 0, y: 0, width: 10, height: 10),
                      CGRect(x: 50, y: 50, width: 10, height: 10)]),
             "mascara: la union de las dos lecturas conserva cada caja")
}

func testAnIncompleteReadWithholdsWhicheverSideItIsOn() {
    let fields = SecureFieldMask.Read.fields([CGRect(x: 0, y: 0, width: 10, height: 10)])
    expectEq(SecureFieldMask.union(fields, .incomplete("walk over budget")),
             .incomplete("walk over budget"),
             "mascara: una lectura incompleta despues retira el cuadro")
    expectEq(SecureFieldMask.union(.incomplete("window list unreadable"), fields),
             .incomplete("window list unreadable"),
             "mascara: una lectura incompleta antes retira el cuadro")
}
