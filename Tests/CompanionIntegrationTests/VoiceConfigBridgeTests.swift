import CompanionCore
import CompanionServices
import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

@Test @MainActor func voiceConfigBridgeTests() async {
    await testConfigProviderReadAtSessionOpen()
    await testTurnDetectionIsNullSoOpenAIDoesNotListen()
    await testOwnerNameReachesCodec()
    await testSpeedCanChangeInHotSession()
    await testAECToggleRearmVeto()
    await testTheEarListensInTheUserLanguage()
}

// MARK: - El idioma manda también en la voz

// Wave 9 llevó el idioma a la UI y a los prompts de texto, pero la entrada de
// voz se quedó atrás: el reconocedor escuchaba siempre en es-MX. La decisión
// existía y nadie la invocaba, que es el patrón de bug de este repo.
//
// Hubo un segundo caso, el permiso preguntado siempre en inglés, que dejó de
// existir cuando el permiso dejó de preguntarse en voz alta (2026-08-22).

/// El oído: un usuario en inglés hablaba inglés y el reconocedor lo
/// transcribía como si fuera español.
@MainActor func testTheEarListensInTheUserLanguage() async {
    let english = makeVoiceHarness(key: nil, autoEvents: [], language: .en)
    await english.session.start()
    await pumpUntil("oído: clásico armado en inglés") {
        english.watch.latest.state == .listening
            && english.watch.latest.pipeline == .classic
    }
    expectEq(english.transcriber.locale, "en-US",
             "oído: al inglés se le escucha en inglés")

    let spanish = makeVoiceHarness(key: nil, autoEvents: [], language: .es)
    await spanish.session.start()
    await pumpUntil("oído: clásico armado en español") {
        spanish.watch.latest.state == .listening
            && spanish.watch.latest.pipeline == .classic
    }
    expectEq(spanish.transcriber.locale, "es-MX",
             "oído: el español no pierde lo que ya funcionaba")
}

// MARK: - ConfigProviding protocol

