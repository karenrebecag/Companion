import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16h-2 (criteria 1 and 2) with fakes: the ack leaves before the work,
// the turn is free while the job runs, the job's end waits for the active
// turn, and stopping still brakes the job.

// One entry point, cases in sequence: the voice harness cases busy-wait on
// the main actor, and run in parallel they starve the suite's timing tests.
@Test @MainActor func backgroundJobRuntimeTests() async {
    await testTheAckIsQueuedBeforeTheDelegationStarts()
    await testTheModelsOwnLineIsTheAckAndNothingIsAdded()
    await testALeakIsNeverTheAck()
    await testTheRoutersDelegationAlsoAcknowledgesFirst()
    await testASlowToolIsAcknowledgedWhileItRuns()
    await testAFastToolSaysNoAck()
    await testTheVoiceIsFreeWhileTheJobRunsAndTheEndWaitsForTheTurn()
    await testTheEndOfAJobWaitsWhileTheUserHolds()
    await testASecondRequestIsAcknowledgedAndItsQueueIsSaid()
    await testStoppingTheBackgroundJobBrakesItAndSaysNoFailure()
    await testStopCancelsTheRunningJobAndEveryQueuedOne()
    await testATeardownIsNotTheUsersStop()
    await testAnErrorResultAfterTheStopCountsAsStopped()
    await testAPressDuringTheAckSilencesItAndKeepsTheJobFromStarting()
    await testAPressDuringTheRoutersAckKeepsTheJobFromStarting()
    await testARoundOfToolsReportsItsStateInsteadOfWritingIt()
    await testAStoppedSynthesizerDoesNotJamTheNextNotice()
    await testEscAtRestSilencesTheNoticeAndDropsTheWaitingOnes()
    await testAVoiceTheUserClosedSaysNoNotice()
    await testAVoiceInErrorDropsItsNotices()
    await testAStaleNoticeIsNeverSaid()
    await testASpokenYesNeverGrantsASheetFromBeforeTheTurn()
    await testASpokenYesNeedsTheSheetOnScreenLongEnough()
    await testASheetShownInThisHoldStillNeedsAClick()
}

// MARK: - fakes

/// One ordered record shared by every fake in a test: the order IS the claim.
final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var all: [String] { lock.withLock { items } }
    func add(_ item: String) { lock.withLock { items.append(item) } }
}

private final class LoggingSynth: SpeechSynthesizer, @unchecked Sendable {
    let log: OrderLog
    init(_ log: OrderLog) { self.log = log }
    let events = AsyncStream<SpeechEvent> { _ in }
    var speakingNow: String { get async { "" } }
    func begin() async {}
    func enqueue(_ sentence: String) async { log.add("say:\(sentence)") }
    func finish() async {}
    func stop() async {}
    func spokenSoFar() async -> String? { nil }
}

/// A job that runs until the test lets it end (or someone stops it).
final class GatedJob: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var opened = false
    private var _goals: [String] = []
    private var _cancelled = false
    private var _running = 0
    var onSubmit: (@Sendable () -> Void)?

    var goals: [String] { lock.withLock { _goals } }
    var cancelled: Bool { lock.withLock { _cancelled } }
    private var sink: AsyncStream<JobEvent>.Continuation?
    private var _resolutions: [Bool] = []
    var resolutions: [Bool] { lock.withLock { _resolutions } }

    func ask(_ request: ApprovalRequest) {
        let sink = lock.withLock { self.sink }
        sink?.yield(.approvalRequested(request))
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock {
            _goals.append(handoff.goal)
            _running += 1
            sink = events
        }
        onSubmit?()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                gates.append(continuation)
                lock.unlock()
            }
        }
        lock.withLock { _running -= 1 }
        events.finish()
        // What `JobRunner` reports for the user's brake.
        if cancelled { throw JobQueue.QueueError.stoppedByUser }
        return JobResult(output: "Encontré tres vuelos.", isError: false)
    }

    /// Lets only the job that has waited longest end.
    func openNext() {
        let first = lock.withLock { gates.isEmpty ? nil : gates.removeFirst() }
        first?.resume()
    }

    func open() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            opened = true
            defer { gates = [] }
            return gates
        }
        for gate in waiting { gate.resume() }
    }

    func cancel() async {
        lock.withLock { _cancelled = true }
        open()
    }

    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {
        lock.withLock { _resolutions.append(approved) }
    }
    var isBusy: Bool { get async { lock.withLock { _running > 0 } } }
}

