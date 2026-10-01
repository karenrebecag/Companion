import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// classic-turn-serialize (D2): the press that cuts a classic turn starts the
// next one while the cut one may still be inside a call that ignores
// cancellation. The next turn waits for it, up to a deadline; past it, the
// stuck turn's late `cutTurn` writes are discarded (ADR 008).

private struct StuckRig {
    let h: VoiceHarness
    let tools: GatedParentTools
}

/// Chat script shared by the VoiceSession-level tests: turn 1 asks for a
/// tool that never returns until released, turn 2 answers.
@MainActor
private func stuckRig(deadline: (@Sendable () async -> Void)?) async -> StuckRig {
    let tools = GatedParentTools()
    let h = makeVoiceHarness(
        key: nil, language: .es, parentTools: tools,
        sensor: FakeContextSensor(TurnContext(source: .voice)))
    if let deadline {
        let classic = await h.session.classic
        classic.turnWaitDeadline = deadline
    }
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)])],
        [.text("Vale, Notes.")],
    ]
    h.transcriber.stoppedText = "abre Safari"
    return StuckRig(h: h, tools: tools)
}

/// Turn 1 is blocked in the tool; a second press cuts it and turn 2 is
/// released with its words. Returns turn 1's handle: the session keeps only
/// the latest one.
@MainActor @discardableResult
private func pressAgainWhileStuck(_ rig: StuckRig) async -> Task<Void, Never>? {
    let h = rig.h
    await h.session.hold()
    await pumpUntil("1") { h.watch.latest.state == .listening }
    await h.session.release()
    await rig.tools.waitUntilBlocked()
    let stuck = await h.session.classicTurnTask
    h.synth.spoken = "Abro Safari."
    await h.session.hold()
    await pumpUntil("2") { h.watch.latest.state == .listening }
    h.transcriber.stoppedText = "mejor Notes"
    await h.session.release()
    return stuck
}

/// Like `pumpUntil`, but answers instead of recording a failure.
@MainActor
private func poll(_ seconds: TimeInterval, _ pred: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !pred(), Date() < end {
        await Task.yield()
        do { try await Task.sleep(for: .milliseconds(2)) } catch { break }
    }
    return pred()
}

@Suite struct ClassicTurnSerialize {
    // The gate opens only after looking at whether turn 2 reached the chat,
    // so the order cannot depend on the scheduler.
    @Test @MainActor func aCutTurnStuckInAToolStillSteersTheNextTurn() async {
        let rig = await stuckRig(deadline: { try? await Task.sleep(for: .seconds(30)) })
        let h = rig.h
        await pressAgainWhileStuck(rig)
        let ranAhead = await poll(1) { h.chat.histories.count >= 2 }
        #expect(!ranAhead, "turn 2 reached the model while turn 1 was still cutting")
        rig.tools.release()
        await h.session.awaitClassicTurn()
        _ = await poll(2) { h.thread.turns.contains { $0.content == "Abro Safari." } }
        let second = h.chat.histories.count >= 2 ? h.chat.histories[1].last { $0.role == .user } : nil
        #expect(second?.content.contains("<steer>") == true)
        let partial = h.thread.turns.firstIndex { $0.role == .assistant && $0.content == "Abro Safari." }
        let next = h.thread.turns.firstIndex { $0.role == .user && $0.content == "mejor Notes" }
        #expect(partial != nil && next != nil && partial! < next!)
    }

    @Test @MainActor func aStuckTurnPastTheDeadlineLetsTheNextOneStartAndWritesNothingLate() async {
        let rig = await stuckRig(deadline: { try? await Task.sleep(for: .milliseconds(50)) })
        let h = rig.h
        let stuck = await pressAgainWhileStuck(rig)
        let started = await poll(5) { h.chat.histories.count >= 2 }
        #expect(started, "turn 2 never started once the deadline expired")
        await h.session.awaitClassicTurn()
        rig.tools.release()
        await stuck?.value
        #expect(!h.thread.turns.contains { $0.role == .assistant && $0.content == "Abro Safari." },
                "the stuck turn threaded its partial after being superseded")
        let pending = await h.session.classic.steerPending
        #expect(!pending, "the stuck turn left a note for a later turn")
        #expect(h.chat.histories.count == 2, "the stuck turn went on to the model")
    }

    // The wait on a predecessor cannot be cancelled, so turn 2 only learns it
    // was cut once turn 1 ends; it must then leave without a trace.
    @Test @MainActor func threePressesOverAStuckToolOnlyTheLastTurnReachesTheChat() async {
        let rig = await stuckRig(deadline: { try? await Task.sleep(for: .seconds(30)) })
        let h = rig.h
        await pressAgainWhileStuck(rig)
        await h.session.hold()
        await pumpUntil("3") { h.watch.latest.state == .listening }
        h.transcriber.stoppedText = "mejor Mail"
        await h.session.release()
        let ranAhead = await poll(1) { h.chat.histories.count >= 2 }
        #expect(!ranAhead, "a later turn reached the model while turn 1 was stuck")
        rig.tools.release()
        await h.session.awaitClassicTurn()
        _ = await poll(2) { h.chat.histories.count >= 2 }
        #expect(h.chat.histories.count == 2, "only turn 1 and the last turn reach the model")
        let users = h.thread.turns.filter { $0.role == .user }.map(\.content)
        #expect(users == ["abre Safari", "mejor Mail"], "the middle turn threaded: \(users)")
    }

    // Q3: a turn cut before its words reach the model leaves no trace.
    @Test func aTurnCutWhileItsEarWasFinishingThreadsNothingAndLeavesNoNote() async {
        let ear = GatedEar(text: "abre Safari")
        let synth = ScriptedSynth()
        synth.spoken = "Abro Sa"
        let chat = ScriptedChat()
        chat.rounds = [[.text("Vale.")]]
        let thread = ScriptedThread()
        let runtime = ClassicRuntime(transcriber: ear, synthesizer: synth, chat: chat, thread: thread)
        runtime.languageRecognizer = FakeRecognizer()
        let pressContext = Task<TurnContext?, Never> { TurnContext(source: .voice) }
        runtime.pressedContext = pressContext

        let turn = Task.detached { await runtime.submit(config: Config(language: .es)) { _ in } }
        await ear.waitUntilStopping()
        turn.cancel()
        ear.finish()
        await turn.value

        #expect(thread.turns.isEmpty, "a cut turn threaded: \(thread.turns.map(\.content))")
        #expect(chat.histories.isEmpty)
        #expect(!runtime.steerPending)
        #expect(runtime.pressedContext != nil, "the cut turn took the next hold's context")
    }
}

