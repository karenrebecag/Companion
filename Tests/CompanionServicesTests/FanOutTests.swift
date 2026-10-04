import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15b-4. Warm the voice at press: the closed set of fixed phrases and
// the TLS connection to api.openai.com, both paid for while the mic is
// still opening — so a router order's ack can come from a warm socket
// instead of a cold TLS handshake plus a cold fetch.

@Test @MainActor func fanOutTests() async {
    await testHoldWithAKeyWarmsOnce()
    await testABouncedPressDoesNotWarmAgain()
    await testHoldWithoutAKeyWarmsNothing()
    await testWarmSendsNoAuthorizationAndNoBody()
    await testARapidSecondPressCancelsTheFirstPressedContext()
}

/// Code review 2026-09-23 (medio): `fanOut()` reassigned `classic.pressedContext`
/// on every fresh press with no regard for a previous scan still running —
/// a hold that ended without ever reading its sense (silence, no dictate
/// field) left that Task orphaned, and the very next press dropped the only
/// reference to it instead of cancelling it first.
@MainActor func testARapidSecondPressCancelsTheFirstPressedContext() async {
    let sensor = DelayedContextSensor(delay: 2, context: TurnContext(source: .typed))
    let h = makeVoiceHarness(key: nil, sensor: sensor)
    await h.session.hold()
    await pumpUntil("doble press: listening") { h.watch.latest.state == .listening }
    await pumpUntilAsync("doble press: el primer sense arrancó") { sensor.calls == 1 }
    // Nothing said: this hold ends idle through the path that never reads
    // the press-time sense (`.agent`, `hasSpeech: false` — `advance` hangs
    // up without ever calling `senseVoice`).
    h.mic.receivedBufferValue = false
    await h.session.release()
    await pumpUntil("doble press: idle tras soltar en silencio") { h.watch.latest.state == .idle }

    await h.session.hold()
    await pumpUntil("doble press: listening de nuevo") { h.watch.latest.state == .listening }
    await pumpUntilAsync("doble press: el primer Task se cancela, no queda huérfano") {
        sensor.wasCancelled
    }
    expectEq(sensor.calls, 2, "doble press: el segundo press sensa el suyo propio")
}

@MainActor func testHoldWithAKeyWarmsOnce() async {
    let (session, synth, secrets, watch) = makeFanOutSession(key: "sk-test")
    await session.hold()
    await pumpUntil("fanout: listening") { watch.latest.state == .listening }
    await pumpUntilAsync("fanout: warmConnection corrió") { await synth.warmedConnections == 1 }
    expectEq(await synth.prewarmed.count, 1, "fanout: un solo prewarm")
    expect(!(await synth.prewarmed.first ?? []).isEmpty, "fanout: el set no está vacío")
    expect(secrets.reads > 0, "fanout: sí lee la clave (al pulsar, no al boot)")
}

@MainActor func testABouncedPressDoesNotWarmAgain() async {
    let (session, synth, _, watch) = makeFanOutSession(key: "sk-test", readyTimeout: 5)
    await session.hold()
    await pumpUntil("fanout rebote: listening") { watch.latest.state == .listening }
    await pumpUntilAsync("fanout rebote: primer warm") { await synth.warmedConnections == 1 }
    await session.hold()
    await settle(0.1)
    expectEq(await synth.warmedConnections, 1, "fanout rebote: no repite warmConnection")
    expectEq(await synth.prewarmed.count, 1, "fanout rebote: no repite prewarm")
}

@MainActor func testHoldWithoutAKeyWarmsNothing() async {
    let (session, synth, _, watch) = makeFanOutSession(key: nil)
    await session.hold()
    await pumpUntil("fanout sin clave: listening") { watch.latest.state == .listening }
    await settle(0.1)
    expectEq(await synth.warmedConnections, 0, "fanout sin clave: sin warmConnection")
    expect(await synth.prewarmed.isEmpty, "fanout sin clave: sin prewarm")
}

@MainActor func testWarmSendsNoAuthorizationAndNoBody() async {
    let transport = ScriptedTransport()
    transport.stub(url: "https://api.openai.com/v1/models", ScriptedReply(status: 200))
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let client = OpenAITTSClient(
        secrets: secrets, transport: transport, language: .es, speechCode: { "es" })
    await client.warm()
    let request = transport.requests.last
    expectEq(request?.url?.absoluteString, "https://api.openai.com/v1/models", "warm: endpoint")
    expectEq(request?.httpMethod, "GET", "warm: GET")
    expect(request?.value(forHTTPHeaderField: "Authorization") == nil, "warm: sin Authorization")
    expect(request?.httpBody == nil, "warm: sin cuerpo")
    expectEq(secrets.reads, 0, "warm: nunca toca el llavero")
}

// MARK: - Harness

private struct AlwaysOnline: ReachabilityProbing {
    var isOnline: Bool { get async { true } }
}

/// A synthesizer that actually records `isCached`/`prewarm`/`warmConnection`
/// — `ScriptedSynth` (12b's fake) deliberately keeps using `VoicePorts`'
/// no-op defaults, so this delivery's own tests need a spy that tracks them.
final class RecordingWarmSynth: SpeechSynthesizer, @unchecked Sendable {
    private let lock = NSLock()
    var queue: [String] = []
    private var _prewarmed: [[String]] = []
    private var _warmedConnections = 0
    var prewarmed: [[String]] { lock.withLock { _prewarmed } }
    var warmedConnections: Int { lock.withLock { _warmedConnections } }
    private let box = StreamBox<SpeechEvent>()
    var events: AsyncStream<SpeechEvent> { box.stream }
    func begin() async {}
    func enqueue(_ sentence: String) async { queue.append(sentence) }
    func finish() async {}
    func stop() async {}
    func spokenSoFar() async -> String? { nil }
    var speakingNow: String { "" }
    func isCached(_ phrase: String) async -> Bool { false }
    func prewarm(_ phrases: [String]) async { lock.withLock { _prewarmed.append(phrases) } }
    func warmConnection() async { lock.withLock { _warmedConnections += 1 } }
}

@MainActor func makeFanOutSession(
    key: String?, readyTimeout: TimeInterval = harnessReadyTimeout
) -> (VoiceSession, RecordingWarmSynth, ScriptedSecrets, SnapWatch) {
    let transport = ScriptedVoiceTransport()
    transport.autoEvents = [.sessionCreated, .sessionUpdated]
    let mic = ScriptedMic()
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = RecordingWarmSynth()
    let chat = ScriptedChat()
    var keys: [SecretKey: String] = [:]
    if let key { keys[.openAI] = key }
    let secrets = ScriptedSecrets(keys)
    let thread = ScriptedThread()
    let provider = StaticConfigProvider(Config(ownerFirstName: "Karen", language: .en))
    let session = VoiceSession(
        transport: transport, mic: mic, player: player, transcriber: transcriber,
        synthesizer: synth, chat: chat, secrets: secrets, thread: thread,
        configProvider: provider, reachability: AlwaysOnline(),
        echoFreeProbe: { false }, readyTimeout: readyTimeout)
    let watch = SnapWatch(session.snapshots)
    return (session, synth, secrets, watch)
}
