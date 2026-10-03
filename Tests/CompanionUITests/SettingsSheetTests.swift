import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// S1 of the Settings brief (ajustes-hoja-incredible, signed by Karen): the
// WIN-5 floating panel copied Incredible's first-run dev panel. Settings is a
// modal sheet centred over a scrim; every value below is checked against the
// local reference [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967].

@Test @MainActor func theScrimIsAPlainBlackVeil() {
    expectEq(SettingsSheetMetrics.scrimAlpha, 0.34, "negro al valor de la referencia local, sin blur")
    expectEq(SettingsSheetMetrics.duration, 0.2, "el fundido dura lo de la referencia local")
    expectEq(SettingsSheetMetrics.curve, MotionCurve.standard, "con la curva standard")
}

@Test @MainActor func theSheetUsesTheDialogSurface() {
    expectEq(SettingsSheetMetrics.radius, Radius.dialog, "radio de dialogo")
    expectEq(SettingsSheetMetrics.elevation, .popover, "la sombra modal es la del popover")
    expectEq(SettingsSheetMetrics.closeInset, 22, "la X se separa de la esquina lo de la referencia local")
}

@Test @MainActor func theSizeConstantsAreTheReferences() {
    expectEq(SettingsSheetMetrics.maxWidth, 1100, "ancho maximo")
    expectEq(SettingsSheetMetrics.maxHeight, 900, "alto maximo")
    expectEq(SettingsSheetMetrics.heightShare, 0.9, "fraccion del alto")
    expectEq(SettingsSheetMetrics.wideBreak, 768, "el corte ancho")
    expectEq(SettingsSheetMetrics.wideMargin, 64, "margen total desde el corte")
    expectEq(SettingsSheetMetrics.narrowMargin, 32, "margen total bajo el corte")
    expectEq(SettingsSheetMetrics.enterScale, 0.98, "escala de entrada")
    expectEq(SettingsSheetMetrics.enterLift, 4, "desplazamiento de entrada")
}

@Test @MainActor func theBreakpointSitsAt768() {
    expectEq(SettingsSheetMetrics.size(in: CGSize(width: 767, height: 500)).width, 735, "767: margen chico")
    expectEq(SettingsSheetMetrics.size(in: CGSize(width: 768, height: 500)).width, 704, "768: ya es margen grande")
    expectEq(SettingsSheetMetrics.size(in: CGSize(width: 769, height: 500)).width, 705, "769: margen grande")
    let short = SettingsSheetMetrics.size(in: CGSize(width: 1600, height: 500))
    expectEq(short, CGSize(width: 1100, height: 450), "ventana baja: el ancho topa y el alto es la fraccion")
}

@Test @MainActor func theSheetIsCappedByTheWindow() {
    let big = SettingsSheetMetrics.size(in: CGSize(width: 1600, height: 1200))
    expectEq(big, CGSize(width: 1100, height: 900), "una ventana grande topa en el maximo")

    let wide = SettingsSheetMetrics.size(in: CGSize(width: 1120, height: 700))
    expectEq(wide.width, 1120 - 64, "desde el corte ancho deja el margen grande")
    expectEq(wide.height, 700 * 0.9, "el alto es una fraccion de la ventana")

    let narrow = SettingsSheetMetrics.size(in: CGSize(width: 700, height: 500))
    expectEq(narrow.width, 700 - 32, "bajo el corte el margen es el chico")

    let edge = SettingsSheetMetrics.size(in: CGSize(width: SettingsSheetMetrics.wideBreak, height: 500))
    expectEq(edge.width, SettingsSheetMetrics.wideBreak - 64, "justo en el corte ya es ancho")

    let tiny = SettingsSheetMetrics.size(in: CGSize(width: 10, height: 0))
    expect(tiny.width >= 0 && tiny.height >= 0, "nunca un tamano negativo")
}

@Test @MainActor func theSheetEntersFromAboveAndLeavesInPlace() {
    let entering = SettingsSheetPhase.entering
    expectEq(entering.opacity, 0, "entra desde transparente")
    expectEq(entering.scale, 0.98, "y un poco mas chica")
    expectEq(entering.offsetY, -4, "y por encima de su sitio")

    let shown = SettingsSheetPhase.shown
    expectEq(shown.opacity, 1, "abierta: opaca")
    expectEq(shown.scale, 1, "a su tamano")
    expectEq(shown.offsetY, 0, "en su sitio")

    let leaving = SettingsSheetPhase.leaving
    expectEq(leaving.opacity, 0, "sale a transparente")
    expectEq(leaving.scale, 0.98, "encogiendo")
    expectEq(leaving.offsetY, 0, "sin moverse")
}

