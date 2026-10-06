import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

// Wave 16m-3 (spec 16m §2, D1): the clip attaches in the island. The picker
// feeds the same staging the window uses and never opens the window; staged
// files become Incredible's 84 × 102 cards, captures stack at 96 × 64 with a
// count, and the drop zone takes its measured 36-high dashed shape. Measures
// from docs/research/incredible-isla-componentes.md §3, pinned before any view.

@Test @MainActor func island16m3MetricsTests() {
    testAttachCardMeasuresMatchIncredible()
    testCaptureStackAndStripMeasuresMatchIncredible()
    testDropZoneMeasuresMatchIncredible()
    testTheRemoveCircleIsTheMeasuredOne()
}

@Test @MainActor func island16m3ProjectionTests() async {
    testCapturesAreToldApartFromFilesByTheirOwnName()
    testCardsKeepTheStagedOrderAndFailuresGoLast()
    testOneCaptureIsAStackWithoutBadge()
    testManyCapturesStackNewestOnTopWithTheirCount()
    testAnOpenStackBecomesTheStrip()
    testNothingStagedIsNothingToShow()
    testTheRowFadesOnlyWhenItOverflows()
    testTheExtensionBadgeReadsTheFileType()
    testRemovingAFailureKeepsTheRest()
    await testRemovingFromTheChatUpdatesTheStack()
    testThePickerKeepsTheFieldOpen()
    await testTheAttachWordsAreInBothLanguages()
}

@Test @MainActor func island16m3PickerTests() async {
    await testTheClipPicksInTheIslandAndNeverOpensTheWindow()
    await testThePickerFeedsTheSameStagingAsTheChat()
    await testACancelledPickerStagesNothing()
    await testAFailedAttachBecomesAnErrorCard()
    await testWithoutAPickerTheIslandSaysSo()
    testTheThumbnailIsLocalAndBounded()
}

// MARK: - Measures

@MainActor func testAttachCardMeasuresMatchIncredible() {
    expectEq([IslandAttachMetrics.cardWidth, IslandAttachMetrics.cardHeight], [84, 102],
             "16m-3 tarjeta: 84 × 102")
    expectEq([IslandAttachMetrics.cardRadius, IslandAttachMetrics.cardPadding], [10, 8],
             "16m-3 tarjeta: radio 10, padding 8")
    expectEq([IslandAttachMetrics.cardFill.hex, IslandAttachMetrics.cardRim.hex],
             [ArcTone.surface.hex, ArcTone.border.hex], "tarjeta Arc: surface bajo border")
    expectEq(IslandAttachMetrics.errorRim.hex, ArcTone.mix(ArcTone.danger, 0.26, over: ArcTone.border).hex,
             "tarjeta con error: borde rojo al 26 %, como el archivo fallido de Arc")
    expectEq(IslandAttachMetrics.errorFill.hex, ArcTone.mix(ArcTone.danger, 0.1, over: ArcTone.surface).hex,
             "tarjeta con error: el fondo del badge de peligro")
    expectEq([IslandAttachMetrics.nameSize, IslandAttachMetrics.nameLineHeight], [12, 16],
             "16m-3 nombre: 12 con interlineado 16")
    expectEq([IslandAttachMetrics.extSize, IslandAttachMetrics.extTracking], [10, 0.04],
             "16m-3 extensión: 10 con +0.04em")
    expectEq([IslandAttachMetrics.extPaddingY, IslandAttachMetrics.extPaddingX,
              IslandAttachMetrics.extRadius], [3, 6, 5], "16m-3 extensión: 3 × 6, radio 5")
    expectEq(IslandAttachMetrics.extFill.hex, ArcTone.surfaceMuted.hex, "extensión: badge neutro de Arc")
    expectEq([IslandAttachMetrics.rowGap, IslandAttachMetrics.rowPaddingTop,
              IslandAttachMetrics.rowPaddingTrailing], [8, 12, 12],
             "16m-3 fila de chips: gap 8, padding 12 / 12 / 0 / 0")
    expectEq(IslandAttachMetrics.noteSeconds, 6, "16i-2 nota bajo el campo: 6 s, como un aviso")
}

