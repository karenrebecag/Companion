import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Production data race (TSan, classic-runtime-submit-speak brief): the shapes
// VoiceSession creates, each in its own unstructured task with no ordering
// between them. TSan is the oracle for the race itself; CI does not run it
// yet, so every test here also asserts what a lost or leaked update would
// break in plain behavior (what was said, how many steer notes rode).

// MARK: - fakes: none of them orders the tasks that use them

/// Records what was enqueued behind its own lock, so the record can never be
/// the thing that orders two turns on the runtime's state.
private final class RecordingSynth: SpeechSynthesizer, @unchecked Sendable {
    private let lock = NSLock()
    private var enqueued: [String] = []
    var lines: [String] { lock.withLock { enqueued } }
    var events: AsyncStream<SpeechEvent> { AsyncStream { $0.finish() } }
    func begin() async {}
    func enqueue(_ sentence: String) async { lock.withLock { enqueued.append(sentence) } }
    func finish() async {}
    func stop() async {}
    /// A cut turn threads this as its partial reply.
    func spokenSoFar() async -> String? { "Uno aquí." }
    var speakingNow: String { "" }
}

/// A fixed one-turn history: concurrent turns each rewrite their own copy of
/// it, so a turn never reads the user turn another one appended.
private final class FixedThread: ConversationPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var assistant: [String] = []
    private var statuses: [String] = []
    var assistantTurns: [String] { lock.withLock { assistant } }
    var statusLines: [String] { lock.withLock { statuses } }
    func historyTurns() async -> [Turn] { [Turn(role: .user, content: "-")] }
    func memoryTurns() async -> [Turn] { [] }
    func appendUser(_ text: String) async {}
    func appendAssistant(_ text: String) async { lock.withLock { assistant.append(text) } }
    func appendStatus(_ text: String) async { lock.withLock { statuses.append(text) } }
    func showStream(_ text: String) async {}
    func finishStream() async {}
}

/// Opens once; everyone waiting, and everyone who comes later, passes.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let pass = lock.withLock {
                if !isOpen { waiters.append(continuation) }
                return isOpen
            }
            if pass { continuation.resume() }
        }
    }

    func open() {
        let released = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        for waiter in released { waiter.resume() }
    }
}

/// A chat that parks a turn mid-stream when the plan says so.
private final class RaceChat: ChatProvider, @unchecked Sendable {
    struct Step {
        var before: [ChatDelta] = []
        var gate: Gate?
        var after: [ChatDelta] = []
    }

    private let lock = NSLock()
    private var seen: [[Turn]] = []
    private let plan: @Sendable (_ call: Int, _ history: [Turn]) -> Step
    init(plan: @escaping @Sendable (_ call: Int, _ history: [Turn]) -> Step) { self.plan = plan }

    var histories: [[Turn]] { lock.withLock { seen } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let index = lock.withLock {
            seen.append(history)
            return seen.count - 1
        }
        let step = plan(index, history)
        return AsyncThrowingStream { continuation in
            Task {
                for delta in step.before { continuation.yield(delta) }
                if let gate = step.gate { await gate.wait() }
                for delta in step.after { continuation.yield(delta) }
                continuation.finish()
            }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}

    /// Chat calls whose rendered request carried a `<steer>` note.
    var steerNotes: Int {
        histories.filter { $0.last?.content.contains("<steer>") == true }.count
    }
}

/// Opens an app by the name in its arguments, so two turns can tell apart.
private struct NamedTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        let object = try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]
        let app = object?["name"] as? String ?? "?"
        return ParentToolOutcome(ok: true, output: "opened", target: app, tool: name)
    }
}

private struct Rig {
    let runtime: ClassicRuntime
    let synth: RecordingSynth
    let thread: FixedThread
    let chat: RaceChat
}

private let fourSentences = "Uno aquí. Dos aquí. Tres aquí. Cuatro aquí."
private let said = "Acusa en una línea: "

