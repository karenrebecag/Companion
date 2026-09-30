import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Split out of HoldVoiceTests.swift to keep it under 800 lines.

@Test @MainActor func holdDictationTests() async {
    await testAHoldDictatesIntoTheField()
    await testAHoldWithoutAFieldTalksToCompanion()
    await testDictationWithoutAccessibilityFallsToCompanion()
    await testAVanishedFieldFallsToCompanion()
    await testAnEmptyDictationPastesNothing()
    await testDictationNeverReachesTheLog()
    await testABouncedPressKeepsTheTarget()
    await testTheProbeNeverDelaysTheMic()
}

// Wave 12e. La misma tecla, otro destino: con un campo de texto enfocado en
// otra app, soltar pega ahí y nada viaja a la conversación.

final class ScriptedFieldProbe: FocusedFieldProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _probes = 0
    var field: FocusedField?
    var trusted = true
    /// What the caller wants recorded at probe time (12e: that the mic is
    /// already opening when Accessibility is asked).
    var onProbe: (@Sendable () -> Void)?
    var probes: Int { lock.withLock { _probes } }
    init(_ field: FocusedField? = nil) { self.field = field }
    func isTrusted() -> Bool { trusted }
    func focusedField() -> FocusedField? {
        lock.withLock { _probes += 1 }
        onProbe?()
        return field
    }
}

final class ScriptedInjector: TextInjecting, @unchecked Sendable {
    private let lock = NSLock()
    private var _texts: [String] = []
    private var _fields: [FocusedField] = []
    var failure: InjectionFailure?
    var texts: [String] { lock.withLock { _texts } }
    var fields: [FocusedField] { lock.withLock { _fields } }

    func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        lock.withLock {
            _texts.append(text)
            _fields.append(field)
        }
        if let failure { return .failed(failure) }
        return .injected(text.count, via: .ax)
    }
}

private let slack = FocusedField(app: "Slack", pid: 42)