@MainActor func testCaptureStackAndStripMeasuresMatchIncredible() {
    expectEq([IslandAttachMetrics.stackWidth, IslandAttachMetrics.stackHeight], [96, 64],
             "16m-3 pila de capturas: 96 × 64")
    expectEq([IslandAttachMetrics.badgeHeight, IslandAttachMetrics.badgeRadius,
              IslandAttachMetrics.badgeSize], [18, 6, 10], "16m-3 insignia: 18 de alto, radio 6, 10 px")
    expectEq([IslandAttachMetrics.stripGap, IslandAttachMetrics.stripPaddingTop,
              IslandAttachMetrics.stripPaddingX], [6, 10, 10], "16m-3 tira de capturas: gap 6, padding 10 / 10 / 0")
    expectEq(IslandAttachMetrics.stackWidth, CaptureKind.screenshot.width,
             "16m-3 pila: la misma captura de 96 que ya pinta la isla, no otra")
}

@MainActor func testDropZoneMeasuresMatchIncredible() {
    expectEq(IslandDropMetrics.height, 36, "16m-3 zona para soltar: alto 36")
    expectEq(IslandDropMetrics.paddingX, 16, "16m-3 zona para soltar: padding 0 × 16")
    expectEq(IslandDropMetrics.dashWidth, 1, "zona Arc: discontinuo de 1")
    expectEq(IslandDropMetrics.restStroke.hex, IslandArc.borderStrong.hex, "zona Arc: border-strong en reposo")
    expectEq([IslandDropMetrics.radius, IslandDropMetrics.textSize], [12, 12],
             "16m-3 zona para soltar: radio 12, texto 12")
}

@MainActor func testTheRemoveCircleIsTheMeasuredOne() {
    expectEq(CloseButtonVariant.onMedia.size.side, 24, "16m-3 quitar: círculo de 24")
    expect(CloseButtonVariant.onMedia.size.filled, "16m-3 quitar: siempre sobre su disco")
    expectEq(IslandAttachMetrics.removeFill.hex, "141519", "16m-3 quitar: fondo #141519")
    expectEq([IslandAttachMetrics.removeFillAlpha, IslandAttachMetrics.removeBorder], [0.9, 0.3],
             "16m-3 quitar: fondo al 90 %, borde blanco 30 %")
}

// MARK: - Projection

private func ref(_ name: String, _ kind: AttachmentKind = .file) -> AttachmentRef {
    AttachmentRef(name: name, path: "/tmp/" + name, kind: kind, byteCount: 4)
}

private func capture(_ n: Int) -> AttachmentRef {
    ref(RegionCapture.fileName(id: UUID()), .image)
}

@MainActor func testCapturesAreToldApartFromFilesByTheirOwnName() {
    expect(RegionCapture.isCapture(name: RegionCapture.fileName(id: UUID())),
           "captura: el nombre que pone la isla la delata")
    expect(!RegionCapture.isCapture(name: "foto.png"), "captura: una imagen cualquiera es un archivo")
    expect(!RegionCapture.isCapture(name: "captura-notas.txt"), "captura: solo PNG")
}

@MainActor func testCardsKeepTheStagedOrderAndFailuresGoLast() {
    let failed = IslandAttachFailure(name: "enorme.mov")
    let model = IslandAttachTrayModel.project(
        staged: [ref("a.pdf"), capture(1), ref("b.png", .image), ref("c.txt")],
        failed: [failed], expanded: false)
    expectEq(model.cards.map(\.name), ["a.pdf", "b.png", "c.txt", "enorme.mov"],
             "tarjetas: en el orden en que se adjuntaron, las fallidas al final")
    expectEq(model.cards.map(\.isError), [false, false, false, true], "tarjetas: solo la fallida en error")
    expectEq(model.stack?.count, 1, "tarjetas: la captura no entra en la fila, va a la pila")
}

@MainActor func testOneCaptureIsAStackWithoutBadge() {
    let only = capture(1)
    let model = IslandAttachTrayModel.project(staged: [only], failed: [], expanded: false)
    expectEq(model.stack?.top, only, "pila: una captura se ve sola")
    expectEq(model.stack?.badge, nil, "pila: sin insignia con una sola")
    expect(model.strip.isEmpty, "pila: sin tira")
    let opened = IslandAttachTrayModel.project(staged: [only], failed: [], expanded: true)
    expectEq(opened.stack?.top, only, "pila: con una sola no hay nada que desplegar")
}

