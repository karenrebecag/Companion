import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-5b, parity round: Incredible's diagram tools are "copy image" and
// "download PNG", each with or without the background, at 2x; no view, no
// zoom; and the container scrolls sideways instead of shrinking. The text
// copy the first version had is gone (the code fallback keeps its own).

private let flow = "flowchart LR\n  A --> B"
private let withBackground = Data([0x89, 0x50, 0x4E, 0x47, 1])
private let withoutBackground = Data([0x89, 0x50, 0x4E, 0x47, 2])
private let both = DiagramImage(data: Data([1]), width: 504, height: 120, png: withBackground, pngTransparent: withoutBackground)
private let none = DiagramImage(data: Data([1]), width: 504, height: 120)

@MainActor
@Test func diagramToolsTests() {
    testPNGVariantsAreChosenByBackground()
    testFilenamesSayWhichVariant()
    testTheNaturalSizeIsNeverShrunkOrCapped()
    testToolTextsExistInBothLanguages()
}

@MainActor func testPNGVariantsAreChosenByBackground() {
    expectEq(IslandDiagramTools.pngData(both, background: true), withBackground, "16m-5b p: con fondo es el PNG con fondo")
    expectEq(IslandDiagramTools.pngData(both, background: false), withoutBackground, "16m-5b p: sin fondo es el transparente")
    expectEq(IslandDiagramTools.pngData(none, background: true), nil, "16m-5b p: sin PNG no hay herramienta")
    expectEq(IslandDiagramTools.pngData(none, background: false), nil, "16m-5b p: ni transparente")
}

@MainActor func testFilenamesSayWhichVariant() {
    expectEq(IslandDiagramTools.filename(background: true), "diagram.png", "16m-5b p: nombre con fondo")
    expectEq(IslandDiagramTools.filename(background: false), "diagram-transparent.png", "16m-5b p: nombre sin fondo")
}

@MainActor func testTheNaturalSizeIsNeverShrunkOrCapped() {
    expectEq(IslandDiagramLayout.displaySize(DiagramImage(data: Data(), width: 504, height: 3000)), CGSize(width: 504, height: 3000),
             "16m-5b p: un diagrama alto no se topa ni se encoge: el popup ya hace scroll vertical")
    expectEq(IslandDiagramLayout.displaySize(DiagramImage(data: Data(), width: 504, height: 60)), CGSize(width: 504, height: 60),
             "16m-5b p: uno bajo tampoco se agranda")
}

@MainActor func testToolTextsExistInBothLanguages() {
    for key in ["island.diagram.copy", "island.diagram.copied", "island.diagram.download",
                "island.diagram.background.on", "island.diagram.background.off"] {
        for language in [AppLanguage.en, .es] {
            let text = Localized.string(key, language: language)
            expect(text != key && !text.isEmpty, "16m-5b p: \(key) está en \(language)")
        }
    }
    let copy = Localized.string("island.diagram.copy", language: .en)
    expect(copy.lowercased().contains("image"), "16m-5b p: copiar dice que copia la imagen")
}

