import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-7: the feedback modal. Destination unchanged (the user's own mail
// app through mailto: no server of ours); the modal only composes what goes
// in the message. Captures are taken only when she asks.

@Test func feedbackDraftTests() {
    let none = FeedbackDraft(mood: nil, text: "  ", captureCount: 0)
    expect(!none.canSend, "16m-7: sin texto no se envía")
    expect(FeedbackDraft(mood: .good, text: "Me gusta", captureCount: 0).canSend, "16m-7: con texto sí")
    expect(!FeedbackDraft(mood: .good, text: "", captureCount: 2).canSend, "16m-7: capturas sin texto no bastan")
    let limit = String(repeating: "a", count: FeedbackDraft.maxCharacters)
    expect(FeedbackDraft(mood: nil, text: limit, captureCount: 0).canSend, "16m-7: el tope exacto entra")
    expect(!FeedbackDraft(mood: nil, text: limit + "a", captureCount: 0).canSend, "16m-7: uno más ya no")
    expectEq(FeedbackDraft(mood: nil, text: "abc", captureCount: 0).remaining, FeedbackDraft.maxCharacters - 3, "16m-7: el contador cuenta lo que queda")
    expectEq(FeedbackDraft(mood: nil, text: limit + "aa", captureCount: 0).remaining, -2, "16m-7: y avisa cuando se pasa")
    expectEq(FeedbackDraft.clipped(String(repeating: "👩‍💻", count: FeedbackDraft.maxCharacters + 200)).count, FeedbackDraft.maxCharacters, "16m-7: recortar cuenta caracteres, no bytes ni escalares")
    expectEq(FeedbackDraft.clipped("hola"), "hola", "16m-7: lo corto queda igual")
}

@Test func feedbackBodyAndMailtoTests() {
    let draft = FeedbackDraft(mood: .bad, text: "No sirve & # % + ?=\nsegunda línea 🙂 ñ'; DROP", captureCount: 2)
    let body = draft.body(language: .en)
    expect(body.contains("No sirve & # % + ?=\nsegunda línea"), "16m-7: el texto viaja tal cual")
    expect(body.contains("2"), "16m-7: dice cuántas capturas van")
    expect(body.lowercased().contains("mood"), "16m-7: dice el ánimo")
    expect(draft.body(language: .es) != body, "16m-7: es/en")
    let plain = FeedbackDraft(mood: nil, text: "hola", captureCount: 0).body(language: .en)
    expectEq(plain, "hola", "16m-7: sin ánimo ni capturas el cuerpo es solo sus palabras")
    expect(!body.contains("/Users") && !body.contains("Companion 1"), "16m-7: ni rutas ni datos de la máquina")
    let hostile = FeedbackDraft(mood: nil, text: "a\u{202E}b\u{0007}c", captureCount: 0).body(language: .en)
    expectEq(hostile, "abc", "16m-7: sin controles de dirección ni de terminal")

    let url = draft.mailtoURL(subject: "Companion feedback & más", language: .en)
    expectEq(url?.scheme, "mailto", "16m-7: el mismo camino: mailto")
    let comps = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    expectEq(comps?.path, "", "16m-7: sin destinatario que inventar")
    expectEq(comps?.queryItems?.first { $0.name == "subject" }?.value, "Companion feedback & más", "16m-7: el asunto sobrevive")
    expectEq(comps?.queryItems?.first { $0.name == "body" }?.value, body, "16m-7: el cuerpo sobrevive a la codificación")
    expectEq(FeedbackDraft(mood: nil, text: "x", captureCount: 0).mailtoURL(subject: "s", language: .en)?.absoluteString.contains(" "), false,
             "16m-7: la URL no lleva espacios crudos")
}

private final class FakeGrabber: RegionGrabbing, @unchecked Sendable {
    private let lock = NSLock()
    var results: [RegionGrab] = []
    var delay: Duration?
    private(set) var captures = 0
    private(set) var discarded: [URL] = []
    func capture() async -> RegionGrab {
        let result = lock.withLock { () -> RegionGrab in
            captures += 1
            return results.isEmpty ? .cancelled : results.removeFirst()
        }
        if let delay { try? await Task.sleep(for: delay) }
        return result
    }
    func recognizeText(at url: URL) async -> String? { nil }
    func discard(_ url: URL) { lock.withLock { discarded.append(url) } }
}

private final class FakeDelivery: FeedbackDelivering, @unchecked Sendable {
    var outcome = FeedbackDelivery.opened
    private(set) var sent: [(FeedbackDraft, [URL])] = []
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery {
        sent.append((draft, captures))
        return outcome
    }
}

private func shot(_ n: Int) -> URL { URL(fileURLWithPath: "/tmp/companion-captures/\(n).png") }

@Test @MainActor func feedbackModelTests() async {
    let grabber = FakeGrabber()
    let delivery = FakeDelivery()
    let model = FeedbackModel(grabber: grabber, delivery: delivery)
    expectEq(grabber.captures, 0, "16m-7: abrir el modal no toma ninguna captura")
    expect(!model.canSend, "16m-7: vacío no se envía")

    model.setText(String(repeating: "x", count: FeedbackDraft.maxCharacters + 200))
    expectEq(model.text.count, FeedbackDraft.maxCharacters, "16m-7: el campo no pasa del tope")
    model.setText("Todo bien")
    model.mood = .love

    grabber.results = (1 ... FeedbackDraft.maxCaptures + 1).map { .captured(shot($0)) }
    for _ in 0 ..< FeedbackDraft.maxCaptures { await model.addCapture() }
    expectEq(model.captures, (1 ... FeedbackDraft.maxCaptures).map(shot), "16m-7: cada captura es una acción suya")
    await model.addCapture()
    expectEq(grabber.captures, FeedbackDraft.maxCaptures, "16m-7: en el tope ni se abre el selector de captura")
    expect(model.note != nil, "16m-7: y lo dice")
    model.removeCapture(shot(2))
    expectEq(model.captures, [shot(1), shot(3)], "16m-7: quitar una")
    expectEq(grabber.discarded, [shot(2)], "16m-7: y se borra el archivo")

    model.send()
    expectEq(delivery.sent.count, 1, "16m-7: se entrega una vez")
    expectEq(delivery.sent.first?.0, FeedbackDraft(mood: .love, text: "Todo bien", captureCount: 2), "16m-7: con ánimo, texto y conteo")
    expectEq(delivery.sent.first?.1, [shot(1), shot(3)], "16m-7: y las capturas")
    expectEq(model.phase, .sent, "16m-7: enviado")

    let failing = FeedbackModel(grabber: grabber, delivery: delivery)
    delivery.outcome = .failed
    failing.setText("hola")
    failing.send()
    expectEq(failing.phase, .composing, "16m-7: si no abrió el correo, sigue componiendo")
    expect(failing.note != nil, "16m-7: y lo dice, sin perder lo escrito")
    expectEq(failing.text, "hola", "16m-7: el texto sigue ahí")

    delivery.outcome = .openedWithoutCaptures
    grabber.results = [.captured(shot(9))]
    await failing.addCapture()
    failing.send()
    expectEq(failing.phase, .sent, "16m-7: abrió el correo")
    expect(failing.note != nil, "16m-7: y avisa que las capturas no pudieron ir adjuntas")
}

@Test @MainActor func feedbackCaptureOutcomesTests() async {
    let grabber = FakeGrabber()
    let model = FeedbackModel(grabber: grabber, delivery: FakeDelivery())
    grabber.results = [.cancelled, .failed, .needsPermission]
    await model.addCapture()
    expect(model.note == nil && model.captures.isEmpty, "16m-7: cancelar la captura no es un error")
    await model.addCapture()
    let failed = model.note
    expect(failed != nil, "16m-7: fallar se dice")
    await model.addCapture()
    expect(model.note != nil && model.note != failed, "16m-7: sin permiso de pantalla se dice distinto")
    expect(model.captures.isEmpty, "16m-7: ninguna quedó")
}

@Test @MainActor func feedbackCancelDiscardsTests() async {
    let grabber = FakeGrabber()
    let model = FeedbackModel(grabber: grabber, delivery: FakeDelivery())
    grabber.results = [.captured(shot(1)), .captured(shot(2))]
    await model.addCapture()
    await model.addCapture()
    model.cancel()
    expectEq(Set(grabber.discarded), [shot(1), shot(2)], "16m-7: cerrar sin enviar borra las capturas")
    expectEq(model.captures, [], "16m-7: y las suelta")
    expectEq(model.phase, .closed, "16m-7: cerrado")
}

@Test @MainActor func feedbackMetricsTests() {
    expectEq(FeedbackMetrics.width, 480, "16m-7 comentarios: modal 480")
    expectEq(FeedbackMetrics.padding, 32, "16m-7 comentarios: padding 32")
    expectEq(FeedbackMetrics.radius, 28, "16m-7 comentarios: radio 28")
    expectEq(FeedbackMood.allCases.count, 4, "16m-7: cuatro estados de ánimo")
    expectEq(Set(FeedbackMood.allCases.map(\.symbol)).count, 4, "16m-7: cada uno con su símbolo, sin emoji")
}


// MARK: - Review round

@Test @MainActor func feedbackCaptureReentrancyTests() async {
    let grabber = FakeGrabber()
    grabber.delay = .milliseconds(120)
    grabber.results = (1 ... 6).map { .captured(shot($0)) }
    let model = FeedbackModel(grabber: grabber, delivery: FakeDelivery())
    async let a: Void = model.addCapture()
    async let b: Void = model.addCapture()
    async let c: Void = model.addCapture()
    _ = await (a, b, c)
    expectEq(grabber.captures, 1, "16m-7 review: dos pulsaciones seguidas no abren dos capturas a la vez")
    expectEq(model.captures.count, 1, "16m-7 review: y queda una")
    for _ in 0 ..< 5 { await model.addCapture() }
    expect(model.captures.count <= FeedbackDraft.maxCaptures, "16m-7 review: nunca pasa del máximo")
}

@Test @MainActor func feedbackCancelDuringCaptureTests() async {
    let grabber = FakeGrabber()
    grabber.delay = .milliseconds(150)
    grabber.results = [.captured(shot(1))]
    let model = FeedbackModel(grabber: grabber, delivery: FakeDelivery())
    let pending = Task { await model.addCapture() }
    try? await Task.sleep(for: .milliseconds(30))
    model.cancel()
    await pending.value
    expectEq(model.captures, [], "16m-7 review: una captura que llega con el modal cerrado no se queda")
    expectEq(grabber.discarded, [shot(1)], "16m-7 review: y su archivo se borra, no queda huérfano")
}

@Test @MainActor func feedbackCancelAfterSendKeepsCapturesTests() async {
    let grabber = FakeGrabber()
    grabber.results = [.captured(shot(1))]
    let model = FeedbackModel(grabber: grabber, delivery: FakeDelivery())
    model.setText("hola")
    await model.addCapture()
    model.send()
    expectEq(model.phase, .sent, "setup")
    model.cancel()
    expectEq(grabber.discarded, [], "16m-7 review: tras enviar, cerrar no borra lo que la app de correo puede estar leyendo")
    expectEq(model.phase, .closed, "16m-7 review: y el modal se cierra")
}

@Test func feedbackMailtoFitsTests() {
    let long = FeedbackDraft(mood: .bad, text: String(repeating: "👩‍💻", count: FeedbackDraft.maxCharacters), captureCount: 0)
    let cut = long.mailto(subject: "s", language: .en)
    expectEq(cut?.truncated, true, "16m-7 review: mil emoji no caben en un mailto y se sabe")
    expect((cut?.url.absoluteString.count ?? .max) <= FeedbackDraft.maxMailtoLength, "16m-7 review: la URL respeta el tope")
    let body = cut.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }?
        .percentEncodedQuery?.components(separatedBy: "&body=").last?.removingPercentEncoding ?? ""
    expect(body.contains("👩‍💻") && !body.contains("\u{FFFD}"), "16m-7 review: el corte no parte un emoji")
    expect(long.mailtoURL(subject: "s", language: .en) != nil, "16m-7 review: mailtoURL sigue existiendo")
    let short = FeedbackDraft(mood: nil, text: "línea uno\r\nlínea dos\rtres\n\ncuatro", captureCount: 0)
    let plain = short.mailto(subject: "s", language: .en)
    expectEq(plain?.truncated, false, "16m-7 review: lo corto no se corta")
    let decoded = plain.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) }?
        .percentEncodedQuery?.components(separatedBy: "&body=").last?.removingPercentEncoding
    expectEq(decoded, short.body(language: .en), "16m-7 review: \\r\\n y \\r sobreviven la codificación")
}