/// A parent tool that runs until the test lets it end.
private final class HeldTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var finished = false
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
            } else {
                waiting = continuation
                lock.unlock()
            }
        }
        lock.withLock { finished = true }
        return ParentToolOutcome(ok: true, output: "Safari al frente", target: "Safari", tool: name)
    }
    func release() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            opened = true
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }
}

private let flights = Handoff(goal: "busca vuelos en Safari", context: "")

@MainActor private func classicTurn(
    _ rounds: [[ChatDelta]], log: OrderLog, heard: String = "búscalo en Safari"
) -> (ClassicRuntime, ScriptedThread) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = heard
    let chat = ScriptedChat()
    chat.rounds = rounds
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: LoggingSynth(log), chat: chat, thread: thread)
    runtime.onDelegate = { handoff in log.add("delegate:\(handoff.goal)") }
    runtime.markTimeline = { point in
        if point == .acknowledged { log.add("mark:ack") }
    }
    return (runtime, thread)
}

private func recordingFirstSentence(_ log: OrderLog) -> @Sendable (TurnEvent) async -> Void {
    { event in
        if event == .firstSentence { log.add("firstSentence") }
        if event == .replyCompleted { log.add("replyCompleted") }
    }
}

// MARK: - criterion 1: the ack before the work

@MainActor func testTheAckIsQueuedBeforeTheDelegationStarts() async {
    for language in [AppLanguage.es, .en] {
        let log = OrderLog()
        let (runtime, thread) = classicTurn([[.handoff(flights)]], log: log)
        await runtime.submit(config: Config(language: language), apply: recordingFirstSentence(log))
        let ack = Acknowledgement.delegating(language)
        expectEq(log.all, [
            "firstSentence", "mark:ack", "say:\(ack)", "delegate:busca vuelos en Safari", "replyCompleted",
        ], "acuse (\(language)): la voz arranca, se marca, se dice y DESPUÉS se delega")
        expect(thread.turns.contains { $0.role == .assistant && $0.content == ack },
               "acuse (\(language)): el hilo guarda lo que se dijo")
    }
}

@MainActor func testTheModelsOwnLineIsTheAckAndNothingIsAdded() async {
    let log = OrderLog()
    let (runtime, _) = classicTurn([[.text("Voy a buscarlo en Safari."), .handoff(flights)]], log: log)
    await runtime.submit(config: Config(language: .es), apply: recordingFirstSentence(log))
    expect(!log.all.contains("say:\(Acknowledgement.delegating(.es))"),
           "acuse: el modelo ya habló, no se añade otra frase (\(log.all))")
    let said = log.all.firstIndex(of: "say:Voy a buscarlo en Safari.")
    let delegated = log.all.firstIndex(of: "delegate:busca vuelos en Safari")
    expect(said != nil && delegated != nil && said! < delegated!,
           "acuse: la frase del modelo va antes de delegar (\(log.all))")
}

@MainActor func testALeakIsNeverTheAck() async {
    let log = OrderLog()
    let leak = "Acusa en una línea lo que dice."
    let (runtime, _) = classicTurn([[.text(leak), .handoff(flights)]], log: log)
    await runtime.submit(config: Config(language: .es), apply: recordingFirstSentence(log))
    expect(!log.all.contains { $0.contains("Acusa") }, "acuse: la instrucción interna no suena")
    expect(log.all.contains("say:\(Acknowledgement.delegating(.es))"),
           "acuse: lo filtrado no cuenta como dicho, así que sale nuestra frase (\(log.all))")
}