@MainActor
@Test func diagramCopyImageTests() {
    let board = NSPasteboard(name: NSPasteboard.Name("companion.test.diagram.tools.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.setString("previous", forType: .string)
    expect(IslandDiagramTools.copyImage(both, background: true, to: board), "16m-5b p: copiar con fondo lo logra")
    expectEq(board.data(forType: .png), withBackground, "16m-5b p: el portapapeles lleva el PNG con fondo")
    expectEq(board.string(forType: .string), nil, "16m-5b p: lo anterior se reemplaza")
    expect(IslandDiagramTools.copyImage(both, background: false, to: board), "16m-5b p: copiar sin fondo lo logra")
    expectEq(board.data(forType: .png), withoutBackground, "16m-5b p: el portapapeles lleva el PNG sin fondo")
    board.clearContents()
    board.setString("keep", forType: .string)
    expect(!IslandDiagramTools.copyImage(none, background: true, to: board), "16m-5b p: sin PNG copiar falla")
    expectEq(board.string(forType: .string), "keep", "16m-5b p: y no vacía el portapapeles")
}

@MainActor
@Test func diagramDownloadTests() async {
    var saved: [(Data, String)] = []
    let ok = await IslandDiagramTools.download(both, background: true) { data, name in saved.append((data, name)); return .saved }
    expectEq(ok, .saved, "16m-5b p: descargar con fondo lo logra")
    expectEq(saved.first?.0, withBackground, "16m-5b p: guarda el PNG con fondo")
    expectEq(saved.first?.1, "diagram.png", "16m-5b p: con su nombre")
    _ = await IslandDiagramTools.download(both, background: false) { data, name in saved.append((data, name)); return .saved }
    expectEq(saved.last?.0, withoutBackground, "16m-5b p: guarda el transparente")
    expectEq(saved.last?.1, "diagram-transparent.png", "16m-5b p: con su nombre")
    expectEq(await IslandDiagramTools.download(both, background: true) { _, _ in .cancelled }, .cancelled,
             "16m-5b p: si ella cancela el panel, es cancelado")
    expectEq(await IslandDiagramTools.download(both, background: true) { _, _ in .failed }, .failed,
             "16m-5b r3: un guardado que falla es .failed, no cancelado")
    var called = false
    let empty = await IslandDiagramTools.download(none, background: true) { _, _ in called = true; return .saved }
    expect(empty != .saved && !called, "16m-5b p: sin PNG ni se abre el panel")
}

@MainActor
@Test func diagramBackgroundToggleTests() {
    let model = IslandDiagramModel()
    expect(model.includesBackground, "16m-5b p: nace con fondo, como el contenedor")
    model.toggleBackground()
    expect(!model.includesBackground, "16m-5b p: alternar quita el fondo")
    model.toggleBackground()
    expect(model.includesBackground, "16m-5b p: y lo devuelve")
}

// MARK: - The real exports (WebKit, fast with the stand-in script)

@MainActor
@Test func diagramExportPNGTests() async {
    await watchedWeb(60, "diagramExportPNGTests") {
        let renderer = testRenderer(script: fakeMermaid(height: 60))
        let outcome = await renderer.render(DiagramBlock(source: flow), width: 504)
        guard case .image(let image) = outcome else { return expect(false, "16m-5b p: debía dibujar: \(outcome)") }
        for (name, data, transparent) in [("con fondo", image.png, false), ("sin fondo", image.pngTransparent, true)] {
            expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "16m-5b p: \(name) es un PNG")
            guard let rep = NSBitmapImageRep(data: data) else { expect(false, "16m-5b p: \(name) se decodifica"); continue }
            expectEq(rep.pixelsWide, 1008, "16m-5b p: \(name) a 2x de ancho")
            expectEq(rep.pixelsHigh, 120, "16m-5b p: \(name) a 2x de alto")
            // The PNG's own pixel values: converting them would test the profile, not the page.
            let corner = rep.colorAt(x: 500, y: 100)
            if transparent {
                expectEq(corner?.alphaComponent ?? 1, 0, "16m-5b p: sin fondo, el fondo es transparente")
            } else {
                expectEq(corner?.alphaComponent ?? 0, 1, "16m-5b p: con fondo, opaco")
                let red = Int(((corner?.redComponent ?? 0) * 255).rounded())
                expect(abs(red - 26) <= 1, "16m-5b p: con el relleno del contenedor (\(red))")
            }
        }
        expect(image.png != image.pngTransparent, "16m-5b p: son dos imágenes distintas")
    }
}

@MainActor
@Test func diagramMatteTests() {
    func image(_ pixels: [UInt8]) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = pixels
        return bytes.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: pixels.count / 4, height: 1, bitsPerComponent: 8, bytesPerRow: pixels.count,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
    // Solid red, fully clear, and half-transparent red, on white and on black.
    let onWhite = image([255, 0, 0, 255, 255, 255, 255, 255, 255, 128, 128, 255])
    let onBlack = image([255, 0, 0, 255, 0, 0, 0, 255, 128, 0, 0, 255])
    guard let onWhite, let onBlack, let matted = DiagramPNG.matte(onWhite: onWhite, onBlack: onBlack),
          let data = matted.dataProvider?.data as Data? else { return expect(false, "16m-5b p: el matting debe producir imagen") }
    let bytes = [UInt8](data)
    expectEq(Array(bytes[0 ..< 4]), [255, 0, 0, 255], "16m-5b p: un píxel sólido sigue sólido")
    expectEq(bytes[7], 0, "16m-5b p: donde se ve el fondo, alfa 0")
    expect(abs(Int(bytes[11]) - 128) <= 2, "16m-5b p: medio transparente, alfa ~128 (\(bytes[11]))")
    expect(abs(Int(bytes[8]) - 128) <= 2, "16m-5b p: y su color premultiplicado (\(bytes[8]))")
    let small = image([0, 0, 0, 255])
    let wide = image([0, 0, 0, 255, 0, 0, 0, 255])
    expect(small != nil && wide != nil && DiagramPNG.matte(onWhite: small!, onBlack: wide!) == nil,
           "16m-5b p: dos tomas de distinto tamaño no se mezclan")
}
