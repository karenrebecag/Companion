import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// 16q-2, decision 6: the comments modal matches what Incredible's does
// without a backend: five moods, six topic chips, 5000 characters, up to
// three screenshots of at most 4 MB each from a file or the clipboard, plus
// the region grab. Delivery stays mailto / composeEmail. Names are our own.

// MARK: - Moods and topics

@Test func fiveMoodsAndSixTopicsWithTheirOwnWords() {
    expectEq(FeedbackMood.allCases.count, 5, "16q-2: cinco estados de animo")
    expectEq(FeedbackMood.allCases.map(\.rawValue), ["upset", "bad", "meh", "good", "love"],
             "16q-2: de peor a mejor; los cuatro anteriores conservan su nombre")
    expectEq(FeedbackTopic.allCases.count, 6, "16q-2: seis chips de tema")
    for language in [AppLanguage.en, .es] {
        let lines = FeedbackMood.allCases.map {
            FeedbackDraft(mood: $0, text: "x", captureCount: 0).body(language: language)
        }
        expectEq(Set(lines).count, 5, "16q-2 (\(language)): cada animo dice algo distinto en el cuerpo")
    }
}

@Test func topicsTravelInTheBodyInAFixedOrderWithoutRepeats() {
    let draft = FeedbackDraft(mood: nil, text: "hola", captureCount: 0, topics: [.dictation, .voice, .voice])
    expectEq(draft.topics, [.voice, .dictation], "16q-2: en el orden de los chips, sin repetir")
    let en = draft.body(language: .en)
    let es = draft.body(language: .es)
    expect(en.hasPrefix("Topics: ") && en.hasSuffix("\n\nhola"), "16q-2 en: la linea de temas va antes de sus palabras - \(en)")
    expect(es.hasPrefix("Temas: "), "16q-2 es: y en espanol - \(es)")
    expect(en != es, "16q-2: es/en")
    expectEq(FeedbackDraft(mood: nil, text: "hola", captureCount: 0).body(language: .en), "hola",
             "16q-2: sin temas no hay linea")
    let all = FeedbackDraft(mood: .bad, text: "t", captureCount: 1, topics: FeedbackTopic.allCases).body(language: .en)
    let order = all.components(separatedBy: "\n\n")
    expect(order.count == 4 && order[0].hasPrefix("Mood") && order[1].hasPrefix("Topics") && order[2] == "t"
        && order[3].hasPrefix("Screenshots"), "16q-2: animo, temas, texto, capturas - \(order)")
}

// MARK: - 5000 characters and the mailto cap

@Test func theLimitIsFiveThousandCharacters() {
    expectEq(FeedbackDraft.maxCharacters, 5000, "16q-2: tope de 5000 caracteres")
    let limit = String(repeating: "a", count: 5000)
    expect(FeedbackDraft(mood: nil, text: limit, captureCount: 0).canSend, "16q-2: 5000 entran")
    expect(!FeedbackDraft(mood: nil, text: limit + "a", captureCount: 0).canSend, "16q-2: 5001 no")
    expectEq(FeedbackDraft.clipped(String(repeating: "👩‍💻", count: 5200)).count, 5000, "16q-2: se recorta por caracteres")
}

@Test func fiveThousandPlainCharactersFitAMailLinkWithEverythingElse() {
    let draft = FeedbackDraft(mood: .upset, text: String(repeating: "a", count: 5000), captureCount: 3,
                              topics: FeedbackTopic.allCases)
    let link = draft.mailto(subject: "Companion feedback", language: .es)
    expectEq(link?.truncated, false, "16q-2: los 5000 sin nada que escapar caben en 6000 con animo y temas")
    expect((link?.url.absoluteString.count ?? .max) <= FeedbackDraft.maxMailtoLength, "16q-2: bajo el tope")
}

@Test func aLongOrdinaryMessageIsCutToTheMailLinkAndKeepsItsHeader() {
    let sentence = "La isla se pliega cuando escribo una arroba y aparece el dialogo de contactos. "
    let text = String((0 ..< 80).map { _ in sentence }.joined().prefix(5000))
    let draft = FeedbackDraft(mood: .bad, text: text, captureCount: 0, topics: [.apps, .screen])
    let link = draft.mailto(subject: "Companion feedback", language: .es)
    expectEq(link?.truncated, true, "16q-2: cinco mil caracteres con espacios y acentos no caben y se sabe")
    expect((link?.url.absoluteString.count ?? .max) <= FeedbackDraft.maxMailtoLength, "16q-2: la URL respeta 6000")
    let body = link.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }?
        .percentEncodedQuery?.components(separatedBy: "&body=").last?.removingPercentEncoding ?? ""
    expect(body.contains("Ánimo") && body.contains("Temas: "), "16q-2: el corte solo come texto, no el encabezado")
    expect(body.hasSuffix("…"), "16q-2: y el corte se ve")
    expect(body.count > 1500, "16q-2: se conserva lo que cabe, no se tira todo")
}