@MainActor func testManyCapturesStackNewestOnTopWithTheirCount() {
    let first = capture(1), second = capture(2), third = capture(3)
    let model = IslandAttachTrayModel.project(
        staged: [first, ref("a.pdf"), second, third], failed: [], expanded: false)
    expectEq(model.stack?.top, third, "pila: la última captura arriba")
    expectEq(model.stack?.count, 3, "pila: cuenta las tres")
    expectEq(model.stack?.badge, "3", "pila: insignia con el número")
    expectEq(model.cards.map(\.name), ["a.pdf"], "pila: los archivos siguen en su fila")
}

@MainActor func testAnOpenStackBecomesTheStrip() {
    let first = capture(1), second = capture(2)
    let model = IslandAttachTrayModel.project(staged: [first, second], failed: [], expanded: true)
    expectEq(model.stack, nil, "tira: la pila abierta deja de ser pila")
    expectEq(model.strip, [second, first], "tira: todas las capturas, la última primero")
}

@MainActor func testNothingStagedIsNothingToShow() {
    let model = IslandAttachTrayModel.project(staged: [], failed: [], expanded: true)
    expect(model.isEmpty, "bandeja: sin adjuntos no se pinta nada")
    expectEq(model.stack, nil, "bandeja: sin pila")
    expect(!IslandAttachTrayModel.project(staged: [], failed: [IslandAttachFailure(name: "x")],
                                          expanded: false).isEmpty,
           "bandeja: un fallo también se enseña")
}

@MainActor func testTheRowFadesOnlyWhenItOverflows() {
    let three = IslandAttachTrayModel.project(
        staged: [ref("a.pdf"), ref("b.pdf"), ref("c.pdf")], failed: [], expanded: false)
    // 3 × 84 + 2 × 8 + 12 of trailing padding = 280.
    expectEq(three.rowWidth, 280, "fila: tres tarjetas, dos huecos y el padding final")
    expect(!three.overflows(available: 460), "fila: cabe en la isla abierta, sin desvanecido")
    expect(three.overflows(available: 279), "fila: un punto menos y se desvanece al final")
    let stacked = IslandAttachTrayModel.project(
        staged: [capture(1), ref("a.pdf")], failed: [], expanded: false)
    expectEq(stacked.rowWidth, 96 + 8 + 84 + 12, "fila: la pila cuenta con sus 96")
}

@MainActor func testTheExtensionBadgeReadsTheFileType() {
    expectEq(IslandAttachLabel.ext("informe.pdf"), "PDF", "extensión: en mayúsculas")
    expectEq(IslandAttachLabel.ext("Foto.Final.jpeg"), "JPEG", "extensión: la última")
    expectEq(IslandAttachLabel.ext("Makefile"), nil, "extensión: sin extensión no hay insignia")
    expectEq(IslandAttachLabel.ext(".env"), nil, "extensión: un archivo oculto no es una extensión")
}

@MainActor func testRemovingAFailureKeepsTheRest() {
    let a = IslandAttachFailure(name: "a.mov"), b = IslandAttachFailure(name: "b.mov")
    expectEq(IslandAttachFailure.removing(a.id, from: [a, b]), [b], "fallo: quitarlo deja los demás")
    expectEq(IslandAttachFailure.removing(UUID(), from: [a, b]), [a, b], "fallo: un id ajeno no quita nada")
}

@MainActor func testRemovingFromTheChatUpdatesTheStack() async {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config(),
                             attachments: MemoryAttachments())
    let names = (1 ... 3).map { _ in RegionCapture.fileName(id: UUID()) } + ["nota.pdf"]
    for name in names { _ = chat.attach(URL(fileURLWithPath: "/tmp/" + name)) }
    var model = IslandAttachTrayModel.project(staged: chat.pendingAttachments, failed: [], expanded: false)
    expectEq(model.stack?.count, 3, "quitar: tres capturas en la pila")
    // The stack's × takes back its top capture, the one on view.
    if let top = model.stack?.top { chat.removePending(top) }
    model = IslandAttachTrayModel.project(staged: chat.pendingAttachments, failed: [], expanded: false)
    expectEq(model.stack?.count, 2, "quitar: la pila baja a dos")
    expectEq(model.stack?.top.name, names[1], "quitar: la siguiente más nueva queda arriba")
    for ref in chat.pendingAttachments where RegionCapture.isCapture(name: ref.name) {
        chat.removePending(ref)
    }
    model = IslandAttachTrayModel.project(staged: chat.pendingAttachments, failed: [], expanded: false)
    expectEq(model.stack, nil, "quitar: sin capturas no hay pila")
    expectEq(model.cards.map(\.name), ["nota.pdf"], "quitar: la tarjeta del archivo sigue")
}

