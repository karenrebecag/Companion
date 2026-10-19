import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Split out of HoldVoiceTests.swift to keep it under 800 lines.

@Test @MainActor func holdDictationTests() async {
    await testAHoldWithoutAFieldTalksToCompanion()
    await testDictationWithoutAccessibilityFallsToCompanion()
    await testAVanishedFieldFallsToCompanion()
    await testAnEmptyDictationPastesNothing()
    await testDictationNeverReachesTheLog()
    await testTheProbeNeverDelaysTheMic()
}

// Wave 12e. La misma tecla, otro destino: con un campo de texto enfocado en
// otra app, soltar pega ahí y nada viaja a la conversación.

private let slack = FocusedField(app: "Slack", pid: 42)

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