@Test @MainActor func aLongMessageGoesWholeThroughTheShareService() {
    final class Spy: @unchecked Sendable { var shared: [[Any]] = []; var opened = 0 }
    let spy = Spy()
    let text = String((0 ..< 120).map { _ in "Un comentario largo con acentos y espacios. " }.joined().prefix(5000))
    let draft = FeedbackDraft(mood: nil, text: text, captureCount: 0)
    expectEq(text.count, 5000, "16q-2: el texto de prueba mide el tope")
    let deliverer = FeedbackDeliverer(share: { _, items in spy.shared.append(items); return true },
                                      open: { _ in spy.opened += 1; return true })
    expectEq(deliverer.deliver(draft, captures: [], subject: "s", language: .es), .opened,
             "16q-2: sale por el servicio de compartir")
    expectEq(spy.opened, 0, "16q-2: sin mailto recortado")
    expectEq(spy.shared.first?.first as? String, draft.body(language: .es),
             "16q-2: el cuerpo va completo, los 5000, sin recorte")
}

// MARK: - Screenshots from a file or the clipboard

private final class FakeGrabber: RegionGrabbing, @unchecked Sendable {
    private let lock = NSLock()
    var results: [RegionGrab] = []
    private(set) var discarded: [URL] = []
    func capture() async -> RegionGrab { lock.withLock { results.isEmpty ? .cancelled : results.removeFirst() } }
    func recognizeText(at url: URL) async -> String? { nil }
    func discard(_ url: URL) { lock.withLock { discarded.append(url) } }
}

private final class FakeDelivery: FeedbackDelivering, @unchecked Sendable {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery { .opened }
}

private final class FakeAttachments: FeedbackAttaching, @unchecked Sendable {
    private let lock = NSLock()
    var chosen: [[URL]] = []
    var pasted: [PastedImage] = []
    var notRegular: Set<URL> = []
    var sizes: [URL: Int] = [:]
    var notImages: Set<URL> = []
    var delay: Duration?
    private(set) var pickerOpened = 0
    private(set) var clipboardReads = 0
    private(set) var discarded: [URL] = []
    @MainActor func chooseImages() async -> [URL] {
        let next = lock.withLock { () -> [URL] in
            pickerOpened += 1
            return chosen.isEmpty ? [] : chosen.removeFirst()
        }
        if let delay { try? await Task.sleep(for: delay) }
        return next
    }
    @MainActor func pastedImage() -> PastedImage {
        lock.withLock {
            clipboardReads += 1
            return pasted.isEmpty ? .empty : pasted.removeFirst()
        }
    }
    func isRegularFile(_ url: URL) -> Bool { lock.withLock { !notRegular.contains(url) } }
    func byteSize(of url: URL) -> Int? { lock.withLock { sizes[url] } }
    func isImage(_ url: URL) -> Bool { lock.withLock { !notImages.contains(url) } }
    func discard(_ url: URL) { lock.withLock { discarded.append(url) } }
}

private func file(_ name: String) -> URL { URL(fileURLWithPath: "/Users/k/Pictures/\(name)") }
private func pastedFile(_ n: Int) -> URL { URL(fileURLWithPath: "/tmp/companion-feedback-paste/\(n).png") }

@MainActor private func model(
    _ attachments: FakeAttachments, grabber: FakeGrabber = FakeGrabber()
) -> FeedbackModel {
    FeedbackModel(grabber: grabber, delivery: FakeDelivery(), attachments: attachments)
}

@Test @MainActor func aFileUpToFourMegabytesIsAdded() async {
    let attachments = FakeAttachments()
    let shot = file("a.png")
    attachments.sizes[shot] = FeedbackDraft.maxCaptureBytes
    attachments.chosen = [[shot]]
    let feedback = model(attachments)
    await feedback.addFiles()
    expectEq(feedback.captures, [shot], "16q-2: exactamente 4 MB entra")
    expectEq(FeedbackDraft.maxCaptureBytes, 4 * 1024 * 1024, "16q-2: 4 MB son 4*1024*1024 bytes")
}