@MainActor func testThePickerKeepsTheFieldOpen() {
    expect(IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                  staged: 0, mainInFront: false, picking: true),
           "selector abierto: la isla no se cierra debajo")
    expect(IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                  staged: 0, mainInFront: true, picking: true),
           "selector abierto: aunque la ventana pase delante al activar la app")
    expect(!IslandComposing.active(focused: false, draft: "", confirmingClear: false,
                                   staged: 0, mainInFront: false, picking: false),
           "selector cerrado sin nada: vuelve a reposo")
}

@MainActor func testTheAttachWordsAreInBothLanguages() async {
    let keys = ["island.attach.captures", "island.attach.failed", "island.attach.pickerUnavailable",
                "island.attach.openCaptures"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in keys {
                expect(Localized.string(key) != key, "\(language): \(key) está en el catálogo")
            }
        }
    }
}

// MARK: - The picker

private final class Recorder {
    var shows = 0
    var picks = 0
    var said: [String] = []
    var failures: [IslandAttachFailure] = []
}

@MainActor private func chatWith(_ store: (any AttachmentStoring)?) -> ChatViewModel {
    ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                  store: MemoryConversationStore(), config: Config(), attachments: store)
}

@MainActor private func actions(_ chat: ChatViewModel, _ recorder: Recorder,
                                picked: [URL]?) -> IslandAttachActions {
    let voice = VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter())
    var pick: IslandFilePicker?
    if let picked {
        pick = { @MainActor in
            recorder.picks += 1
            return picked
        }
    }
    return IslandAttachActions(chat: chat, voice: voice, grabber: nil,
                               say: { recorder.said.append($0) }, pickFiles: pick,
                               onFail: { recorder.failures.append($0) })
}

/// A scratch folder with one regular file, a folder and a link to the file.
private func scratch() throws -> (root: URL, file: URL, folder: URL, link: URL) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString)", isDirectory: true)
    let folder = root.appendingPathComponent("carpeta", isDirectory: true)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("nota.txt")
    try Data("hola".utf8).write(to: file)
    let link = root.appendingPathComponent("enlace.txt")
    try fm.createSymbolicLink(at: link, withDestinationURL: file)
    return (root, file, folder, link)
}

@MainActor func testTheClipPicksInTheIslandAndNeverOpensTheWindow() async {
    let recorder = Recorder()
    let chat = chatWith(MemoryAttachments())
    let view = IslandView(
        chat: chat, voice: VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter()),
        hold: HoldSettingsModel(permission: FakeAccessibility(trusted: true)),
        onShowMain: { recorder.shows += 1 }, onSize: { _, _ in },
        pickFiles: { recorder.picks += 1; return [] })
    await view.pickAttach(.chooseFile)?.value
    expectEq(recorder.picks, 1, "clip: «Elegir archivo…» abre el selector desde la isla")
    expectEq(recorder.shows, 0, "clip: nunca abre la ventana principal (D1)")
}

@MainActor func testThePickerFeedsTheSameStagingAsTheChat() async {
    do {
        let disk = try scratch()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let recorder = Recorder()
        let chat = chatWith(MemoryAttachments())
        await actions(chat, recorder, picked: [disk.folder, disk.file, disk.link]).chooseFiles()
        expectEq(chat.pendingAttachments.map(\.name), ["nota.txt"],
                 "selector: lo elegido entra en los adjuntos del chat, los mismos que ve la ventana")
        // Review 16m-3: filtered, but said — see testWhatThePickerCannotTakeIsSaidNotSwallowed.
        expectEq(recorder.failures.map(\.name), ["carpeta", "enlace.txt"],
                 "selector: carpeta y enlace no entran, y se ven como tarjetas en error")
    } catch {
        expect(false, "selector: preparar el disco no debe fallar (\(error))")
    }
}

