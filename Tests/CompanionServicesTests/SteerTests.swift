import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15b-10. Pressing while the classic turn thinks or speaks cuts it:
// the reducer used to no-op on `.thinking` (spec §1-D), and even fixed, the
// turn kept running as a plain `await` nothing could reach to cancel. Now
// `classic.submit` runs in its own task (`VoiceSessionSteer`), and
// `ClassicRuntime` itself refuses to enqueue, thread or delegate once cut.

@Test @MainActor func steerTests() async {
    testInterruptDuringClassicThinkingCuts()
    testInterruptDuringClassicSpeakingEndsIdleNotListening()
    await testCutBeforeAnySentenceEnqueuesNothing()
    await testCutMidSentenceStopsFurtherEnqueues()
    await testCancelDuringActStopsTheNextChatStream()
    await testCutBeforeHandoffNeverCallsOnDelegate()
    await testDelegateAlreadySentSurvivesALaterCut()
    await testCutThreadsWhatWasAlreadySpoken()
    await testSteerPendingReachesTheNextTurnExactlyOnce()
    await testSteerPendingIsConsumedEvenWhenTheRouterHandlesTheTurn()
}

// MARK: - TurnMachine (pure)

@MainActor func testInterruptDuringClassicThinkingCuts() {
    var machine = TurnMachine(snapshot: TurnSnapshot(state: .thinking, pipeline: .classic))
    let effects = machine.handle(.interrupt, at: 0)
    expectEq(effects, [.cancelAgentOutput(steer: false), .stopClassicIO],
             "15b code review: interrupt en clásico corta y apaga el micro, no lo reabre")
    expectEq(machine.snapshot.state, .idle, "15b code review: idle, no listening con el micro huérfano")
    expect(machine.snapshot.pipeline == nil, "15b code review: sin pipeline armado")
}

@MainActor func testInterruptDuringClassicSpeakingEndsIdleNotListening() {
    var machine = TurnMachine(snapshot: TurnSnapshot(state: .speaking, pipeline: .classic))
    let effects = machine.handle(.interrupt, at: 0)
    expectEq(effects, [.cancelAgentOutput(steer: false), .stopClassicIO],
             "15b code review: mismo corte mientras habla")
    expectEq(machine.snapshot.state, .idle, "15b code review: idle mientras hablaba")
}

@MainActor func testCutBeforeAnySentenceEnqueuesNothing() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "cuéntame algo largo"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("15b-10: el chat arrancó") { !chat.histories.isEmpty }

    task.cancel()
    chat.finish(toCall: 0)
    await task.value

    expect(synth.queue.isEmpty, "15b-10: cortado antes de la primera frase, cero enqueue")
    expect(runtime.steerPending, "15b-10: deja nota para el siguiente turno")
}

@MainActor func testCutMidSentenceStopsFurtherEnqueues() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "cuéntame algo largo"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("15b-10: el chat arrancó") { !chat.histories.isEmpty }

    chat.yield(.text("Esta es una respuesta larga para el corte. "), toCall: 0)
    await pumpUntilAsync("15b-10: la primera frase sonó") { !synth.queue.isEmpty }
    let queueAtCut = synth.queue

    task.cancel()
    // A stale delta reaching an already-cancelled task must never enqueue —
    // reproduces spec §1-D (a stray sentence sounding after the cut).
    chat.yield(.text("Esto no debería sonar nunca."), toCall: 0)
    chat.finish(toCall: 0)
    await task.value

    expectEq(synth.queue, queueAtCut,
             "15b-10: nada se encola después del corte, aunque el fake siga mandando texto")
}

/// Code review 2026-09-23 (bajo): a non-handoff tool round checked
/// `Task.isCancelled` after the stream and inside the handoff branch, but
/// NOT right after `act()` — a press landing mid-`act()` still fell through
/// to the next round's `chat.stream`, one extra network call the user's
/// cut should have prevented.
@MainActor func testCancelDuringActStopsTheNextChatStream() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre safari"
    let thread = ScriptedThread()
    let tools = GatedParentTools()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.parentTools = tools
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("act cancel: el chat arrancó") { !chat.histories.isEmpty }

    chat.yield(
        .toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)]),
        toCall: 0)
    chat.finish(toCall: 0)
    await tools.waitUntilBlocked()

    task.cancel()
    tools.release()
    await task.value

    expectEq(chat.histories.count, 1,
             "act cancel: un corte durante act() no dispara la siguiente ronda de chat.stream")
}

@MainActor func testCutBeforeHandoffNeverCallsOnDelegate() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "crea un archivo"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    let delegated = HandoffSpy()
    runtime.onDelegate = { delegated.record($0) }
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("15b-10: el chat arrancó") { !chat.histories.isEmpty }

    chat.yield(.handoff(Handoff(goal: "crea un archivo", context: "")), toCall: 0)
    task.cancel()
    chat.finish(toCall: 0)
    await task.value

    expect(delegated.goals.isEmpty, "15b-10: cortar antes del handoff nunca dispara onDelegate")
}

@MainActor func testDelegateAlreadySentSurvivesALaterCut() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "crea un archivo"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    let delegated = HandoffSpy()
    runtime.onDelegate = { delegated.record($0) }
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("15b-10: el chat arrancó") { !chat.histories.isEmpty }

    chat.yield(.handoff(Handoff(goal: "crea un archivo", context: "")), toCall: 0)
    chat.finish(toCall: 0)
    await task.value
    expectEq(delegated.goals, ["crea un archivo"],
             "15b-10: el encargo salió antes de cualquier corte")

    // A press that cuts the (already finished) turn afterward must not
    // retract the errand already handed off — it runs on its own task in
    // VoiceSession, structurally outside `classicTurnTask`.
    task.cancel()
    expectEq(delegated.goals, ["crea un archivo"],
             "15b-10: un encargo en marcha no se cancela")
}

