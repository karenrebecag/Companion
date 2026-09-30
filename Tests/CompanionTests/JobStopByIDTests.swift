import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// 16q-1: a job's own stop. `JobQueue.cancel(job:)` stops one job by the id
// its owner minted, running or waiting, and leaves the rest of the line
// alone; `cancelAll` (the total brake) is untouched.

@Test @MainActor func jobStopByIDTests() async {
    await testStoppingTheRunningJobLetsTheNextOneRun()
    await testStoppingAWaitingJobLeavesTheRunningOne()
    await testAStopBeforeSubmitKeepsTheJobFromEverRunning()
    await testAStopDuringTheHandoverKeepsThatJobFromRunning()
    await testStoppingAnUnknownIdChangesNothing()
    await testTheTotalBrakeStillStopsTheWholeLine()
    await testJobRunnerRoutesTheJobsOwnStop()
    await testTheStoppedListKeepsThe32NewestAndDropsTheOldest()
}

/// Blocks every job until the test lets it end by id; records who started
/// and who was cancelled while running.
private final class HoldExecutor: Executor, @unchecked Sendable {
    let descriptor = ExecutorCatalog.native
    private let lock = NSLock()
    private var started: [String] = []
    private var cancelled: [String] = []
    private var open: Set<String> = []
    var startedIDs: [String] { lock.withLock { started } }
    var cancelledIDs: [String] { lock.withLock { cancelled } }
    func release(_ id: String) { lock.withLock { _ = open.insert(id) } }

    /// A job nobody releases or cancels ends by itself: a broken stop must
    /// fail the test, not park it for the queue's whole budget.
    struct Abandoned: Error {}
    static let deadline: Duration = .seconds(4)

    func run(
        _ job: JobRequest, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock { started.append(job.id) }
        let limit = ContinuousClock.now.advanced(by: Self.deadline)
        while !lock.withLock({ open.contains(job.id) }) {
            if ContinuousClock.now >= limit { throw Abandoned() }
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                lock.withLock { cancelled.append(job.id) }
                throw error
            }
        }
        return JobResult(output: "ok:\(job.id)", isError: false)
    }
}

private func request(_ id: String) -> JobRequest {
    JobRequest(id: id, goal: "objetivo", context: "")
}

@MainActor private func sink() -> AsyncStream<JobEvent>.Continuation {
    let (stream, continuation) = AsyncStream<JobEvent>.makeStream()
    Task { for await _ in stream {} }
    return continuation
}

/// Generous by default: the suite runs in parallel with tests that block real
/// threads, and a starved pool takes seconds to schedule a task. The stop
/// assertions pass a tighter deadline themselves.
@MainActor private func until(
    _ label: String, timeout: TimeInterval = 10, _ predicate: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await predicate()), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    expect(await predicate(), label)
}

private func outcome(_ task: Task<JobResult, Error>) async -> Result<JobResult, Error> {
    do { return .success(try await task.value) } catch { return .failure(error) }
}

private func boundedValue(_ task: Task<JobResult, Error>) async -> JobResult? {
    if case .success(let result)? = await bounded(task) { return result }
    return nil
}