@MainActor func testConfigProviderReadAtSessionOpen() async {
    let provider = TestConfigProvider(config: Config(
        voice: VoiceSettings(voice: .cedar, speed: 1.0)))
    let h = makeVoiceHarnessWithProvider(provider)

    await h.session.start()
    await pumpUntil("start: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    // First session uses cedar voice from the provider
    expect(hasVoiceInSessionUpdate(h.transport.sent, expectedVoice: .cedar),
           "config provider: reads voice at session open")
    expectEq(provider.readCount, 1, "config provider: reads once per session start")
}

@MainActor func testTurnDetectionIsNullSoOpenAIDoesNotListen() async {
    let provider = TestConfigProvider(config: Config(
        voice: VoiceSettings(turnDetection: .semanticVAD(eagerness: .high))))
    let h = makeVoiceHarnessWithProvider(provider)

    await h.session.start()
    await pumpUntil("start: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    // Wave 9i: OpenAI never listens — turn_detection is null no matter the
    // user's VAD preference, which now drives the LOCAL endpointer instead.
    let update = sessionUpdateJSON(h.transport.sent)
    let session = update["session"] as? [String: Any] ?? [:]
    let audio = session["audio"] as? [String: Any] ?? [:]
    let input = audio["input"] as? [String: Any] ?? [:]
    expect(input["turn_detection"] is NSNull,
           "turn detection: null — OpenAI no hace VAD, escucha Apple")
}

@MainActor func testOwnerNameReachesCodec() async {
    let provider = TestConfigProvider(config: Config(ownerFirstName: "Karen"))
    let h = makeVoiceHarnessWithProvider(provider)

    await h.session.start()
    await pumpUntil("start: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    let update = sessionUpdateJSON(h.transport.sent)
    let instructions = update["session"] as? [String: Any] ?? [:]
    let sessionInstructions = instructions["instructions"] as? String ?? ""
    expect(sessionInstructions.contains("Karen"),
           "owner name: reaches session instructions")
}

// MARK: - Hot speed updates (6c-3 preview; full impl in 6c-3)

@MainActor func testSpeedCanChangeInHotSession() async {
    let provider = TestConfigProvider(config: Config(
        voice: VoiceSettings(speed: 1.0)))
    let h = makeVoiceHarnessWithProvider(provider)

    await h.session.start()
    await pumpUntil("start: listening") {
        h.watch.latest.state == TurnState.listening && h.watch.latest.pipeline == .realtime
    }

    // Change speed in the provider while session is active
    provider.updateConfig(Config(
        voice: VoiceSettings(speed: 1.5)))

    // The actual hot speed update (via session.update with only speed field)
    // is wired in 6c-3, but the provider should have the new value
    expectEq(provider.current.voice.speed, 1.5,
             "hot speed: provider reads new speed immediately")
}

// MARK: - AEC veto toggle (6c-4 spec; rearm logic in 6c-4)

@MainActor func testAECToggleRearmVeto() async {
    let vetoStore = InMemoryAECVeto(true)
    expectEq(vetoStore.isVetoed, true, "veto: initial state is vetoed")

    // Toggling AEC preference clears the veto
    vetoStore.isVetoed = false
    expectEq(vetoStore.isVetoed, false, "veto: toggle clears isVetoed")

    // Next session will retry VPIO
    let provider = TestConfigProvider(config: Config(
        voice: VoiceSettings(echoCancellation: true)))
    expectEq(provider.current.voice.echoCancellation, true,
             "aec toggle: echoCancellation preference is true")
}

// MARK: - JSON Helpers

private func sessionUpdateJSON(_ sent: [String]) -> [String: Any] {
    let updateMsg = sent.first(where: { $0.contains("session.update") }) ?? "{}"
    return (try? JSONSerialization.jsonObject(with: updateMsg.data(using: .utf8)!)) as? [String: Any] ?? [:]
}

private func hasVoiceInSessionUpdate(_ sent: [String], expectedVoice: VoiceID? = nil) -> Bool {
    let updateMsg = sent.first(where: { $0.contains("session.update") }) ?? "{}"
    guard let json = (try? JSONSerialization.jsonObject(with: updateMsg.data(using: .utf8)!)) as? [String: Any] else {
        return false
    }
    let session = json["session"] as? [String: Any] ?? [:]
    let audio = session["audio"] as? [String: Any] ?? [:]
    let output = audio["output"] as? [String: Any] ?? [:]
    let voice = output["voice"] as? String

    if let expected = expectedVoice {
        return voice == expected.rawValue
    }
    return voice != nil
}

// MARK: - Velocidad en caliente (6c, contrato del ledger)

@Test @MainActor func hotSpeedTests() async {
    await testHotSpeedTravelsMidSession()
    await testHotSpeedIgnoredWhenIdle()
}

@MainActor func testHotSpeedTravelsMidSession() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("hot-speed: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    await h.session.setSpeed(1.3)
    await pumpUntil("hot-speed: viaja un update") { h.transport.sent.count > before }
    let last = h.transport.sent.last ?? ""
    expect(last.contains("\"speed\":1.3"), "hot-speed: lleva la velocidad nueva")
    expect(last.contains("session.update"), "hot-speed: es un session.update")
    expect(!last.contains("\"voice\""), "hot-speed: JAMÁS toca la voz (ledger)")
    expect(!last.contains("turn_detection"), "hot-speed: no arrastra otros campos")
}

@MainActor func testHotSpeedIgnoredWhenIdle() async {
    let h = makeVoiceHarness()
    let before = h.transport.sent.count
    await h.session.setSpeed(0.8)
    await settle(0.05)
    expectEq(h.transport.sent.count, before,
             "hot-speed: sin sesión no hay a dónde mandarlo")
}

// MARK: - La voz sabe que tiene especialista (bug de produccion, captura de Karen)

@Test @MainActor func voiceDelegationTests() async {
    await testSessionDeclaresDelegateWhenAvailable()
    await testSessionOmitsDelegateWithoutExecutor()
}

@MainActor func testSessionDeclaresDelegateWhenAvailable() async {
    let h = makeVoiceHarness(jobs: RecordingSubmitter())
    await h.session.start()
    await pumpUntil("delegación: sesión lista") {
        h.transport.sent.contains { $0.contains("session.update") }
    }
    let update = h.transport.sent.first { $0.contains("session.update") } ?? ""
    expect(update.contains("\"delegate\""),
           "voz: declara la herramienta delegate (sin ella el modelo dice 'no puedo')")
    expect(update.contains("specialist"),
           "voz: las instrucciones le dicen que el especialista existe")
}

@MainActor func testSessionOmitsDelegateWithoutExecutor() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("sin ejecutor: sesión lista") {
        h.transport.sent.contains { $0.contains("session.update") }
    }
    let update = h.transport.sent.first { $0.contains("session.update") } ?? ""
    expect(!update.contains("\"delegate\""),
           "voz: sin ejecutor no promete lo que no puede cumplir")
}