@Test @MainActor func reduceMotionDropsTheTransition() {
    expect(ChromeMotion.animation(SettingsSheetMetrics.motion, reduceMotion: true) == nil, "con Reducir movimiento no hay transicion")
    expectEq(ChromeMotion.animation(SettingsSheetMetrics.motion, reduceMotion: false),
             MotionCurve.animation(MotionCurve.standard, 0.2), "sin el, la curva y la duracion de la hoja")
}

@Test @MainActor func theSheetStaysOpenUntilItsExitEnds() {
    var sheet = SettingsSheetModel()
    expect(!sheet.isOpen, "nace cerrada")
    expect(sheet.open(animated: true), "abrir con animacion pide asentar la entrada")
    expect(sheet.isOpen, "abrir la monta")
    expectEq(sheet.phase, .entering, "y arranca en la entrada")
    sheet.settle()
    expectEq(sheet.phase, .shown, "la entrada termina abierta")

    expect(sheet.close(animated: true), "cerrar con animacion pide terminar la salida")
    expect(sheet.isOpen, "cerrando sigue montada")
    expectEq(sheet.phase, .leaving, "mientras sale")
    sheet.settle()
    expectEq(sheet.phase, .leaving, "una entrada tardia no la reabre")
    sheet.finishClose()
    expect(!sheet.isOpen, "al terminar la salida se desmonta")
    sheet.finishClose()
    expect(!sheet.isOpen, "terminar dos veces es lo mismo")
}

@Test @MainActor func reduceMotionOpensAndClosesInOneStep() {
    var sheet = SettingsSheetModel()
    expect(!sheet.open(animated: false), "sin animacion no hay entrada que asentar")
    expectEq(sheet.phase, .shown, "y aparece ya en su sitio, sin un cuadro en blanco")
    expect(!sheet.close(animated: false), "sin animacion no hay salida que esperar")
    expect(!sheet.isOpen, "se desmonta en el acto")
}

@Test @MainActor func openingAnOpenSheetKeepsItAsItIs() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    sheet.settle()
    sheet.query = "voz"
    expect(!sheet.open(animated: true), "ya abierta, abrir no repite la entrada")
    expectEq(sheet.phase, .shown, "sigue en su sitio")
    expectEq(sheet.query, "voz", "y no borra la busqueda")

    var entering = SettingsSheetModel()
    _ = entering.open(animated: true)
    expect(!entering.open(animated: true), "entrando, abrir otra vez no pide otra entrada")
    expectEq(entering.phase, .entering, "la entrada en curso sigue")
}

@Test @MainActor func aSecondCloseDuringTheExitDoesNothing() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    sheet.settle()
    _ = sheet.close(animated: true)
    expect(!sheet.canClose, "saliendo ya no se puede volver a cerrar")
    expect(!sheet.close(animated: true), "un segundo cierre no pide otra salida")
    expect(sheet.isOpen, "ni corta la que esta en curso")
    expect(!sheet.close(animated: false), "tampoco un cierre sin animacion")
    expect(sheet.isOpen, "la salida en curso termina sola")
}

@Test @MainActor func aClosedSheetIgnoresSettleCloseAndFinish() {
    var sheet = SettingsSheetModel()
    sheet.settle()
    expect(!sheet.isOpen, "asentar sin abrir no la monta")
    expect(!sheet.canClose, "cerrada no se puede cerrar")
    expect(!sheet.close(animated: true), "cerrar una hoja cerrada no pide salida")
    expect(!sheet.isOpen && sheet.phase != .leaving, "ni la deja saliendo")
}

@Test @MainActor func aCloseBeforeTheEntranceSettlesWins() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    _ = sheet.close(animated: true)
    sheet.settle()
    expectEq(sheet.phase, .leaving, "el asentado tardio no deshace el cierre")
}

@Test @MainActor func finishingWithoutAnExitDoesNothing() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    sheet.finishClose()
    expect(sheet.isOpen, "entrando, un fin de salida suelto no la cierra")
    sheet.settle()
    sheet.finishClose()
    expect(sheet.isOpen, "abierta, tampoco")
}

@Test @MainActor func reopeningWhileLeavingWinsOverTheLateFinish() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    sheet.settle()
    sheet.query = "voz"
    _ = sheet.close(animated: true)
    expect(sheet.open(animated: true), "reabrir durante la salida vuelve a entrar")
    expectEq(sheet.phase, .entering, "desde la entrada")
    expectEq(sheet.query, "", "con la busqueda limpia, como una apertura nueva")
    sheet.settle()
    sheet.finishClose()
    expect(sheet.isOpen, "el fin de la salida vieja no cierra la nueva")
}