private func rig(tools: (any ParentToolExecuting)? = nil, plan: @escaping @Sendable (Int, [Turn]) -> RaceChat.Step) -> Rig {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "restaurantes cercanos"
    let synth = RecordingSynth()
    let thread = FixedThread()
    let chat = RaceChat(plan: plan)
    let runtime = ClassicRuntime(transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.languageRecognizer = FakeRecognizer()
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice))
    runtime.parentTools = tools
    return Rig(runtime: runtime, synth: synth, thread: thread, chat: chat)
}

private func waitUntil(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0 ..< 2500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

private func submit(_ runtime: ClassicRuntime) -> Task<Void, Never> {
    Task.detached { await runtime.submit(config: Config(language: .es)) { _ in } }
}

private func openApp(_ name: String, id: String) -> ChatDelta {
    .toolCalls([ToolCallRef(id: id, name: "open_app", arguments: #"{"name":"\#(name)"}"#)])
}

private func announcement(hasCard: Bool) -> JobAnnouncement {
    JobAnnouncement(goal: "restaurantes", outcome: .done(result: "Hay tres."), language: .es, hasCard: hasCard)
}

// MARK: - announce against a turn

@Suite struct ClassicRuntimeRace {
    // Loop counts: RED evidence in docs/research/classic-runtime-submit-speak.md
    // is 9 TSan warnings at 50 iterations here and at 20 below; fewer
    // iterations stopped surfacing the race reliably.
    @Test func aNoticeAndATurnRunApart() async {
        for _ in 0 ..< 50 {
            let r = rig { _, _ in .init(after: [.text(fourSentences)]) }
            let notice = Task.detached { await r.runtime.announce(announcement(hasCard: true)) }
            let turn = submit(r.runtime)
            await notice.value
            await turn.value
            let spoken = r.synth.lines.joined(separator: " ")
            #expect(spoken.contains("Cuatro aquí."), "the turn's reply was cut short: \(spoken)")
            #expect(r.synth.lines.contains(announcement(hasCard: true).spokenLine), "the notice was lost: \(spoken)")
        }
    }

    @Test func aCardOnANoticeDoesNotShortenATurnInFlight() async {
        let gate = Gate()
        // Call 1 is the notice's own summary, which must not wait on the turn.
        let r = rig { call, _ in
            call == 0 ? .init(gate: gate, after: [.text(fourSentences)]) : .init(after: [.text("Hay tres.")])
        }
        let turn = submit(r.runtime)
        #expect(await waitUntil { !r.chat.histories.isEmpty })
        await r.runtime.announce(announcement(hasCard: true))
        gate.open()
        await turn.value
        let spoken = r.synth.lines.joined(separator: " ")
        #expect(spoken.contains("Cuatro aquí."), "the notice's card leaked into the turn: \(spoken)")
    }

    // MARK: - a cut turn against the next one

    @Test func aCutTurnAndTheNextRunApart() async {
        for _ in 0 ..< 20 {
            let gate = Gate()
            let r = rig { call, _ in
                call == 0 ? .init(before: [.text("Uno aquí. ")], gate: gate, after: [.text("Dos aquí. Tres aquí.")])
                    : .init(after: [.text("Hola.")])
            }
            let old = submit(r.runtime)
            #expect(await waitUntil { r.synth.lines.contains("Uno aquí.") })
            old.cancel()
            let next = submit(r.runtime)
            gate.open()
            await old.value
            await next.value
            #expect(r.thread.assistantTurns.contains("Uno aquí."), "the old turn never reached cutTurn")
            // The next turn may read the flag before or after the cut sets it:
            // the note rode once, or is still pending; never twice, never lost.
            let pending = r.runtime.steerPending ? 1 : 0
            #expect(r.chat.steerNotes + pending == 1, "notes=\(r.chat.steerNotes) pending=\(pending)")
        }
    }

    @Test func aCutTurnGivesTheNextTurnExactlyOneSteerNote() async {
        let gate = Gate()
        let r = rig { call, _ in
            call == 0 ? .init(before: [.text("Uno aquí. ")], gate: gate, after: [.text("Dos aquí.")])
                : .init(after: [.text("Hola.")])
        }
        let old = submit(r.runtime)
        #expect(await waitUntil { r.synth.lines.contains("Uno aquí.") })
        old.cancel()
        gate.open()
        await old.value
        #expect(r.thread.assistantTurns.contains("Uno aquí."), "the old turn never reached cutTurn")
        #expect(r.runtime.steerPending)
        await submit(r.runtime).value
        await submit(r.runtime).value
        #expect(r.chat.steerNotes == 1, "the note must ride one turn, not none or both")
        #expect(!r.runtime.steerPending)
    }

    // MARK: - the exactly-once helpers under contention

    @Test func manySubmitsConsumeOneSteerNoteBetweenThem() async {
        let r = rig { _, _ in .init(after: [.text("Hola.")]) }
        r.runtime.steerPending = true
        let start = Gate()
        let turns = (0 ..< 8).map { _ in
            Task.detached {
                await start.wait()
                await r.runtime.submit(config: Config(language: .es)) { _ in }
            }
        }
        start.open()
        for turn in turns { await turn.value }
        #expect(r.chat.histories.count == 8)
        #expect(r.chat.steerNotes == 1, "exactly one turn takes the note")
        #expect(!r.runtime.steerPending)
    }

    @Test func manySubmitsUseTheLeftoverWordsOnce() async {
        let r = rig { _, _ in .init(after: [.text("Hola.")]) }
        r.runtime.leftoverHeard = "palabras guardadas"
        let start = Gate()
        let turns = (0 ..< 8).map { _ in
            Task.detached {
                await start.wait()
                await r.runtime.submit(config: Config(language: .es)) { _ in }
            }
        }
        start.open()
        for turn in turns { await turn.value }
        let usingThem = r.chat.histories.filter { $0.last?.content.contains("palabras guardadas") == true }
        #expect(usingThem.count == 1, "exactly one turn answers for the kept words")
        #expect(r.runtime.leftoverHeard == nil)
    }

    @Test func cancellingThePressedContextCancelsItOnceAndClearsIt() async {
        let r = rig { _, _ in .init() }
        let pressed = Task<TurnContext?, Never> {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(1)) }
            return nil
        }
        r.runtime.pressedContext = pressed
        r.runtime.cancelPressedContext()
        #expect(pressed.isCancelled)
        #expect(r.runtime.pressedContext == nil)
        r.runtime.cancelPressedContext()
        #expect(r.runtime.pressedContext == nil)
        _ = await pressed.value
    }

    // MARK: - one turn's state stays its own

    @Test func anEffectLineIsNotRepeatedByALaterTurn() async {
        // Held on the runtime before, this was reset at turn start; it now has
        // nowhere to outlive a turn, and this pins that.
        let r = rig(tools: NamedTools()) { call, history in
            switch call {
            case 0: .init(after: [openApp("Safari", id: "A")])
            case 1: .init(after: [.text(said + "abrí Safari.")])
            default: .init(after: [.text(said + "listo.")])
            }
        }
        await submit(r.runtime).value
        await submit(r.runtime).value
        #expect(r.synth.lines.filter { $0 == "Abrí Safari." }.count == 1, "\(r.synth.lines)")
    }

    @Test func overlappingToolTurnsEachSayOnlyTheirOwnEffect() async {
        let roundTwo = Gate()
        let r = rig(tools: NamedTools()) { call, history in
            if history.contains(where: { $0.toolCallID == "A" }) {
                return .init(gate: roundTwo, after: [.text(said + "abrí Safari.")])
            }
            if history.contains(where: { $0.toolCallID == "B" }) {
                return .init(gate: roundTwo, after: [.text(said + "abrí Notes.")])
            }
            return .init(after: [openApp(call == 0 ? "Safari" : "Notes", id: call == 0 ? "A" : "B")])
        }
        let first = submit(r.runtime)
        #expect(await waitUntil { !r.chat.histories.isEmpty })
        let second = submit(r.runtime)
        // Both rounds of tools have run before either turn ends.
        #expect(await waitUntil { r.chat.histories.count == 4 })
        roundTwo.open()
        await first.value
        await second.value
        #expect(r.synth.lines.filter { $0 == "Abrí Safari." }.count == 1, "\(r.synth.lines)")
        #expect(r.synth.lines.filter { $0 == "Abrí Notes." }.count == 1, "\(r.synth.lines)")
    }
}