@MainActor func testACancelledPickerStagesNothing() async {
    let recorder = Recorder()
    let chat = chatWith(MemoryAttachments())
    await actions(chat, recorder, picked: []).chooseFiles()
    expect(chat.pendingAttachments.isEmpty, "selector cancelado: nada entra")
    expect(recorder.said.isEmpty && recorder.failures.isEmpty, "selector cancelado: tampoco se dice nada")
}

private final class RefusingAttachments: AttachmentStoring, @unchecked Sendable {
    func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef { throw AttachmentError.tooLarge }
    func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef {
        throw AttachmentError.tooLarge
    }
    func restore(path: String) -> AttachmentRef? { nil }
    func discard(_ ref: AttachmentRef) {}
    func payload(for ref: AttachmentRef) -> AttachmentPayload? { nil }
}

@MainActor func testAFailedAttachBecomesAnErrorCard() async {
    do {
        let disk = try scratch()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let recorder = Recorder()
        let chat = chatWith(RefusingAttachments())
        await actions(chat, recorder, picked: [disk.file]).chooseFiles()
        expect(chat.pendingAttachments.isEmpty, "fallo: nada queda adjunto")
        expectEq(recorder.failures.map(\.name), ["nota.txt"],
                 "fallo: la isla lo enseña como tarjeta en error, con su nombre")
    } catch {
        expect(false, "fallo: preparar el disco no debe fallar (\(error))")
    }
}

@MainActor func testWithoutAPickerTheIslandSaysSo() async {
    let recorder = Recorder()
    await actions(chatWith(MemoryAttachments()), recorder, picked: nil).chooseFiles()
    expectEq(recorder.said, [Localized.string("island.attach.pickerUnavailable")],
             "sin selector: una línea bajo el campo, sin abrir la ventana")
}

@MainActor func testTheThumbnailIsLocalAndBounded() {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("thumb-\(UUID().uuidString).png")
    defer { try? fm.removeItem(at: url) }
    let big = NSImage(size: NSSize(width: 800, height: 600), flipped: false) { rect in
        NSColor.systemTeal.setFill()
        rect.fill()
        return true
    }
    guard let tiff = big.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        expect(false, "miniatura: no se pudo preparar la imagen")
        return
    }
    do { try png.write(to: url) } catch {
        expect(false, "miniatura: no se pudo escribir la imagen (\(error))")
        return
    }
    let thumb = IslandAttachThumbnail.make(path: url.path, maxPixel: 204)
    expect(thumb != nil, "miniatura: una imagen local da su miniatura")
    expect(max(thumb?.width ?? .max, thumb?.height ?? .max) <= 204,
           "miniatura: nunca más grande que lo que pinta la tarjeta")
    expectEq(IslandAttachThumbnail.make(path: url.path + ".no", maxPixel: 204) == nil, true,
             "miniatura: sin archivo no hay miniatura")
    expectEq(IslandAttachThumbnail.make(path: "https://example.com/x.png", maxPixel: 204) == nil, true,
             "miniatura: una URL de red nunca se lee")
}

// MARK: - Review round (code 4 MEDIUM, security LOW-1)

@Test @MainActor func island16m3ReviewTests() async {
    await testASecondClipClickDoesNotOpenASecondPicker()
    await testWhatThePickerCannotTakeIsSaidNotSwallowed()
    await testWhatTheDropCannotTakeIsSaidToo()
    testThumbnailsAreDecodedOncePerAttachment()
    testAHugeImageGetsNoThumbnail()
    testAPictureThatFailsShowsTheFallbackIcon()
    testOnlyTheIslandsOwnCaptureNameStacks()
    testFocusGoesBackOnlyIfNobodyTookIt()
    testAFailedNameIsSanitizedLikeAStagedOne()
    testTheStackCountsItsPeekingLayersInTheRow()
}

@MainActor private final class HeldPicker {
    var calls = 0
    var waiting: [CheckedContinuation<[URL], Never>] = []

    func pick() async -> [URL] {
        calls += 1
        return await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        waiting.forEach { $0.resume(returning: []) }
        waiting = []
    }
}