@Test @MainActor func feedbackDelivererBranchesTests() {
    final class Spy: @unchecked Sendable { var shared: [[Any]] = []; var opened: [URL] = [] }
    let spy = Spy()
    let draft = FeedbackDraft(mood: nil, text: "hola", captureCount: 1)
    let files = [URL(fileURLWithPath: "/tmp/a.png")]
    func deliverer(share: Bool, open: Bool) -> FeedbackDeliverer {
        FeedbackDeliverer(share: { _, items in spy.shared.append(items); return share }, open: { spy.opened.append($0); return open })
    }
    expectEq(deliverer(share: true, open: true).deliver(draft, captures: files, subject: "s", language: .en), .opened,
             "16m-7 review: con capturas y servicio, sale por el servicio")
    expectEq(spy.shared.count, 1, "16m-7 review: una vez")
    expectEq(spy.opened.count, 0, "16m-7 review: sin mailto")
    expectEq(deliverer(share: false, open: true).deliver(draft, captures: files, subject: "s", language: .en), .openedWithoutCaptures,
             "16m-7 review: sin servicio, el texto va por mailto y se avisa de las capturas")
    expectEq(deliverer(share: false, open: false).deliver(draft, captures: files, subject: "s", language: .en), .failed,
             "16m-7 review: si nada abre, falla")
    let plain = FeedbackDraft(mood: nil, text: "hola", captureCount: 0)
    let before = spy.shared.count
    expectEq(deliverer(share: true, open: true).deliver(plain, captures: [], subject: "s", language: .en), .opened,
             "16m-7 review: sin capturas, mailto normal")
    expectEq(spy.shared.count, before, "16m-7 review: sin capturas ni exceso no se usa el servicio")
    let long = FeedbackDraft(mood: nil, text: String(repeating: "👩‍💻", count: FeedbackDraft.maxCharacters), captureCount: 0)
    expectEq(deliverer(share: true, open: true).deliver(long, captures: [], subject: "s", language: .en), .opened,
             "16m-7 review: un texto que no cabe en mailto sale completo por el servicio")
    expectEq(spy.shared.count, before + 1, "16m-7 review: usó el servicio")
    expectEq(deliverer(share: false, open: true).deliver(long, captures: [], subject: "s", language: .en), .openedTruncated,
             "16m-7 review: sin servicio se corta y se dice")
}

@Test @MainActor func feedbackRequestSurvivesAMissingWindowTests() {
    FeedbackRequest.clear()
    expect(!FeedbackRequest.consume(), "16m-7 review: sin petición no hay nada")
    FeedbackRequest.raise()
    FeedbackRequest.raise()
    expect(FeedbackRequest.consume(), "16m-7 review: una petición hecha antes de que la ventana existiera se lee al aparecer")
    expect(!FeedbackRequest.consume(), "16m-7 review: y se consume una vez")
}