@Test @MainActor func aBiggerNonImageOrUnreadableFileIsRefusedWithAWord() async {
    let attachments = FakeAttachments()
    let big = file("big.png"), text = file("notes.txt"), ghost = file("ghost.png")
    attachments.sizes = [big: FeedbackDraft.maxCaptureBytes + 1, text: 10]
    attachments.notImages = [text]
    attachments.chosen = [[big], [text], [ghost]]
    let feedback = model(attachments)
    await feedback.addFiles()
    expect(feedback.captures.isEmpty, "16q-2: un byte de mas ya no entra")
    let tooBig = feedback.note
    expect(tooBig != nil, "16q-2: y se dice")
    await feedback.addFiles()
    expect(feedback.captures.isEmpty && feedback.note != nil && feedback.note != tooBig, "16q-2: lo que no es imagen se dice distinto")
    await feedback.addFiles()
    expect(feedback.captures.isEmpty && feedback.note != nil, "16q-2: un archivo ilegible tampoco entra")
}

@Test @MainActor func theLimitIsThreeAcrossFilesClipboardAndRegion() async {
    let attachments = FakeAttachments()
    let grabber = FakeGrabber()
    let a = file("a.png"), b = file("b.png")
    attachments.sizes = [a: 100, b: 100, pastedFile(1): 100]
    attachments.chosen = [[a, b]]
    attachments.pasted = [.image(pastedFile(1)), .image(pastedFile(2))]
    grabber.results = [.captured(URL(fileURLWithPath: "/tmp/companion-captures/1.png"))]
    let feedback = model(attachments, grabber: grabber)
    await feedback.addFiles()
    feedback.addPasted()
    expectEq(feedback.captures.count, 3, "16q-2: dos archivos y una pegada llenan las tres")
    await feedback.addCapture()
    expectEq(feedback.captures.count, 3, "16q-2: la region no pasa del tope")
    expect(grabber.results.count == 1 || feedback.note != nil, "16q-2: y lo dice")
    let readsBefore = attachments.clipboardReads
    feedback.addPasted()
    expectEq(attachments.clipboardReads, readsBefore, "16q-2: lleno, ni se lee el portapapeles (no deja archivo temporal)")
    let opened = attachments.pickerOpened
    await feedback.addFiles()
    expectEq(attachments.pickerOpened, opened, "16q-2: lleno, ni se abre el selector")
}

@Test @MainActor func aPickerAnswerBiggerThanTheRoomTakesWhatFits() async {
    let attachments = FakeAttachments()
    let files = (1 ... 5).map { file("\($0).png") }
    for url in files { attachments.sizes[url] = 10 }
    attachments.chosen = [files]
    let feedback = model(attachments)
    await feedback.addFiles()
    expectEq(feedback.captures, Array(files.prefix(3)), "16q-2: entran las que caben, en orden")
    expect(feedback.note != nil, "16q-2: y avisa que sobraron")
}

@Test @MainActor func theSameFileTwiceIsOneScreenshot() async {
    let attachments = FakeAttachments()
    let a = file("a.png")
    attachments.sizes[a] = 10
    attachments.chosen = [[a, a], [a]]
    let feedback = model(attachments)
    await feedback.addFiles()
    await feedback.addFiles()
    expectEq(feedback.captures, [a], "16q-2: el mismo archivo no ocupa dos ranuras")
}

@Test @MainActor func aPastedImageIsAddedOrExplainedAndCleanedWhenRefused() {
    let attachments = FakeAttachments()
    attachments.sizes = [pastedFile(1): 1000, pastedFile(2): FeedbackDraft.maxCaptureBytes + 1]
    attachments.pasted = [.empty, .image(pastedFile(2)), .image(pastedFile(1))]
    let feedback = model(attachments)
    feedback.addPasted()
    expect(feedback.captures.isEmpty && feedback.note != nil, "16q-2: sin imagen en el portapapeles se dice")
    feedback.addPasted()
    expect(feedback.captures.isEmpty, "16q-2: una pegada de mas de 4 MB no entra")
    expectEq(attachments.discarded, [pastedFile(2)], "16q-2: y su archivo temporal se borra")
    feedback.addPasted()
    expectEq(feedback.captures, [pastedFile(1)], "16q-2: una valida entra")
    expectEq(feedback.note, nil, "16q-2: sin aviso")
}

