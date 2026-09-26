import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Code review 2026-09-24 (alto). A hold turn that failed after an earlier
// reply "recovered" into `.listening` with a hot mic and no key held: the
// hold branch of `speechFinished` never cleared `inConversation`, so the
// next failure took the hands-free recover path. A hold fails to rest with
// its IO stopped; and the hands-free recover retries once, not forever.

@Test @MainActor func holdFailureTests() async {
    testAFailedHoldTurnAfterAReplyRestsWithTheMicOff()
    testAFailedHoldStartTearsDownWhatItOpened()
    testTheRecoverLoopRetriesOnceThenFails()
    testARecoverThatArmedCanRecoverAgain()
    await testAChatErrorOnTheSecondHoldLeavesNoHotMic()
}

private func step(_ m: inout TurnMachine, _ event: TurnEvent) -> [TurnEffect] {
    m.handle(event, at: 0)
}

/// One whole hold: press, arm, release with speech, reply, spoken.
private func completedHold(_ m: inout TurnMachine) {
    _ = step(&m, .holdPressed(preferRealtime: false))
    _ = step(&m, .classicListenArmed)
    _ = step(&m, .holdReleased(hasSpeech: true))
    _ = step(&m, .firstSentence)
    _ = step(&m, .replyCompleted)
    _ = step(&m, .speechFinished)
}

@MainActor func testAFailedHoldTurnAfterAReplyRestsWithTheMicOff() {
    var m = TurnMachine()
    completedHold(&m)
    expectEq(m.snapshot.state, .idle, "falla: el primer hold terminó en reposo")
    _ = step(&m, .holdPressed(preferRealtime: false))
    _ = step(&m, .classicListenArmed)
    _ = step(&m, .holdReleased(hasSpeech: true))
    expectEq(m.snapshot.state, .thinking, "falla: el segundo hold piensa")
    let effects = step(&m, .turnFailed(.sessionDropped))
    expect(m.snapshot.state != .listening, "falla: nunca vuelve a escuchar sin tecla")
    expect(effects.contains(.stopClassicIO), "falla: apaga el micro del hold")
    expect(!effects.contains(.requestClassicListen), "falla: no lo reabre")
}

/// The mic came up but the ear did not: the pending listen still owns a
/// running mic, and a failure must stop it.
@MainActor func testAFailedHoldStartTearsDownWhatItOpened() {
    var m = TurnMachine()
    completedHold(&m)
    _ = step(&m, .holdPressed(preferRealtime: false))
    let effects = step(&m, .voiceStartFailed(.speechEngine))
    expect(m.snapshot.state != .listening, "arranque: no queda escuchando")
    expect(effects.contains(.stopClassicIO), "arranque: apaga lo que abrió")
}

@MainActor func testTheRecoverLoopRetriesOnceThenFails() {
    var m = TurnMachine(snapshot: TurnSnapshot(
        state: .listening, pipeline: .classic, inConversation: true))
    let first = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .listening, "bucle: el primer fallo reintenta")
    expect(first.contains(.requestClassicListen), "bucle: pide escuchar otra vez")
    let second = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .error, "bucle: el segundo fallo seguido se rinde")
    expect(!second.contains(.requestClassicListen), "bucle: sin otro reintento")
}

@MainActor func testARecoverThatArmedCanRecoverAgain() {
    var m = TurnMachine(snapshot: TurnSnapshot(
        state: .listening, pipeline: .classic, inConversation: true))
    _ = step(&m, .voiceStartFailed(.micUnavailable))
    _ = step(&m, .classicListenArmed)
    _ = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .listening, "bucle: un reintento que sí armó cuenta de cero")
}

/// The chat fails only on its second call.
private final class SecondCallFailsChat: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        return AsyncThrowingStream { continuation in
            if call == 1 {
                continuation.yield(.text("Listo."))
                continuation.finish()
            } else {
                continuation.finish(throwing: ChatError.timeout)
            }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

@MainActor func testAChatErrorOnTheSecondHoldLeavesNoHotMic() async {
    let mic = ScriptedMic()
    let transcriber = ScriptedTranscriber()
    transcriber.stoppedText = "qué hora es"
    let synth = ScriptedSynth()
    let chat = SecondCallFailsChat()
    let session = VoiceSession(
        transport: ScriptedVoiceTransport(), mic: mic, player: ScriptedPlayer(),
        transcriber: transcriber, synthesizer: synth, chat: chat,
        secrets: ScriptedSecrets(), thread: ScriptedThread(),
        configProvider: StaticConfigProvider(Config(language: .es)),
        reachability: AssumeOnline(), echoFreeProbe: { false }, releaseTail: 0)
    let watch = SnapWatch(session.snapshots)

    await session.hold()
    await pumpUntil("hold 1: listening") { watch.latest.state == .listening }
    await session.release()
    await pumpUntil("hold 1: habla") { watch.latest.state == .speaking }
    await session.awaitClassicTurn()
    synth.yield(.finished)
    await pumpUntil("hold 1: reposo") { watch.latest.state == .idle }

    await session.hold()
    await pumpUntil("hold 2: listening") { watch.latest.state == .listening }
    await session.release()
    await pumpUntil("hold 2: el chat falla") { chat.callCount == 2 }
    await session.awaitClassicTurn()
    await settle(0.05)
    expect(watch.latest.state != .listening, "hold 2: no queda escuchando sin tecla")
    expect(mic.stopped, "hold 2: el micro se apaga")
}