@Test @MainActor func escapeClearsTheSearchBeforeItCloses() {
    var sheet = SettingsSheetModel()
    _ = sheet.open(animated: true)
    sheet.settle()
    sheet.query = "voz"
    expectEq(sheet.escape(), .clearedSearch, "con texto, Esc solo limpia")
    expectEq(sheet.query, "", "la busqueda queda vacia")
    expectEq(sheet.phase, .shown, "y la hoja sigue abierta")
    expectEq(sheet.escape(), .close, "el segundo Esc pide cerrar; la salida la anima quien la presenta")

    _ = sheet.close(animated: true)
    expectEq(sheet.escape(), .ignored, "saliendo, Esc ya no es suyo")

    var closed = SettingsSheetModel()
    expectEq(closed.escape(), .ignored, "con la hoja cerrada, Esc no es suyo")
}

@Test @MainActor func openingStartsWithAnEmptySearch() {
    var sheet = SettingsSheetModel()
    sheet.query = "voz"
    _ = sheet.open(animated: true)
    expectEq(sheet.query, "", "cada apertura arranca sin busqueda")
}

// QA review S1: the pure model was tested, the view that paints it was not.
@Test @MainActor func theCloseButtonIsLabelledForWhatItCloses() async {
    await Localized.scoped(to: .es) { expectEq(SettingsSheetHost.closeLabel, "Cerrar ajustes", "es") }
    await Localized.scoped(to: .en) { expectEq(SettingsSheetHost.closeLabel, "Close settings", "en") }
}

@Test @MainActor func theScrimDarkensTheWindowOnlyOnceShown() throws {
    var shown = SettingsSheetModel()
    _ = shown.open(animated: false)
    var entering = SettingsSheetModel()
    _ = entering.open(animated: true)
    let size = CGSize(width: 1120, height: 760)
    let lit = try #require(hostShot(shown, size: size))
    let clear = try #require(hostShot(entering, size: size))
    let corner = lit.pixel(x: 8, y: 8)
    let expected = 255 * (1 - SettingsSheetMetrics.scrimAlpha)
    expect(corner.count == 3 && corner.allSatisfy { abs(Double($0) - expected) < 6 },
           "fuera de la hoja: blanco bajo negro al 34 % (\(corner))")
    expect(clear.pixel(x: 8, y: 8).allSatisfy { $0 > 250 }, "entrando, el velo aun no oscurece")
}

@MainActor private func sheetHost(_ model: SettingsSheetModel) -> some View {
    SettingsSheetHost(
        model: .constant(model), tab: .constant(.general),
        preview: nil, chat: nil, updates: nil, welcome: nil, memory: nil, browser: nil, onClose: {})
        .environment(DropdownHost())
}

private struct SheetShot {
    let rep: NSBitmapImageRep
    let size: CGSize

    func pixel(x: CGFloat, y: CGFloat) -> [UInt8] {
        let scale = CGFloat(rep.pixelsWide) / size.width
        let px = Int(x * scale), py = Int(y * scale)
        guard let data = rep.bitmapData, px < rep.pixelsWide, py < rep.pixelsHigh else { return [] }
        let at = py * rep.bytesPerRow + px * rep.samplesPerPixel
        return (0..<min(3, rep.samplesPerPixel)).map { data[at + $0] }
    }
}

@MainActor private func hostShot(_ model: SettingsSheetModel, size: CGSize) -> SheetShot? {
    let view = sheetHost(model).background(Color.white).environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .aqua)
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return SheetShot(rep: rep, size: size)
}

@Test @MainActor func theSearchResultsListWhatMatchesAndSayWhenNothingDoes() throws {
    let known = try #require(SettingsInventory.searchEntries.first?.title, "the inventory has entries")
    expect(!SettingsSearch.match(known, in: SettingsInventory.searchEntries).isEmpty, "an entry finds itself")
    let hit = try #require(sheetBitmap(SettingsSearchResults(query: known, onPick: { _ in }).frame(width: 300)))
    let none = try #require(sheetBitmap(SettingsSearchResults(query: "zzzzqq", onPick: { _ in }).frame(width: 300)))
    #expect(hit != none, "matches draw rows, a miss draws the empty note")
    _ = try #require(sheetBitmap(SettingsSearchField(query: .constant(""), onSubmit: {}).frame(width: 300)))
}

@MainActor private func sheetBitmap(_ view: some View) -> Data? {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func settingsSheetGallery() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var model = SettingsSheetModel()
    _ = model.open(animated: false)
    for size in [CGSize(width: 700, height: 500), CGSize(width: 1600, height: 1200)] {
        try await saveLive(AnyView(sheetHost(model)), scheme: .light, size: size, to: out,
                           "s1-sheet-\(Int(size.width))x\(Int(size.height))")
    }
    for scheme in [ColorScheme.light, .dark] {
        let host = SettingsSheetHost(
            model: .constant(model), tab: .constant(.general),
            preview: nil, chat: nil, updates: nil, welcome: nil, memory: nil, browser: nil, onClose: {})
            .environment(DropdownHost())
        try await saveLive(AnyView(host), scheme: scheme,
                           size: CGSize(width: 1120, height: 760), to: out, "s1-sheet-\(scheme)")
    }
}