@MainActor func testTheRoutersDelegationAlsoAcknowledgesFirst() async {
    let log = OrderLog()
    let (runtime, _) = classicTurn([], log: log)
    runtime.decide = { _, _ in .delegate(flights) }
    await runtime.submit(config: Config(language: .es), apply: recordingFirstSentence(log))
    let ack = log.all.firstIndex(of: "say:\(Acknowledgement.delegating(.es))")
    let delegated = log.all.firstIndex(of: "delegate:busca vuelos en Safari")
    expect(ack != nil && delegated != nil && ack! < delegated!,
           "acuse: el router también dice su frase antes de delegar (\(log.all))")
    expect(log.all.contains("mark:ack"), "acuse: y se mide")
}

@MainActor func testASlowToolIsAcknowledgedWhileItRuns() async {
    let log = OrderLog()
    let see = ToolCallRef(id: "s1", name: "see", arguments: "{}")
    let (runtime, _) = classicTurn([[.toolCalls([see])], [.text("Veo Safari.")]], log: log)
    let tools = HeldTools()
    runtime.parentTools = tools
    runtime.slowToolWait = {}
    let ack = Acknowledgement.working(tool: "see", .es)
    let turn = Task { await runtime.submit(config: Config(language: .es), apply: recordingFirstSentence(log)) }
    await pumpUntilAsync("herramienta lenta: el acuse suena mientras corre") { log.all.contains("say:\(ack)") }
    expect(!tools.finished, "herramienta lenta: la herramienta sigue en curso")
    tools.release()
    await turn.value
    expectEq(log.all.filter { $0 == "say:\(ack)" }.count, 1, "herramienta lenta: una sola frase")
    let order = log.all.filter { $0.hasPrefix("say:") || $0 == "firstSentence" || $0 == "mark:ack" }
    expectEq(order, ["firstSentence", "mark:ack", "say:\(ack)", "say:Veo Safari."],
             "herramienta lenta: acuse, luego la respuesta")
}

@MainActor func testAFastToolSaysNoAck() async {
    let log = OrderLog()
    let open = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let (runtime, _) = classicTurn([[.toolCalls([open])], [.text("Abrí Safari.")]], log: log)
    let tools = HeldTools()
    tools.release()
    runtime.parentTools = tools
    runtime.slowToolWait = {
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
    }
    await runtime.submit(config: Config(language: .es), apply: recordingFirstSentence(log))
    expect(!log.all.contains { $0.hasPrefix("mark:ack") }, "herramienta rápida: sin acuse (\(log.all))")
    expect(log.all.contains("say:Abrí Safari."), "herramienta rápida: la respuesta normal")
}

// MARK: - criterion 2: the voice does not wait for the job

@MainActor private func delegatingHold(_ h: VoiceHarness, _ jobs: GatedJob, turns: Int) async {
    await h.session.hold()
    await pumpUntil("fondo: escuchando") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("fondo: el encargo arrancó") { jobs.goals.count == turns }
}

@MainActor private func endSpeech(_ h: VoiceHarness) async {
    h.synth.yield(.finished)
    await pumpUntil("fondo: la voz del turno terminó") { h.watch.latest.state == .idle }
}

