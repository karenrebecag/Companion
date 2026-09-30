import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Split out of HoldVoiceTests.swift to keep it under 800 lines.

@Test @MainActor func holdPressSenseTests() async {
    await testPressTimeSenseIsNotRepeatedAtCommit()
    await testDiscardCancelsThePressSenseTask()
    await testSenseVoiceWithoutASensorIsUnaffected()
    await testDictationSuccessCancelsThePressSenseTask()
    await testSilentDictationHoldCancelsThePressSenseTask()
}

private let slack = FocusedField(app: "Slack", pid: 42)

// Wave 15b-5. Sentir al pulsar: `fanOut()` arranca `sensor.sense(...)` en
// una Task a la vez que el micro, y `senseVoice` la espera en vez de pagar
// el sensor otra vez al comprometer el turno.

/// A sensor with a real delay, so a test can prove `senseVoice` reads an
/// already-finished press-time Task instead of paying the delay again at
/// commit — and records whether cancellation ever reached it.
final class DelayedContextSensor: ContextSensing, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _cancelled = false
    private var _finished = 0
    var finished: Int { lock.withLock { _finished } }
    var calls: Int { lock.withLock { _calls } }
    var wasCancelled: Bool { lock.withLock { _cancelled } }
    private let delay: TimeInterval
    private let laterDelay: TimeInterval
    private let context: TurnContext

    /// `laterDelay` applies from the second `sense` on: a test that must prove
    /// the commit does not sense again makes a second call unmistakably slow.
    init(delay: TimeInterval, laterDelay: TimeInterval? = nil, context: TurnContext) {
        self.delay = delay
        self.laterDelay = laterDelay ?? delay
        self.context = context
    }

    func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        let call = lock.withLock { _calls += 1; return _calls }
        do {
            try await Task.sleep(for: .seconds(call == 1 ? delay : laterDelay))
            lock.withLock { _finished += 1 }
        } catch {
            lock.withLock { _cancelled = true }
        }
        return context
    }
}

/// A sensor slower than the gap between press and release must not add its
/// own delay a second time at commit: `senseVoice` reads the press-time
/// Task's already-finished value instead of calling `sense` again.
@MainActor func testPressTimeSenseIsNotRepeatedAtCommit() async {
    let sensor = DelayedContextSensor(
        delay: 0.2, laterDelay: 30, context: TurnContext(source: .typed, focusedApp: "Notes"))
    let h = makeVoiceHarness(sensor: sensor)
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("press-sense: listening") { h.watch.latest.state == .listening }
    // Causal, not a wall-clock guess: under a loaded parallel run 0.35 s did not
    // always outlast the sensor's 0.2 s, so the release awaited the remainder.
    await pumpUntil("press-sense: el sense de la pulsación terminó") { sensor.finished == 1 }
    await h.session.release()
    await pumpUntil("press-sense: el chat recibe el turno") { !h.chat.histories.isEmpty }
    expectEq(sensor.calls, 1, "press-sense: un solo sense, en la pulsación")
    let last = h.chat.histories[0].last { $0.role == .user }
    expect(last?.content.contains("Notes") == true, "press-sense: el contexto sensado al pulsar viaja")
}

/// A tap (discard) never sends a turn, so the press-time sense it started
/// has no commit to feed — the Task is cancelled instead of finishing
/// unread in the background.
@MainActor func testDiscardCancelsThePressSenseTask() async {
    let sensor = DelayedContextSensor(delay: 2, context: TurnContext(source: .typed))
    let h = makeVoiceHarness(sensor: sensor)
    await h.session.hold()
    await pumpUntil("cancel: listening") { h.watch.latest.state == .listening }
    await pumpUntilAsync("cancel: el sense arrancó") { sensor.calls == 1 }
    await h.session.discard()
    await pumpUntil("cancel: idle o mute") {
        h.watch.latest.state == .idle || h.watch.latest.muted
    }
    await pumpUntilAsync("cancel: el Task de sense se cancela") { sensor.wasCancelled }
}

/// Code review 2026-09-23 (medio): `completeHold`'s dictation-success
/// branch returns through `.holdDiscarded` and never calls `senseVoice` —
/// the press-time sense `fanOut` started was left running, uncancelled
/// (only `discard()`, a tap with no release, cancelled it).
@MainActor func testDictationSuccessCancelsThePressSenseTask() async {
    let sensor = DelayedContextSensor(delay: 2, context: TurnContext(source: .typed))
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(
        sensor: sensor, fieldProbe: ScriptedFieldProbe(slack), injector: injector)
    h.transcriber.stoppedText = "hola qué tal"
    await h.session.hold(dictate: true)
    await pumpUntil("dictado cancela: listening") { h.watch.latest.state == .listening }
    await pumpUntilAsync("dictado cancela: el sense arrancó") { sensor.calls == 1 }
    await h.session.release()
    await pumpUntil("dictado cancela: pega") { injector.texts == ["hola qué tal"] }
    await pumpUntilAsync("dictado cancela: el Task de sense se cancela") { sensor.wasCancelled }
}

/// Same gap, the other early return: a dictation hold with nothing heard
/// (`text.isEmpty`) also ends in `.holdDiscarded` without ever reading the
/// press-time sense.
@MainActor func testSilentDictationHoldCancelsThePressSenseTask() async {
    let sensor = DelayedContextSensor(delay: 2, context: TurnContext(source: .typed))
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(
        sensor: sensor, fieldProbe: ScriptedFieldProbe(slack), injector: injector)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = ""
    await h.session.hold(dictate: true)
    await pumpUntil("silencio cancela: listening") { h.watch.latest.state == .listening }
    await pumpUntilAsync("silencio cancela: el sense arrancó") { sensor.calls == 1 }
    await h.session.release()
    await pumpUntil("silencio cancela: lo dice") { seen.events.contains { $0 == .heardNothing } }
    await pumpUntilAsync("silencio cancela: el Task de sense se cancela") { sensor.wasCancelled }
}

/// Without a sensor configured, a classic hold behaves exactly as before
/// 15b-5: no context block on the turn.
@MainActor func testSenseVoiceWithoutASensorIsUnaffected() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("sin sensor: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("sin sensor: chat") { !h.chat.histories.isEmpty }
    let last = h.chat.histories[0].last { $0.role == .user }
    expect(last?.content.contains("<context") != true, "sin sensor: sin bloque de contexto")
}