// R3 (interrupciones-por-causa): the steer note says "I cut you to change
// course". An explicit stop is not a change of course, so it leaves no note;
// what was already said is still real and still threaded.
@Suite struct StopLeavesNoSteerNote {
    @Test @MainActor func aStopWhileStuckInAToolThreadsThePartialButLeavesNoNote() async {
        let rig = await stuckRig(deadline: { try? await Task.sleep(for: .seconds(30)) })
        let h = rig.h
        await h.session.hold()
        await pumpUntil("1") { h.watch.latest.state == .listening }
        await h.session.release()
        await rig.tools.waitUntilBlocked()
        h.synth.spoken = "Abro Safari."
        await h.session.interrupt()
        rig.tools.release()
        await h.session.awaitClassicTurn()

        #expect(h.thread.turns.contains { $0.role == .assistant && $0.content == "Abro Safari." },
                "a stop dropped what had already been said")
        let pending = await h.session.classic.steerPending
        #expect(!pending, "a stop left a steer note for the next turn")

        await h.session.hold()
        await pumpUntil("2") { h.watch.latest.state == .listening }
        h.transcriber.stoppedText = "abre Notes"
        await h.session.release()
        await h.session.awaitClassicTurn()
        let next = h.chat.histories.count >= 2 ? h.chat.histories[1].last { $0.role == .user } : nil
        #expect(next != nil, "the turn after the stop never reached the model")
        #expect(next?.content.contains("<steer>") == false, "the turn after a stop was told it was a steer")
    }

    // The press lands while the stopped turn is still stuck, so it cuts that
    // same turn again; the stop still stands.
    @Test @MainActor func aPressAfterAStopOnTheSameStuckTurnStillLeavesNoNote() async {
        let rig = await stuckRig(deadline: { try? await Task.sleep(for: .seconds(30)) })
        let h = rig.h
        await h.session.hold()
        await pumpUntil("1") { h.watch.latest.state == .listening }
        await h.session.release()
        await rig.tools.waitUntilBlocked()
        h.synth.spoken = "Abro Safari."
        await h.session.interrupt()
        await h.session.hold()
        await pumpUntil("2") { h.watch.latest.state == .listening }
        h.transcriber.stoppedText = "abre Notes"
        await h.session.release()
        rig.tools.release()
        // The latest handle is the press's turn, which waited on the stopped
        // one: once it returns, both are done and no wall clock is involved.
        await h.session.awaitClassicTurn()

        let next = h.chat.histories.count >= 2 ? h.chat.histories[1].last { $0.role == .user } : nil
        #expect(next != nil, "the turn after the stop never reached the model")
        #expect(next?.content.contains("<steer>") == false, "a press undid the stop's missing note")
    }
}

/// An ear whose `stop` parks until the test finishes it: a turn cut while
/// "its ear was still finishing".
private final class GatedEar: Transcriber, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: CheckedContinuation<String, Never>?
    private var stopping = false
    private var watcher: CheckedContinuation<Void, Never>?
    private var finished = false
    private let text: String
    init(text: String) { self.text = text }

    func requestAuthorization() async -> Bool { true }
    var isAuthorized: Bool { true }
    func start(localeIdentifier: String) async throws {}
    func append(_ frame: MicFrame) async {}
    var partials: AsyncStream<String> { AsyncStream { $0.finish() } }
    var currentText: String { "" }

    func stop() async -> String {
        await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            let (now, wake): (Bool, CheckedContinuation<Void, Never>?) = lock.withLock {
                stopping = true
                defer { watcher = nil }
                if finished { return (true, watcher) }
                parked = c
                return (false, watcher)
            }
            wake?.resume()
            if now { c.resume(returning: text) }
        }
    }

    func waitUntilStopping() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock {
                if !stopping { watcher = c }
                return stopping
            }
            if ready { c.resume() }
        }
    }

    func finish() {
        let c: CheckedContinuation<String, Never>? = lock.withLock {
            finished = true
            defer { parked = nil }
            return parked
        }
        c?.resume(returning: text)
    }
}