@MainActor func testTheVoiceIsFreeWhileTheJobRunsAndTheEndWaitsForTheTurn() async {
    let jobs = GatedJob()
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    // The job records, in its own order log, what the voice had queued when
    // it started; the fake synthesizer's queue is lock-protected.
    let queueAtSubmit = OrderLog()
    let synth = h.synth
    jobs.onSubmit = { queueAtSubmit.add(synth.queue.joined(separator: "|")) }
    h.transcriber.stoppedText = "búscalo en Safari"
    h.chat.rounds = [[.handoff(flights)], [.text("Son las diez.")], [.text("Hay tres vuelos baratos.")]]
    await delegatingHold(h, jobs, turns: 1)
    let ack = Acknowledgement.delegating(.es)
    expectEq(queueAtSubmit.all.first, ack, "fondo: el acuse ya estaba en cola cuando arrancó el encargo")
    await endSpeech(h)
    expect(!jobs.cancelled, "fondo: el turno acabó y el encargo sigue")

    h.transcriber.stoppedText = "qué hora es"
    await h.session.hold()
    await pumpUntil("fondo: la usuaria vuelve a hablar") { h.watch.latest.state == .listening }
    expect(!jobs.cancelled, "fondo: el hold nuevo no mata el encargo")
    await h.session.release()
    await pumpUntil("fondo: el turno nuevo contesta") { h.synth.queue.contains("Son las diez.") }

    jobs.open()
    await pumpUntilAsync("fondo: el aviso de fin espera su hueco") {
        await h.session.parkedAnnouncements.count == 1
    }
    let done = Escalation.jobDoneSpoken(.es)
    expect(!h.synth.queue.contains(done), "fondo: el aviso no pisa el turno que habla")
    await endSpeech(h)
    await pumpUntil("fondo: el aviso suena al acabar el turno") { h.synth.queue.contains(done) }
    await pumpUntil("fondo: con su frase de resumen") { h.synth.queue.contains("Hay tres vuelos baratos.") }
    let reply = h.synth.queue.firstIndex(of: "Son las diez.") ?? .max
    let announced = h.synth.queue.firstIndex(of: done) ?? -1
    expect(reply < announced, "fondo: primero la respuesta de la usuaria, luego el aviso (\(h.synth.queue))")
}

@MainActor func testTheEndOfAJobWaitsWhileTheUserHolds() async {
    let jobs = GatedJob()
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    h.transcriber.stoppedText = "búscalo en Safari"
    h.chat.rounds = [[.handoff(flights)], [.text("Resumen.")]]
    await delegatingHold(h, jobs, turns: 1)
    await endSpeech(h)
    await h.session.hold()
    await pumpUntil("hold: escuchando") { h.watch.latest.state == .listening }
    jobs.open()
    await pumpUntilAsync("hold: el aviso queda en cola") { await h.session.parkedAnnouncements.count == 1 }
    expect(!h.synth.queue.contains(Escalation.jobDoneSpoken(.es)), "hold: no le habla encima a la usuaria")
    await h.session.discard()
    await pumpUntil("hold: al soltar sin turno, suena") {
        h.synth.queue.contains(Escalation.jobDoneSpoken(.es))
    }
}

@MainActor func testASecondRequestIsAcknowledgedAndItsQueueIsSaid() async {
    let jobs = GatedJob()
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    h.transcriber.stoppedText = "búscalo en Safari"
    h.chat.rounds = [[.handoff(flights)], [.handoff(Handoff(goal: "reserva hotel", context: ""))]]
    await delegatingHold(h, jobs, turns: 1)
    await endSpeech(h)
    h.transcriber.stoppedText = "y reserva hotel"
    await delegatingHold(h, jobs, turns: 2)
    let ack = Acknowledgement.delegating(.es)
    expectEq(h.synth.queue.filter { $0 == ack }.count, 2, "cola: el segundo pedido también se acusa")
    await pumpUntilAsync("cola: el aviso de cola espera al turno") {
        await h.session.parkedAnnouncements.count == 1
    }
    await endSpeech(h)
    await pumpUntil("cola: se dice que va en cola") {
        h.synth.queue.contains(Escalation.jobQueuedSpoken(.es))
    }
    expect(!jobs.cancelled, "cola: pedir otra cosa no para lo que corre")
    await jobs.cancel()
}

/// Records every session event and hands it to the model, in order.
private final class SessionEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SessionEvent] = []
    var all: [SessionEvent] { lock.withLock { items } }
    func add(_ event: SessionEvent) { lock.withLock { items.append(event) } }
}