@Test @MainActor func onlyWhatTheAppWroteIsEverDeleted() async {
    let attachments = FakeAttachments()
    let grabber = FakeGrabber()
    let mine = file("mine.png")
    attachments.sizes = [mine: 10, pastedFile(1): 10]
    attachments.chosen = [[mine]]
    attachments.pasted = [.image(pastedFile(1))]
    let region = URL(fileURLWithPath: "/tmp/companion-captures/r.png")
    grabber.results = [.captured(region)]
    let feedback = model(attachments, grabber: grabber)
    await feedback.addFiles()
    feedback.addPasted()
    await feedback.addCapture()
    feedback.removeCapture(mine)
    expect(attachments.discarded.isEmpty && grabber.discarded.isEmpty,
           "16q-2: quitar un archivo suyo de la lista jamas lo borra del disco")
    await feedback.addFiles()
    feedback.cancel()
    expectEq(Set(attachments.discarded), [pastedFile(1)], "16q-2: cerrar borra la pegada")
    expectEq(grabber.discarded, [region], "16q-2: y la captura de region")
    expect(!attachments.discarded.contains(mine) && !grabber.discarded.contains(mine),
           "16q-2: nunca el archivo que ella eligio")
}

@Test @MainActor func afterSendingNothingIsDeletedBecauseTheMailAppMayBeReading() async {
    let attachments = FakeAttachments()
    attachments.sizes[pastedFile(1)] = 10
    attachments.pasted = [.image(pastedFile(1))]
    let feedback = model(attachments)
    feedback.setText("hola")
    feedback.addPasted()
    feedback.send()
    feedback.cancel()
    expect(attachments.discarded.isEmpty, "16q-2: tras enviar, cerrar no borra la pegada")
}

@Test @MainActor func twoPressesOnChooseFileOpenOnePicker() async {
    let attachments = FakeAttachments()
    attachments.delay = .milliseconds(120)
    let a = file("a.png")
    attachments.sizes[a] = 10
    attachments.chosen = [[a], [a]]
    let feedback = model(attachments)
    async let first: Void = feedback.addFiles()
    async let second: Void = feedback.addFiles()
    _ = await (first, second)
    expectEq(attachments.pickerOpened, 1, "16q-2: un selector a la vez")
}

@Test @MainActor func withoutAttachmentsThePortIsAbsentAndSaysSo() async {
    let feedback = FeedbackModel(grabber: FakeGrabber(), delivery: FakeDelivery())
    await feedback.addFiles()
    expect(feedback.note != nil && feedback.captures.isEmpty, "16q-2: sin puerto de archivos se dice, no se rompe")
    feedback.addPasted()
    expect(feedback.captures.isEmpty, "16q-2: ni pegando")
}

@Test @MainActor func topicsToggleAndTravelInTheDraft() {
    let feedback = model(FakeAttachments())
    feedback.toggleTopic(.apps)
    feedback.toggleTopic(.voice)
    expectEq(feedback.draft.topics, [.voice, .apps], "16q-2: varios temas, en orden")
    feedback.toggleTopic(.apps)
    expectEq(feedback.draft.topics, [.voice], "16q-2: el segundo toque lo quita")
    expectEq(feedback.topics, [.voice], "16q-2: y el modelo lo sabe")
}

// MARK: - The live attachments never touch what is not theirs

@Test @MainActor func theLiveAttachmentsDeleteOnlyTheirOwnFolder() throws {
    let live = SystemFeedbackAttachments()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("q2-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let hers = dir.appendingPathComponent("hers.png")
    try Data(count: 10).write(to: hers)
    live.discard(hers)
    expect(FileManager.default.fileExists(atPath: hers.path), "16q-2: un archivo de ella fuera de la carpeta de pegadas no se borra")
    live.discard(dir.appendingPathComponent("../../etc/hosts"))
    expect(FileManager.default.fileExists(atPath: "/etc/hosts"), "16q-2: una ruta con .. tampoco escapa")
    expectEq(live.byteSize(of: hers), 10, "16q-2: el tamano sale del archivo")
    expect(live.byteSize(of: dir.appendingPathComponent("nope.png")) == nil, "16q-2: sin archivo, sin tamano")
    for name in ["a.PNG", "b.jpeg"] {
        let image = dir.appendingPathComponent(name)
        try Data(count: 4).write(to: image)
        expect(live.isImage(image), "16q-2: \(name) es imagen, con la extension en mayusculas o no")
    }
    let text = dir.appendingPathComponent("a.txt")
    let bare = dir.appendingPathComponent("a")
    try Data(count: 4).write(to: text)
    try Data(count: 4).write(to: bare)
    expect(!live.isImage(text) && !live.isImage(bare), "16q-2: un texto o algo sin extension no lo es")
    expect(!live.isImage(dir.appendingPathComponent("ghost.png")), "16q-2: un archivo que no existe no es imagen")
}