/// Review 16m-3 (MEDIUM): a second click opened a second panel, and the
/// first to close set `picking` off with the other still up.
@MainActor func testASecondClipClickDoesNotOpenASecondPicker() async {
    let held = HeldPicker()
    let view = IslandView(
        chat: chatWith(MemoryAttachments()), voice: VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter()),
        hold: HoldSettingsModel(permission: FakeAccessibility(trusted: true)), geometry: IslandGeometry(),
        onShowMain: {}, onSize: { _, _ in }, pickFiles: { await held.pick() })
    let first = view.pickAttach(.chooseFile)
    for _ in 0 ..< 5 { await Task.yield() }
    let second = view.pickAttach(.chooseFile)
    for _ in 0 ..< 5 { await Task.yield() }
    expectEq(held.calls, 1, "clip: con el selector abierto, otro clic no abre un segundo selector")
    held.release()
    await first?.value
    await second?.value
}

/// Review 16m-3 (MEDIUM): a folder, an app bundle or a link from the picker
/// was filtered out without a word; the user chose it and must see why not.
@MainActor func testWhatThePickerCannotTakeIsSaidNotSwallowed() async {
    do {
        let disk = try scratch()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let bundle = disk.root.appendingPathComponent("Calculadora.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let recorder = Recorder()
        let chat = chatWith(MemoryAttachments())
        await actions(chat, recorder, picked: [disk.folder, disk.file, bundle, disk.link]).chooseFiles()
        expectEq(chat.pendingAttachments.map(\.name), ["nota.txt"], "selector: solo el archivo entra")
        expectEq(recorder.failures.map(\.name), ["carpeta", "Calculadora.app", "enlace.txt"],
                 "selector: carpeta, paquete y enlace salen como tarjetas en error, no desaparecen")
    } catch {
        expect(false, "selector: preparar el disco no debe fallar (\(error))")
    }
}

@MainActor func testWhatTheDropCannotTakeIsSaidToo() async {
    do {
        let disk = try scratch()
        defer { try? FileManager.default.removeItem(at: disk.root) }
        let recorder = Recorder()
        let chat = chatWith(MemoryAttachments())
        actions(chat, recorder, picked: nil).drop([disk.folder, disk.file], zone: .ask)
        expectEq(chat.pendingAttachments.map(\.name), ["nota.txt"], "soltar: el archivo entra")
        expectEq(recorder.failures.map(\.name), ["carpeta"], "soltar: la carpeta sale como tarjeta en error")
    } catch {
        expect(false, "soltar: preparar el disco no debe fallar (\(error))")
    }
}

private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func hit() { lock.withLock { count += 1 } }
}

/// Review 16m-3 (MEDIUM): every time SwiftUI rebuilt a card it decoded the
/// picture again.
@MainActor func testThumbnailsAreDecodedOncePerAttachment() {
    let counter = DecodeCounter()
    let cache = IslandThumbnailCache(decode: { _, _ in
        counter.hit()
        return nil
    })
    let id = UUID()
    _ = cache.image(id: id, path: "/tmp/a.png")
    _ = cache.image(id: id, path: "/tmp/a.png")
    expectEq(counter.calls, 1, "miniatura: la segunda petición del mismo adjunto no decodifica, aunque falle")
    _ = cache.image(id: UUID(), path: "/tmp/b.png")
    expectEq(counter.calls, 2, "miniatura: otro adjunto sí decodifica")
}

/// Security review 16m-3 (LOW-1): a file that declares a gigantic canvas
/// is never handed to the decoder.
@MainActor func testAHugeImageGetsNoThumbnail() {
    let fm = FileManager.default
    let url = fm.temporaryDirectory.appendingPathComponent("huge-\(UUID().uuidString).png")
    defer { try? fm.removeItem(at: url) }
    let image = NSImage(size: NSSize(width: 800, height: 600), flipped: false) { rect in
        NSColor.systemTeal.setFill()
        rect.fill()
        return true
    }
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        expect(false, "tope: no se pudo preparar la imagen")
        return
    }
    do { try png.write(to: url) } catch {
        expect(false, "tope: no se pudo escribir la imagen (\(error))")
        return
    }
    let pixels = CGFloat(rep.pixelsWide * rep.pixelsHigh)
    expect(IslandAttachThumbnail.make(path: url.path, maxPixel: 204, maxSourcePixels: pixels) != nil,
           "tope: justo en el tope, sí hay miniatura")
    expect(IslandAttachThumbnail.make(path: url.path, maxPixel: 204, maxSourcePixels: pixels - 1) == nil,
           "tope: por encima del tope de píxeles no se decodifica")
    expectEq(IslandAttachMetrics.maxSourcePixels, 100_000_000, "tope: 100 megapíxeles")
}