@MainActor func testStoppingTheBackgroundJobBrakesItAndSaysNoFailure() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    let seen = SessionEventLog()
    Task {
        for await event in h.session.events {
            seen.add(event)
            await MainActor.run { _ = model.send(event) }
        }
    }
    h.transcriber.stoppedText = "búscalo en Safari"
    h.chat.rounds = [[.handoff(flights)], [.text("Resumen.")]]
    await delegatingHold(h, jobs, turns: 1)
    await endSpeech(h)
    await pumpUntil("parar: el encargo en la proyección") { model.projection.job != nil }
    expect(model.send(.stop).contains(.cancelJob), "parar: el freno de la isla sigue (9g)")
    await pumpUntil("parar: llega al encargo") { jobs.cancelled }
    // Positive first: the job's own end reached the session, and the thread
    // line that the bridge writes right before it would announce.
    await pumpUntil("parar: el fin del encargo llega a la sesión") {
        seen.all.contains { if case .jobFinished(false, _) = $0 { true } else { false } }
    }
    await pumpUntil("parar: el hilo lo registra") {
        h.thread.status.filter { $0.contains("busca vuelos en Safari") }.count >= 2
    }
    expect(!h.synth.queue.contains(Escalation.jobFailedSpoken(.es)),
           "parar: lo que la usuaria paró no se anuncia como fallo (\(h.synth.queue))")
    expectEq(await h.session.parkedAnnouncements.count, 0, "parar: nada queda en cola")
    expectEq(await h.session.droppedAnnouncements, 0, "parar: ni siquiera se intentó anunciar")
}

// MARK: - stop is one brake, and a whole one (B1, L2)

/// Runs until cancelled; then throws, or answers with an error result the
/// way a CLI reports `is_error` after being killed.
private final class HeldExecutor: Executor, @unchecked Sendable {
    let descriptor = ExecutorCatalog.native
    let answersAfterCancel: Bool
    private let lock = NSLock()
    private var goals: [String] = []
    var started: [String] { lock.withLock { goals } }
    init(answersAfterCancel: Bool = false) { self.answersAfterCancel = answersAfterCancel }

    func run(_ job: JobRequest, events: AsyncStream<JobEvent>.Continuation) async throws -> JobResult {
        lock.withLock { goals.append(job.goal) }
        events.yield(.stepStarted(tool: "Bash", summary: job.goal))
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            if answersAfterCancel { return JobResult(output: "killed", isError: true) }
            throw error
        }
        return JobResult(output: "ok", isError: false)
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [JobEvent] = []
    var all: [JobEvent] { lock.withLock { items } }
    func add(_ event: JobEvent) { lock.withLock { items.append(event) } }
}

private func runner(_ executor: any Executor, _ queue: JobQueue) -> JobRunner {
    JobRunner(executorProvider: DefaultExecutorProvider(nativeExecutor: executor),
              queue: queue, approvals: FakeApprovals())
}

private func collecting() -> (EventBox, AsyncStream<JobEvent>.Continuation) {
    let box = EventBox()
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    Task { for await event in stream { box.add(event) } }
    return (box, sink)
}

@MainActor func testStopCancelsTheRunningJobAndEveryQueuedOne() async {
    let executor = HeldExecutor()
    let queue = JobQueue(budget: 120)
    let jobs = runner(executor, queue)
    let (_, sinkA) = collecting()
    let (eventsB, sinkB) = collecting()
    let first = Task { try await jobs.submit(Handoff(goal: "A", context: ""), events: sinkA) }
    await pumpUntil("stop: A corre") { executor.started == ["A"] }
    let second = Task { try await jobs.submit(Handoff(goal: "B", context: ""), events: sinkB) }
    await pumpUntilAsync("stop: B espera en la cola") { await queue.waitingCount == 1 }
    await jobs.cancel()
    let a = await result(first)
    let b = await result(second)
    expectEq(a?.cancelled, true, "stop: el que corre queda parado por la usuaria")
    expectEq(b?.cancelled, true, "stop: el encolado también")
    expectEq(executor.started, ["A"], "stop: el encolado nunca ejecuta")
    let busy = await queue.isBusy
    expect(!busy, "stop: la cola queda libre")
    let spoke = eventsB.all.filter { if case .started = $0 { false } else { true } }
    expect(spoke.isEmpty, "stop: el encolado no emite pasos ni permisos (\(spoke))")
}