/// Resumes its continuation once, whichever of the result and the deadline
/// gets there first.
private final class FirstOf: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<JobResult, Error>?, Never>?
    init(_ continuation: CheckedContinuation<Result<JobResult, Error>?, Never>) {
        self.continuation = continuation
    }
    func resume(_ value: Result<JobResult, Error>?) {
        let pending = lock.withLock { () -> CheckedContinuation<Result<JobResult, Error>?, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}

/// `outcome` with a deadline: a task that never ends yields nil, so a test
/// waiting on a stop that did nothing fails instead of hanging. A structured
/// race would not do: its group waits for the child parked on `task.value`.
private func bounded(
    _ task: Task<JobResult, Error>, seconds: Double = 3
) async -> Result<JobResult, Error>? {
    await withCheckedContinuation { continuation in
        let race = FirstOf(continuation)
        let waiter = Task { race.resume(await outcome(task)) }
        Task {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            race.resume(nil)
            waiter.cancel()
        }
    }
}

@MainActor func testStoppingTheRunningJobLetsTheNextOneRun() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    let first = Task { try await queue.submit(request("a"), to: executor, events: sink()) }
    let second = Task { try await queue.submit(request("b"), to: executor, events: sink()) }
    defer { first.cancel(); second.cancel() }
    await until("por id: a corre") { executor.startedIDs == ["a"] }
    await until("por id: b espera") { await queue.waitingCount == 1 }
    await queue.cancel(job: "a")
    // The executor is what proves the stop reached the running job: without
    // it a's task only ends when the budget does.
    await until("por id: a recibio la cancelacion", timeout: 2) { executor.cancelledIDs == ["a"] }
    if case .failure(let error)? = await bounded(first) {
        expectEq(error as? JobQueue.QueueError, .stoppedByUser, "por id: a termina como parado por la usuaria")
    } else {
        expect(false, "por id: a debia terminar parado")
    }
    await until("por id: b arranca despues") { executor.startedIDs == ["a", "b"] }
    executor.release("b")
    if case .success(let result)? = await bounded(second) {
        expectEq(result.output, "ok:b", "por id: b termina bien, nadie lo paro")
    } else {
        expect(false, "por id: b no debia fallar")
    }
}

@MainActor func testStoppingAWaitingJobLeavesTheRunningOne() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    let first = Task { try await queue.submit(request("a"), to: executor, events: sink()) }
    await until("espera: a corre") { executor.startedIDs == ["a"] }
    let second = Task { try await queue.submit(request("b"), to: executor, events: sink()) }
    await until("espera: b en fila") { await queue.waitingCount == 1 }
    await queue.cancel(job: "b")
    if case .failure(let error)? = await bounded(second) {
        expectEq(error as? JobQueue.QueueError, .stoppedByUser, "espera: b sabe que lo pararon")
    } else {
        expect(false, "espera: b debia terminar parado")
    }
    expectEq(await queue.waitingCount, 0, "espera: la fila queda vacia")
    expect(executor.cancelledIDs.isEmpty, "espera: a no recibio ninguna cancelacion")
    expectEq(executor.startedIDs, ["a"], "espera: b nunca arranco")
    executor.release("a")
    if case .success? = await bounded(first) {} else { expect(false, "espera: a termina bien") }
}

/// The job was named and announced but had not reached the queue yet.
@MainActor func testAStopBeforeSubmitKeepsTheJobFromEverRunning() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    await queue.cancel(job: "a")
    var failure: Error?
    do { _ = try await queue.submit(request("a"), to: executor, events: sink()) } catch { failure = error }
    expectEq(failure as? JobQueue.QueueError, .stoppedByUser, "antes de entrar: se para sin ejecutar")
    expect(executor.startedIDs.isEmpty, "antes de entrar: el ejecutor nunca lo vio")
    expect(!(await queue.isBusy), "antes de entrar: la fila queda libre")
}

/// The same hole `stopEpoch` closes for the total brake: the turn is handed
/// to B still busy, and a stop of B that lands before B is back on the actor
/// sees neither a waiter nor work in flight.
@MainActor func testAStopDuringTheHandoverKeepsThatJobFromRunning() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    await queue.setAfterHandover { queue in queue.cancel(job: "b") }
    let first = Task { try await queue.submit(request("a"), to: executor, events: sink()) }
    await until("traspaso: a corre") { executor.startedIDs == ["a"] }
    let second = Task { try await queue.submit(request("b"), to: executor, events: sink()) }
    await until("traspaso: b espera") { await queue.waitingCount == 1 }
    executor.release("a")
    _ = await bounded(first)
    if case .failure(let error)? = await bounded(second) {
        expectEq(error as? JobQueue.QueueError, .stoppedByUser, "traspaso: b sabe que lo pararon")
    } else {
        expect(false, "traspaso: b debia terminar parado")
    }
    expectEq(executor.startedIDs, ["a"], "traspaso: b nunca arranca")
    expect(!(await queue.isBusy), "traspaso: la fila queda libre")
}