@MainActor func testAPictureThatFailsShowsTheFallbackIcon() {
    expectEq(IslandPictureState.of(image: nil, loaded: false), .loading, "imagen: mientras carga, el tile")
    expectEq(IslandPictureState.of(image: nil, loaded: true), .fallback,
             "imagen: si no se pudo leer, el icono de respaldo, no un hueco")
}

/// Review 16m-3 (MEDIUM): any `captura-*.png` of the user's went into the stack.
@MainActor func testOnlyTheIslandsOwnCaptureNameStacks() {
    expect(!RegionCapture.isCapture(name: "captura-final.png"), "captura: un nombre de la usuaria es un archivo")
    expect(!RegionCapture.isCapture(name: "captura-1234567.png"), "captura: siete cifras no son las suyas")
    expect(!RegionCapture.isCapture(name: "captura-GGGGGGGG.png"), "captura: solo hexadecimal en minúscula")
    expect(RegionCapture.isCapture(name: "captura-0a1b2c3d.png"), "captura: ocho hex, como las genera")
    let model = IslandAttachTrayModel.project(
        staged: [ref("captura-final.png", .image)], failed: [], expanded: false)
    expectEq(model.cards.map(\.name), ["captura-final.png"], "captura: la de la usuaria es una tarjeta")
    expectEq(model.stack, nil, "captura: y no forma pila")
}

/// Review 16m-3 (LOW): the keyboard goes back to the app that had it only if
/// the user did not switch apps while the panel was up.
@MainActor func testFocusGoesBackOnlyIfNobodyTookIt() {
    expect(IslandPickerFocus.handsBack(previousIsCompanion: false, previousRunning: true, frontIsCompanion: true),
           "foco: nadie se movió, vuelve a la app de antes")
    expect(!IslandPickerFocus.handsBack(previousIsCompanion: false, previousRunning: true, frontIsCompanion: false),
           "foco: la usuaria cambió de app durante el panel, no se le roba")
    expect(!IslandPickerFocus.handsBack(previousIsCompanion: true, previousRunning: true, frontIsCompanion: true),
           "foco: si antes estaba Companion, nada se mueve")
    expect(!IslandPickerFocus.handsBack(previousIsCompanion: false, previousRunning: false, frontIsCompanion: true),
           "foco: una app que ya cerró no se activa")
}

/// Review 16m-3 (LOW): a failed card's name is shown like a staged one.
@MainActor func testAFailedNameIsSanitizedLikeAStagedOne() {
    let tricky = "factura\u{202E}fdp.exe:v2"
    let failure = IslandAttachFailure(name: tricky)
    expectEq(failure.name, AttachmentPolicy.sanitizedFileName(tricky), "fallo: mismo saneado que un adjunto")
    expect(!failure.name.unicodeScalars.contains { $0.value == 0x202E },
           "fallo: sin controles bidi que den la vuelta al nombre")
    let isolated = AttachmentPolicy.sanitizedFileName("a\u{2066}b\u{200F}.txt")
    let controls: Set<UInt32> = [0x2066, 0x2067, 0x2068, 0x2069, 0x200F]
    expect(!isolated.unicodeScalars.contains { controls.contains($0.value) },
           "saneado: fuera los aislantes y marcas de dirección")
}

/// Review 16m-3 (LOW): the stack's peeking layers take room the row forgot.
@MainActor func testTheStackCountsItsPeekingLayersInTheRow() {
    let model = IslandAttachTrayModel.project(
        staged: [capture(1), capture(2), capture(3), ref("a.pdf")], failed: [], expanded: false)
    expectEq(model.stack?.layers, 2, "pila: tres capturas, dos capas asomando")
    let expected: CGFloat = 96 + 6 + 8 + 84 + 12
    expectEq(model.rowWidth, expected, "fila: la pila cuenta también sus 2 × 3 de capas")
}