@MainActor func testATeardownIsNotTheUsersStop() async {
    let executor = HeldExecutor()
    let jobs = runner(executor, JobQueue(budget: 120))
    let (_, sink) = collecting()
    let task = Task { try await jobs.submit(Handoff(goal: "A", context: ""), events: sink) }
    await pumpUntil("desmontaje: corre") { executor.started == ["A"] }
    task.cancel()
    let outcome = await result(task)
    expectEq(outcome?.isError, true, "desmontaje: termina con error")
    expectEq(outcome?.cancelled, false, "desmontaje: no se confunde con el freno de la usuaria")
}

@MainActor func testAnErrorResultAfterTheStopCountsAsStopped() async {
    let executor = HeldExecutor(answersAfterCancel: true)
    let jobs = runner(executor, JobQueue(budget: 120))
    let (_, sink) = collecting()
    let task = Task { try await jobs.submit(Handoff(goal: "A", context: ""), events: sink) }
    await pumpUntil("error tras parar: corre") { executor.started == ["A"] }
    await jobs.cancel()
    let outcome = await result(task)
    expectEq(outcome?.cancelled, true, "error tras parar: un is_error tras el freno cuenta como parado")
}

private func result(_ task: Task<JobResult, Error>) async -> JobResult? {
    do { return try await task.value } catch { return nil }
}

// MARK: - a press over the ack (code review M1, L2)

/// The press lands at the ack's first sentence: the turn's task is cut there.
private let pressAtFirstSentence: @Sendable (TurnEvent) async -> Void = { event in
    if event == .firstSentence { withUnsafeCurrentTask { $0?.cancel() } }
}

@MainActor func testAPressDuringTheAckSilencesItAndKeepsTheJobFromStarting() async {
    let log = OrderLog()
    let (runtime, _) = classicTurn([[.handoff(flights)]], log: log)
    await Task { await runtime.submit(config: Config(language: .es), apply: pressAtFirstSentence) }.value
    expect(!log.all.contains { $0.hasPrefix("say:") }, "press: nada suena tras el press (\(log.all))")
    expect(!log.all.contains { $0.hasPrefix("delegate:") }, "press: el encargo no arranca")
}

@MainActor func testAPressDuringTheRoutersAckKeepsTheJobFromStarting() async {
    let log = OrderLog()
    let (runtime, _) = classicTurn([], log: log)
    runtime.decide = { _, _ in .delegate(flights) }
    await Task { await runtime.submit(config: Config(language: .es), apply: pressAtFirstSentence) }.value
    expect(!log.all.contains { $0.hasPrefix("delegate:") }, "router: el encargo no arranca tras el press (\(log.all))")
    expect(!log.all.contains { $0.hasPrefix("say:") }, "router: y su frase no suena")
}

// MARK: - a tool round reports its state (S3)

private struct CardTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        let pin = LocationsBlock.Location(name: "Café", lat: 19.4, lng: -99.1)
        return ParentToolOutcome(ok: true, output: "abierto", target: "Safari",
                                 card: Card(payload: .locations(LocationsBlock(locations: [pin])), source: .tool),
                                 tool: name)
    }
}

@MainActor func testARoundOfToolsReportsItsStateInsteadOfWritingIt() async {
    let (runtime, _) = classicTurn([], log: OrderLog())
    let open = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let round = await runtime.actRound(
        [open], said: "", heard: "abre Safari", using: CardTools(), language: .es, unverified: [])
    expectEq(round.effectLines, ["Abrí Safari."], "ronda: devuelve la línea del efecto")
    expect(round.sawCard, "ronda: y que hubo tarjeta")
    var mouth = TurnMouth(language: .es, recognizer: FakeRecognizer(), heard: "abre Safari")
    expect(mouth.effectLines.isEmpty && !mouth.cardThisTurn, "ronda: el turno no cambia hasta absorber")
    ClassicRuntime.absorb(round, into: &mouth)
    expectEq(mouth.effectLines, ["Abrí Safari."], "ronda: absorber lleva la línea al turno")
    expect(mouth.cardThisTurn, "ronda: y la tarjeta")
}

// MARK: - the notice's lifecycle (S1, S2, M3)

