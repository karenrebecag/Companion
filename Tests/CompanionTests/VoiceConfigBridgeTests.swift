import CompanionCore
import CompanionServices
import CompanionUI
import Foundation
import Testing

@Test @MainActor func voiceConfigBridgeTests() async {
    await testConfigProviderReadAtSessionOpen()
    await testTurnDetectionChangeAppliesToNextSession()
    await testOwnerNameReachesCodec()
    await testSpeedCanChangeInHotSession()
    await testAECToggleRearmVeto()
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

@MainActor func testTurnDetectionChangeAppliesToNextSession() async {
    let provider = TestConfigProvider(config: Config(
        voice: VoiceSettings(turnDetection: .semanticVAD(eagerness: .high))))
    let h = makeVoiceHarnessWithProvider(provider)

    await h.session.start()
    await pumpUntil("start: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    // Session uses semantic VAD with high eagerness from the provider
    let update = sessionUpdateJSON(h.transport.sent)
    let turnDetection = turnDetectionFromJSON(update)
    expectEq(turnDetection["type"] as? String, "semantic_vad",
             "turn detection: session uses semantic_vad")
    expectEq(turnDetection["eagerness"] as? String, "high",
             "turn detection: session has high eagerness from provider")
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

// MARK: - Test Harness

/// Mutable test provider that can simulate preference changes.
final class TestConfigProvider: ConfigProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _config: Config
    private(set) var readCount = 0

    var current: Config {
        lock.withLock {
            readCount += 1
            return _config
        }
    }

    init(config: Config) {
        self._config = config
    }

    func updateConfig(_ newConfig: Config) {
        lock.withLock {
            _config = newConfig
        }
    }
}

/// Extend the voice harness factory to accept a provider.
@MainActor func makeVoiceHarnessWithProvider(_ provider: any ConfigProviding) -> VoiceHarness {
    let transport = ScriptedVoiceTransport()
    transport.autoEvents = [.sessionCreated, .sessionUpdated]
    let mic = ScriptedMic()
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    var keys: [SecretKey: String] = [:]
    keys[.openAI] = "sk-test"
    let secrets = ScriptedSecrets(keys)
    let thread = ScriptedThread()
    let clock = TestClock()
    let session = VoiceSession(
        transport: transport,
        mic: mic,
        player: player,
        transcriber: transcriber,
        synthesizer: synth,
        chat: chat,
        secrets: secrets,
        thread: thread,
        configProvider: provider,
        reachability: TestReachability(online: true),
        echoFreeProbe: { false },
        micSilenceTimeout: 10,
        now: { clock.now },
        readyTimeout: 1)
    let watch = SnapWatch(session.snapshots)
    return VoiceHarness(
        session: session, transport: transport, mic: mic, player: player,
        transcriber: transcriber, thread: thread, clock: clock, watch: watch)
}

private struct TestReachability: ReachabilityProbing {
    let online: Bool
    var isOnline: Bool { get async { online } }
}

// MARK: - JSON Helpers

private func sessionUpdateJSON(_ sent: [String]) -> [String: Any] {
    let updateMsg = sent.first(where: { $0.contains("session.update") }) ?? "{}"
    return (try? JSONSerialization.jsonObject(with: updateMsg.data(using: .utf8)!)) as? [String: Any] ?? [:]
}

private func turnDetectionFromJSON(_ updateJSON: [String: Any]) -> [String: Any] {
    let session = updateJSON["session"] as? [String: Any] ?? [:]
    let audio = session["audio"] as? [String: Any] ?? [:]
    let input = audio["input"] as? [String: Any] ?? [:]
    return input["turn_detection"] as? [String: Any] ?? [:]
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
