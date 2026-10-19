import CoreGraphics
import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import ImageIO
import Testing

@Test func secureFieldEgressTests() {
    testMaskedRectIsOpaqueBlackAtTheTop()
    testPixelsOutsideTheMaskKeepTheirColor()
    testFrameWithASecureFieldLeavesMaskedAsJPEG()
    testWithheldFrameProducesNoBytes()
}

private func whiteImage(width: Int, height: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// Red channel of one pixel, counted from the top row.
private func red(_ image: CGImage, x: Int, y: Int) -> Int? {
    guard let provider = image.dataProvider, let data = provider.data,
          let bytes = CFDataGetBytePtr(data) else { return nil }
    let bytesPerPixel = image.bitsPerPixel / 8
    return Int(bytes[y * image.bytesPerRow + x * bytesPerPixel])
}

private func testMaskedRectIsOpaqueBlackAtTheTop() {
    guard let source = whiteImage(width: 100, height: 100),
          let masked = ScreenCapture.paint(source, over: [CGRect(x: 10, y: 10, width: 20, height: 20)])
    else {
        expect(false, "mascara: no se pudo pintar la imagen de prueba")
        return
    }
    expectEq(red(masked, x: 15, y: 15), 0, "mascara: el rectangulo queda negro opaco")
    expectEq(red(masked, x: 29, y: 29), 0, "mascara: la esquina del rectangulo tambien")
    expectEq(red(masked, x: 15, y: 85), 255,
             "mascara: el rectangulo va arriba, no espejado desde abajo")
}

private func testPixelsOutsideTheMaskKeepTheirColor() {
    guard let source = whiteImage(width: 100, height: 100),
          let masked = ScreenCapture.paint(source, over: [CGRect(x: 10, y: 10, width: 20, height: 20)])
    else {
        expect(false, "mascara: no se pudo pintar la imagen de prueba")
        return
    }
    expectEq(red(masked, x: 9, y: 9), 255, "mascara: el pixel justo fuera no se toca")
    expectEq(red(masked, x: 50, y: 50), 255, "mascara: el resto de la pantalla no se toca")
}

private func testFrameWithASecureFieldLeavesMaskedAsJPEG() {
    guard let source = whiteImage(width: 100, height: 100) else {
        expect(false, "mascara: no se pudo crear la imagen de prueba")
        return
    }
    let shot = ScreenCapture.egress(
        source, display: CGRect(x: 0, y: 0, width: 100, height: 100),
        read: .fields([CGRect(x: 10, y: 10, width: 30, height: 30)]))
    guard case .image(let data) = shot,
          let decoder = CGImageSourceCreateWithData(data as CFData, nil),
          let decoded = CGImageSourceCreateImageAtIndex(decoder, 0, nil)
    else {
        expect(false, "mascara: el cuadro con campo seguro debe salir como JPEG")
        return
    }
    // JPEG is lossy: black and white stay far apart on either side of the cut.
    expect((red(decoded, x: 25, y: 25) ?? 255) < 32, "mascara: el campo sale negro en el JPEG")
    expect((red(decoded, x: 90, y: 90) ?? 0) > 224, "mascara: lo demas sale sin cambios")
}

private func testWithheldFrameProducesNoBytes() {
    guard let source = whiteImage(width: 100, height: 100) else {
        expect(false, "mascara: no se pudo crear la imagen de prueba")
        return
    }
    let shot = ScreenCapture.egress(
        source, display: CGRect(x: 0, y: 0, width: 100, height: 100),
        read: .incomplete("accessibility walk over budget"))
    switch shot {
    case .withheld:
        expect(true, "mascara: sin lectura completa no hay bytes")
    case .image, .failed, .skipped:
        expect(false, "mascara: un cuadro sin lectura completa no debe salir")
    }
}