/// A hold that delegated and ended: the job runs, the voice rests.
@MainActor private func restingWithJob(
    _ jobs: GatedJob, rounds: [[ChatDelta]] = [[.handoff(flights)], [.text("Resumen.")]],
    session: SessionModel? = nil
) async -> VoiceHarness {
    let h = makeVoiceHarness(jobs: jobs, language: .es, session: session)
    h.transcriber.stoppedText = "búscalo en Safari"
    h.chat.rounds = rounds
    await delegatingHold(h, jobs, turns: 1)
    await endSpeech(h)
    return h
}

@MainActor private func noticeSounding(_ h: VoiceHarness, _ jobs: GatedJob) async {
    jobs.open()
    await pumpUntil("aviso: suena") { h.synth.queue.contains(Escalation.jobDoneSpoken(.es)) }
}

@MainActor func testAStoppedSynthesizerDoesNotJamTheNextNotice() async {
    let jobs = GatedJob()
    let h = await restingWithJob(jobs, rounds: [
        [.handoff(flights)], [.handoff(Handoff(goal: "reserva hotel", context: ""))],
        [.text("Uno.")], [.text("Dos.")],
    ])
    h.transcriber.stoppedText = "y reserva hotel"
    await delegatingHold(h, jobs, turns: 2)
    await endSpeech(h)
    // The second request's "queued" notice sounds first; its audio ends.
    await pumpUntil("S1: el aviso de cola") { h.synth.queue.contains(Escalation.jobQueuedSpoken(.es)) }
    h.synth.yield(.finished)
    await pumpUntilAsync("S1: el aviso de cola terminó") { await !h.session.announcementUnlogged }
    let done = Escalation.jobDoneSpoken(.es)
    jobs.openNext()
    await pumpUntil("S1: el fin de A suena") { h.synth.queue.filter { $0 == done }.count == 1 }
    // Something of ours stops the synthesizer mid-notice: no `.finished` comes.
    await h.session.interrupt()
    expect(h.synth.stopped, "S1: el aviso se calla")
    jobs.openNext()
    await pumpUntil("S1: sin pulsar nada, el fin de B sí suena") {
        h.synth.queue.filter { $0 == done }.count == 2
    }
}

@MainActor func testEscAtRestSilencesTheNoticeAndDropsTheWaitingOnes() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: nil, approvals: nil)
    let h = await restingWithJob(jobs, session: model)
    await noticeSounding(h, jobs)
    await pumpUntil("S2: la proyección ve el aviso") { model.projection.announcing }
    await h.session.interrupt()
    expect(h.synth.stopped, "S2: Esc en reposo calla el resumen")
    expectEq(await h.session.parkedAnnouncements.count, 0, "S2: y no queda nada esperando")
    await pumpUntil("S2: la proyección ve que calló") { !model.projection.announcing }
}

@MainActor func testAVoiceTheUserClosedSaysNoNotice() async {
    let jobs = GatedJob()
    let h = await restingWithJob(jobs)
    await h.session.hangUp()
    jobs.open()
    await pumpUntilAsync("M3: el aviso se descarta") { await h.session.droppedAnnouncements == 1 }
    expectEq(await h.session.parkedAnnouncements.count, 0, "M3: y no se queda esperando")
    expect(!h.synth.queue.contains(Escalation.jobDoneSpoken(.es)), "M3: con la voz cerrada por la usuaria, no suena")
}

@MainActor func testAVoiceInErrorDropsItsNotices() async {
    let jobs = GatedJob()
    let h = await restingWithJob(jobs)
    h.mic.granted = false
    await h.session.hold()
    await pumpUntil("M3: la voz en error") { h.watch.latest.state == .error }
    jobs.open()
    await pumpUntilAsync("M3: el aviso se descarta") { await h.session.droppedAnnouncements == 1 }
    expectEq(await h.session.parkedAnnouncements.count, 0, "M3: nada queda en cola")
    expect(!h.synth.queue.contains(Escalation.jobDoneSpoken(.es)), "M3: con la voz en error, no suena")
}