@MainActor func testCutThreadsWhatWasAlreadySpoken() async {
    let chat = GatedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "cuéntame algo largo"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    let task = Task { await runtime.submit(config: Config(language: .en)) { _ in } }
    await pumpUntilAsync("15b-10: el chat arrancó") { !chat.histories.isEmpty }

    chat.yield(.text("Esta es una respuesta larga para el corte. "), toCall: 0)
    await pumpUntilAsync("15b-10: la primera frase sonó") { !synth.queue.isEmpty }
    // The synthesizer's own record of what actually played, independent of
    // what the model kept generating past the cut.
    synth.spoken = "Esta es una respuesta larga para el corte."

    task.cancel()
    chat.finish(toCall: 0)
    await task.value

    expectEq(thread.turns.last?.role, .assistant, "15b-10: el parcial entra como del asistente")
    expectEq(thread.turns.last?.content, "Esta es una respuesta larga para el corte.",
             "15b-10: lo ya dicho, no lo que seguía generando")
    expect(thread.finished, "15b-10: cierra el stream del hilo igual que un turno normal")
}

// MARK: - Wave 15b-11: the steer note, consumed exactly once

@MainActor func testSteerPendingReachesTheNextTurnExactlyOnce() async {
    let chat = ScriptedChat()
    chat.rounds = [[.text("Uno.")], [.text("Dos.")]]
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice))
    runtime.steerPending = true

    transcriber.stoppedText = "sigue"
    await runtime.submit(config: Config(language: .en)) { _ in }
    let first = chat.histories[0].last { $0.role == .user }
    expect(first?.content.contains("<steer>") == true,
           "15b-11: el primer turno tras el corte lleva la nota")
    expect(!runtime.steerPending, "15b-11: se consume, no queda pegada")

    transcriber.stoppedText = "y ahora esto"
    await runtime.submit(config: Config(language: .en)) { _ in }
    let second = chat.histories[1].last { $0.role == .user }
    expect(second?.content.contains("<steer>") != true,
           "15b-11: el turno siguiente ya no la lleva")
}

@MainActor func testSteerPendingIsConsumedEvenWhenTheRouterHandlesTheTurn() async {
    let chat = ScriptedChat()
    let synth = ScriptedSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.steerPending = true
    runtime.decide = { _, _ in
        .acted(
            ParentToolOutcome(ok: true, output: "", target: "Safari"),
            ToolCallRef(id: "1", name: "open_app", arguments: #"{"name":"Safari"}"#))
    }

    await runtime.submit(config: Config(language: .en)) { _ in }

    expect(!runtime.steerPending,
           "15b-11: un turno que resuelve el router también consume la nota")
}

// MARK: - VoiceSession (the real actor, TurnMachine + ClassicRuntime wired together)

final class GatedChat: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncThrowingStream<ChatDelta, Error>.Continuation] = []
    private var _histories: [[Turn]] = []
    var histories: [[Turn]] { lock.withLock { _histories } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        lock.withLock { _histories.append(history) }
        return AsyncThrowingStream { continuation in
            self.lock.withLock { self.continuations.append(continuation) }
        }
    }

    func yield(_ delta: ChatDelta, toCall index: Int) {
        let cont = lock.withLock { index < continuations.count ? continuations[index] : nil }
        cont?.yield(delta)
    }

    func finish(toCall index: Int) {
        let cont = lock.withLock { index < continuations.count ? continuations[index] : nil }
        cont?.finish()
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

/// A parent-tool fake whose `execute` blocks until released, so a test can
/// cancel the turn WHILE a non-handoff tool round is running.
final class GatedParentTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var gate: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }

    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock {
                gate = c
                if let waiter {
                    waiter.resume()
                    self.waiter = nil
                }
            }
        }
        return ParentToolOutcome(ok: true, output: "done", target: name)
    }

    func waitUntilBlocked() async {
        if lock.withLock({ gate != nil }) { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock { waiter = c }
        }
    }

    func release() {
        lock.withLock { gate?.resume(); gate = nil }
    }
}

/// Records every handoff `onDelegate` receives, lock-protected so a spy
/// closure can mutate it from inside a cancellable `Task`.
final class HandoffSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _goals: [String] = []
    var goals: [String] { lock.withLock { _goals } }
    func record(_ handoff: Handoff) { lock.withLock { _goals.append(handoff.goal) } }
}

private struct SteerHarness {
    let session: VoiceSession
    let transcriber: ScriptedTranscriber
    let synth: ScriptedSynth
    let watch: SnapWatch
    let mic: ScriptedMic
    let thread: ScriptedThread
}

/// Classic-only (no OpenAI key): the fewest moving parts that still wire
/// `TurnMachine`, `VoiceSessionSteer` and `ClassicRuntime` together for real.
@MainActor
private func makeSteerHarness(chat: GatedChat) -> SteerHarness {
    let mic = ScriptedMic()
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let secrets = ScriptedSecrets()
    let thread = ScriptedThread()
    let provider = StaticConfigProvider(Config(language: .en))
    let session = VoiceSession(
        mic: mic, player: player, transcriber: transcriber,
        synthesizer: synth, chat: chat, secrets: secrets, thread: thread,
        configProvider: provider, reachability: AssumeOnline(), now: { 0 })
    let watch = SnapWatch(session.snapshots)
    return SteerHarness(
        session: session, transcriber: transcriber, synth: synth, watch: watch, mic: mic, thread: thread)
}