/// 14. Con un campo enfocado en otra app, soltar pega el texto ahí: el
/// inyector lo recibe, la conversación no, y el flujo dice dónde.
@MainActor func testAHoldDictatesIntoTheField() async {
    let probe = ScriptedFieldProbe(slack)
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(fieldProbe: probe, injector: injector)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "hola qué tal"
    // 15b-1: dictation is the dictation key's own hold now, never FN's.
    await h.session.hold(dictate: true)
    await pumpUntil("dictado: listening") { h.watch.latest.state == .listening }
    expectEq(probe.probes, 1, "dictado: la sonda corre al pulsar")
    await pumpUntil("dictado: anuncia la app") { seen.events.contains { $0 == .dictating(app: "Slack") } }
    let before = h.transport.sent.count
    await h.session.release()
    await pumpUntil("dictado: pega") { injector.texts == ["hola qué tal"] }
    expectEq(injector.fields.first?.pid, 42, "dictado: en el campo sondeado")
    await pumpUntil("dictado: lo dice") {
        seen.events.contains { $0 == .dictated(app: "Slack", text: "hola qué tal") }
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(!hasMessage(added, type: "conversation.item.create"), "dictado: nada viaja a la conversación")
    expect(!hasMessage(added, type: "response.create"), "dictado: y no se pide respuesta")
    expect(!added.contains { $0.contains("hola qué tal") }, "dictado: el texto no sale por el socket")
    expect(h.chat.histories.isEmpty, "dictado: no viaja al chat")
    expect(!seen.events.contains { $0 == .heardNothing }, "dictado: no es «no te oí»")
}

/// 15. Sin campo (o con una contraseña), el hold habla con Companion como
/// siempre y el inyector no ve nada. Con `dictate: true` para que el
/// enrutador de campo siga siendo el que decide (15b-1: FN ya ni pregunta).
@MainActor func testAHoldWithoutAFieldTalksToCompanion() async {
    for field in [nil, FocusedField(app: "Safari", pid: 7, secure: true)] {
        let probe = ScriptedFieldProbe(field)
        let injector = ScriptedInjector()
        let h = makeVoiceHarness(fieldProbe: probe, injector: injector)
        let seen = SessionEventBox(h.session.events)
        h.transcriber.stoppedText = "abre Safari"
        h.chat.rounds = [[.text("Listo.")]]
        await h.session.hold(dictate: true)
        await pumpUntil("agente: listening") { h.watch.latest.state == .listening }
        await h.session.release()
        await pumpUntil("agente: el texto viaja") { !h.chat.histories.isEmpty }
        expect(injector.texts.isEmpty, "agente: el inyector no ve nada (\(field?.app ?? "sin campo"))")
        expect(!seen.events.contains { if case .dictating = $0 { true } else { false } },
               "agente: la island no dice «dictando»")
    }
}

/// 16. En modo Dictar sin Accesibilidad no se pega: el texto llega a
/// Companion y el flujo avisa del permiso.
@MainActor func testDictationWithoutAccessibilityFallsToCompanion() async {
    let probe = ScriptedFieldProbe(slack)
    probe.trusted = false
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(fieldProbe: probe, injector: injector)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold(dictate: true)
    await pumpUntil("permiso: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("permiso: el texto va a Companion") { !h.chat.histories.isEmpty }
    await pumpUntil("permiso: avisa") { seen.events.contains { $0 == .dictationFailed(.needsAccessibility) } }
    expect(injector.texts.isEmpty, "permiso: sin confianza no se pega")
    expect(!seen.events.contains { if case .dictating = $0 { true } else { false } },
           "permiso: no prometió dictar")
}

/// 17. El campo desapareció al soltar (otra app delante): no se pega en
/// otro sitio; las palabras van a Companion.
@MainActor func testAVanishedFieldFallsToCompanion() async {
    let probe = ScriptedFieldProbe(slack)
    let injector = ScriptedInjector()
    injector.failure = .fieldGone
    let h = makeVoiceHarness(fieldProbe: probe, injector: injector)
    h.transcriber.clearOnStop = true
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold(dictate: true)
    await pumpUntil("se fue: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("se fue: el texto va a Companion") { !h.chat.histories.isEmpty }
    expectEq(injector.texts, ["hola"], "se fue: se intentó una vez")
    expect(!seen.events.contains { if case .dictated = $0 { true } else { false } },
           "se fue: no dice «pegado»")
}

/// 18. Dictado vacío: «no te oí», y el inyector no recibe una cadena vacía.
@MainActor func testAnEmptyDictationPastesNothing() async {
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(fieldProbe: ScriptedFieldProbe(slack), injector: injector)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = ""
    await h.session.hold(dictate: true)
    await pumpUntil("vacío: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("vacío: lo dice") { seen.events.contains { $0 == .heardNothing } }
    expect(injector.texts.isEmpty, "vacío: nada que pegar")
    expect(h.chat.histories.isEmpty, "vacío: nada que enviar")
}

/// 19. Lo dictado no aparece en el log ni en el flujo (salvo como parcial
/// mientras se mantiene): el log solo cuenta cuántos caracteres y dónde.
@MainActor func testDictationNeverReachesTheLog() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-dictation-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        let injector = ScriptedInjector()
        let h = makeVoiceHarness(fieldProbe: ScriptedFieldProbe(slack), injector: injector)
        let seen = SessionEventBox(h.session.events)
        h.transcriber.stoppedText = "palabra secreta"
        await h.session.hold(dictate: true)
        await pumpUntil("log: listening") { h.watch.latest.state == .listening }
        await h.session.release()
        await pumpUntil("log: pegó") {
            seen.events.contains { $0 == .dictated(app: "Slack", text: "palabra secreta") }
        }
        await h.session.hangUp()
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(text.contains("dictation: pasted 15 chars into Slack via ax"), "log: cuenta y dónde")
        expect(!text.contains("palabra secreta"), "log: nunca el texto")
        // 16m-4: the result card reads the pasted words, so `.dictated`
        // carries them, in memory. Only its payload is exempt, and only
        // because it is `DictatedText`, which prints redacted: any event's
        // description is still checked, `.dictated` included.
        let leaked = seen.events.contains {
            if case .partialTranscript = $0 { return false }
            return "\($0)".contains("palabra secreta")
        }
        expect(!leaked, "flujo: el texto solo viaja como parcial y como payload del resultado, sin imprimirse")
        let carried = seen.events.contains {
            if case .dictated(_, let words) = $0 { return words?.value == "palabra secreta" }
            return false
        }
        expect(carried, "flujo: el resultado sí lo lleva a la tarjeta")
    }
}

/// 20. Una pulsación que rebota mientras conecta es el mismo hold: no
/// vuelve a preguntar por el campo (una llamada de Accesibilidad a una app
/// ocupada cuesta) ni repite el anuncio.
@MainActor func testABouncedPressKeepsTheTarget() async {
    let probe = ScriptedFieldProbe(slack)
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(
        autoEvents: [], readyTimeout: 0.4, fieldProbe: probe, injector: injector)
    let seen = SessionEventBox(h.session.events)
    await h.session.hold(dictate: true)
    await pumpUntil("rebote: listening") { h.watch.latest.state == .listening }
    await h.session.hold(dictate: true)
    expectEq(probe.probes, 1, "rebote: una sola sonda")
    expectEq(seen.events.filter { $0 == .dictating(app: "Slack") }.count, 1,
             "rebote: un solo anuncio")
}

/// 21. Preguntar por el campo es una llamada a la app de delante, que puede
/// estar colgada: nunca por delante del micro. Con la sonda detenida, la
/// sesión llega a escuchar igual (revisión de código 2026-09-06).
@MainActor func testTheProbeNeverDelaysTheMic() async {
    let probe = ScriptedFieldProbe(slack)
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(fieldProbe: probe, injector: injector)
    // La espera tiene tope: si la sonda volviera al camino de la pulsación
    // esto debe fallar, no colgar la suite.
    let gate = DispatchSemaphore(value: 0)
    probe.onProbe = { _ = gate.wait(timeout: .now() + 5) }
    h.transcriber.stoppedText = "hola"
    await h.session.hold(dictate: true)
    await pumpUntil("sonda: el micro abre con la sonda detenida") {
        h.watch.latest.state == .listening
    }
    expectEq(probe.probes, 1, "sonda: ya estaba preguntando")
    gate.signal()
    await h.session.release()
    await pumpUntil("sonda: pega igual") { injector.texts == ["hola"] }
}