@MainActor func testAStaleNoticeIsNeverSaid() async {
    let jobs = GatedJob()
    let h = await restingWithJob(jobs, rounds: [[.handoff(flights)], [.text("Son las diez.")], [.text("Resumen.")]])
    h.transcriber.stoppedText = "qué hora es"
    await h.session.hold()
    await pumpUntil("M3: hold") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("M3: el turno contesta") { h.synth.queue.contains("Son las diez.") }
    jobs.open()
    await pumpUntilAsync("M3: el aviso espera") { await h.session.parkedAnnouncements.count == 1 }
    h.clock.now += AnnouncementGap.maxAge + 1
    await endSpeech(h)
    await pumpUntilAsync("M3: el aviso caducado se descarta") { await h.session.droppedAnnouncements == 1 }
    expect(!h.synth.queue.contains(Escalation.jobDoneSpoken(.es)), "M3: un aviso viejo no suena")
}

// MARK: - a spoken yes and the sheet (security M1)

private let sheetRequest = ApprovalRequest(
    requestId: "r1", toolName: "Bash", summary: "rm -rf build", inputJSON: "{}")
private let saysYes: [ChatDelta] = [
    .toolCalls([ToolCallRef(id: "y1", name: "resolve_approval", arguments: #"{"approved":true}"#)]),
]

/// The job asks while the voice rests, or once `pressFirst` opened a turn.
@MainActor private func askedSheet(pressFirst: Bool) async -> (VoiceHarness, GatedJob) {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = await restingWithJob(jobs, rounds: [[.handoff(flights)], saysYes], session: model)
    h.transcriber.stoppedText = "sí, dale"
    if pressFirst {
        await h.session.hold()
        await pumpUntil("M1: hold") { h.watch.latest.state == .listening }
    }
    jobs.ask(sheetRequest)
    await pumpUntilAsync("M1: la hoja llega a la sesión") { await h.session.pendingApproval != nil }
    await pumpUntil("M1: y a la proyección") { model.projection.approval != nil }
    return (h, jobs)
}

@MainActor private func answer(_ h: VoiceHarness, pressed: Bool) async {
    if !pressed {
        await h.session.hold()
        await pumpUntil("M1: hold") { h.watch.latest.state == .listening }
    }
    await h.session.release()
    await h.session.awaitClassicTurn()
}

@MainActor func testASpokenYesNeverGrantsASheetFromBeforeTheTurn() async {
    let (h, jobs) = await askedSheet(pressFirst: false)
    h.clock.now += 5
    await answer(h, pressed: false)
    expect(jobs.resolutions.isEmpty, "M1: un sí de un turno nuevo no aprueba la hoja de antes")
    expect(h.synth.queue.contains(Escalation.approvalNeedsClickSpoken(.es)),
           "M1: la voz dice que la hoja espera un clic (\(h.synth.queue))")
}

@MainActor func testASpokenYesNeedsTheSheetOnScreenLongEnough() async {
    let (h, jobs) = await askedSheet(pressFirst: true)
    h.clock.now += ApprovalClickGuard.dwell / 2
    await answer(h, pressed: true)
    expect(jobs.resolutions.isEmpty, "M1: una hoja recién aparecida no se aprueba de voz")
    expect(h.synth.queue.contains(Escalation.approvalNeedsClickSpoken(.es)), "M1: y se dice por qué")
}

/// Review 16h-2 round 3 (HIGH): a sheet that appeared with the key down was
/// never said by the voice, so even read for the dwell it takes the click.
@MainActor func testASheetShownInThisHoldStillNeedsAClick() async {
    let (h, jobs) = await askedSheet(pressFirst: true)
    h.clock.now += ApprovalClickGuard.dwell + 0.1
    await answer(h, pressed: true)
    expect(jobs.resolutions.isEmpty, "M1: la hoja aparecida en este hold no se aprueba de voz")
    expect(h.synth.queue.contains(Escalation.approvalNeedsClickSpoken(.es)), "M1: la voz pide el clic")
    await jobs.cancel()
}