@MainActor func testStoppingAnUnknownIdChangesNothing() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    let first = Task { try await queue.submit(request("a"), to: executor, events: sink()) }
    await until("desconocido: a corre") { executor.startedIDs == ["a"] }
    await queue.cancel(job: "fantasma")
    try? await Task.sleep(for: .milliseconds(30))
    expect(executor.cancelledIDs.isEmpty, "desconocido: nadie recibe cancelacion")
    executor.release("a")
    if case .success? = await bounded(first) {} else { expect(false, "desconocido: a termina bien") }
}

/// Mutation guard: the total brake keeps stopping running and waiting jobs.
@MainActor func testTheTotalBrakeStillStopsTheWholeLine() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    let first = Task { try await queue.submit(request("a"), to: executor, events: sink()) }
    await until("total: a corre") { executor.startedIDs == ["a"] }
    let second = Task { try await queue.submit(request("b"), to: executor, events: sink()) }
    await until("total: b espera") { await queue.waitingCount == 1 }
    await queue.cancelAll()
    _ = await bounded(first)
    if case .failure(let error)? = await bounded(second) {
        expectEq(error as? JobQueue.QueueError, .stoppedByUser, "total: b tambien parado")
    } else {
        expect(false, "total: b debia terminar parado")
    }
    expectEq(executor.startedIDs, ["a"], "total: b nunca arranco")
}

private struct OneExecutorProvider: ExecutorProviderProtocol {
    let executor: any Executor
    func selectExecutor(for _: Handoff) -> any Executor { executor }
}

/// The runner is what the UI reaches: it must submit under the caller's id
/// and stop by that same id.
@MainActor func testJobRunnerRoutesTheJobsOwnStop() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    let runner = JobRunner(
        executorProvider: OneExecutorProvider(executor: executor), queue: queue,
        approvals: Approvals(clock: RealtimeClock()))
    let mine = JobID("mio")
    let other = JobID("otro")
    let first = Task { try await runner.submit(Handoff(goal: "uno", context: ""), as: mine, events: sink()) }
    defer { first.cancel() }
    await until("runner: el primero corre con su id") { executor.startedIDs == ["mio"] }
    let second = Task { try await runner.submit(Handoff(goal: "dos", context: ""), as: other, events: sink()) }
    defer { second.cancel() }
    await until("runner: el segundo espera") { await queue.waitingCount == 1 }
    await runner.cancel(job: mine)
    await until("runner: el primero recibio la cancelacion", timeout: 2) { executor.cancelledIDs == ["mio"] }
    let stopped = await boundedValue(first)
    expectEq(stopped?.cancelled, true, "runner: el primero termina como parado por la usuaria")
    await until("runner: el segundo arranca despues") { executor.startedIDs == ["mio", "otro"] }
    executor.release("otro")
    let done = await boundedValue(second)
    expectEq(done?.isError, false, "runner: el segundo no fue tocado")
}

/// The list is capped: the 33rd stop keeps its place, the oldest leaves.
@MainActor func testTheStoppedListKeepsThe32NewestAndDropsTheOldest() async {
    let queue = JobQueue(budget: 10)
    let executor = HoldExecutor()
    for index in 0 ... 32 { await queue.cancel(job: "s\(index)") }
    var newest: Error?
    do { _ = try await queue.submit(request("s32"), to: executor, events: sink()) } catch { newest = error }
    expectEq(newest as? JobQueue.QueueError, .stoppedByUser, "tope: el 33 sigue parado")
    var another: Error?
    do { _ = try await queue.submit(request("s1"), to: executor, events: sink()) } catch { another = error }
    expectEq(another as? JobQueue.QueueError, .stoppedByUser, "tope: el 2 sigue dentro de los 32")
    executor.release("s0")
    let oldest = Task { try await queue.submit(request("s0"), to: executor, events: sink()) }
    await until("tope: el mas viejo se expulso y corre") { executor.startedIDs.contains("s0") }
    if case .success? = await bounded(oldest) {} else { expect(false, "tope: el mas viejo debia correr") }
}
