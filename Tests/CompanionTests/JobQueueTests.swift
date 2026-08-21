import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func jobQueueTests() async {
    await testResultReachesCaller()
    await testSerialOneAtATime()
    await testSilentJobStillTimesOut()
    await testCancelCurrentStopsTheJob()
    await testFailureDoesNotJamTheQueue()
    await testEventsReachTheCaller()
}

/// The whole point of delegating: the answer must come back.
@MainActor func testResultReachesCaller() async {
    let queue = JobQueue(budget: 5)
    let executor = ScriptedExecutor(output: "listo")
    let (events, sink) = AsyncStream<JobEvent>.makeStream()
    events.ignore()
    let result = try? await queue.submit(job("1"), to: executor, events: sink)
    expectEq(result?.output, "listo", "cola: el resultado del especialista vuelve")
    expectEq(result?.isError, false, "cola: sin error")
}

@MainActor func testSerialOneAtATime() async {
    let queue = JobQueue(budget: 5)
    let executor = ScriptedExecutor(output: "ok", delay: 0.15)
    async let first: JobResult? = try? await queue.submit(
        job("1"), to: executor, events: sinkIgnoring())
    try? await Task.sleep(for: .milliseconds(40))
    let busyDuringFirst = await queue.isBusy
    async let second: JobResult? = try? await queue.submit(
        job("2"), to: executor, events: sinkIgnoring())
    _ = await (first, second)
    expect(busyDuringFirst, "cola: marca ocupado mientras corre")
    expectEq(executor.maxConcurrent, 1, "cola: nunca dos especialistas a la vez")
    expectEq(executor.started, ["1", "2"], "cola: respeta el orden de llegada")
}

/// The bug this replaces: the old queue only checked the clock when an event
/// arrived, so a hung executor waited forever.
@MainActor func testSilentJobStillTimesOut() async {
    let queue = JobQueue(budget: 0.05)
    let executor = SilentExecutor()
    var failure: Error?
    do {
        _ = try await queue.submit(job("1"), to: executor, events: sinkIgnoring())
    } catch { failure = error }
    expectEq(failure as? JobQueue.QueueError, .budgetExhausted,
             "cola: un trabajo mudo también agota el presupuesto")
    await waitUntil("cola: el trabajo se cancela al agotarse") {
        executor.wasCancelled
    }
}

@MainActor func testCancelCurrentStopsTheJob() async {
    let queue = JobQueue(budget: 10)
    let executor = SilentExecutor()
    async let attempt: JobResult? = try? await queue.submit(
        job("1"), to: executor, events: sinkIgnoring())
    try? await Task.sleep(for: .milliseconds(50))
    await queue.cancelCurrent()
    let result = await attempt
    expect(result == nil, "cola: cancelar corta el trabajo en curso")
    await waitUntil("cola: el ejecutor recibe la cancelación") {
        executor.wasCancelled
    }
}

@MainActor func testFailureDoesNotJamTheQueue() async {
    let queue = JobQueue(budget: 5)
    let failing = FailingExecutor()
    _ = try? await queue.submit(job("1"), to: failing, events: sinkIgnoring())
    let healthy = ScriptedExecutor(output: "segundo")
    let result = try? await queue.submit(job("2"), to: healthy, events: sinkIgnoring())
    expectEq(result?.output, "segundo", "cola: un fallo no atora la fila")
    let busy = await queue.isBusy
    expect(!busy, "cola: queda libre tras terminar")
}

@MainActor func testEventsReachTheCaller() async {
    let queue = JobQueue(budget: 5)
    let executor = ScriptedExecutor(output: "ok", emits: [
        .stepStarted(tool: "read_file", summary: "leyendo"),
        .stepFinished(tool: "read_file", ok: true),
    ])
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    let seen = EventBox()
    let collector = Task { for await event in stream { seen.append(event) } }
    _ = try? await queue.submit(job("1"), to: executor, events: sink)
    sink.finish()
    _ = await collector.value
    expectEq(seen.count, 2, "cola: los pasos llegan a quien observa")
}

/// Cancellation lands on another thread; poll instead of asserting instantly.
@MainActor private func waitUntil(
    _ label: String, timeout: TimeInterval = 2, _ predicate: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    expect(predicate(), label)
}

// MARK: - Fakes

private func job(_ id: String) -> JobRequest {
    JobRequest(id: id, goal: "objetivo", context: "")
}

@MainActor private func sinkIgnoring() -> AsyncStream<JobEvent>.Continuation {
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    stream.ignore()
    return sink
}

extension AsyncStream where Element == JobEvent {
    /// Drains without observing: some tests only care about the result.
    func ignore() {
        let stream = self
        Task { for await _ in stream {} }
    }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [JobEvent] = []
    func append(_ event: JobEvent) { lock.withLock { events.append(event) } }
    var count: Int { lock.withLock { events.count } }
}

private final class ScriptedExecutor: Executor, @unchecked Sendable {
    let descriptor = ExecutorCatalog.native
    private let output: String
    private let delay: TimeInterval
    private let emits: [JobEvent]
    private let lock = NSLock()
    private var live = 0
    private(set) var maxConcurrent = 0
    private(set) var started: [String] = []

    init(output: String, delay: TimeInterval = 0, emits: [JobEvent] = []) {
        self.output = output
        self.delay = delay
        self.emits = emits
    }

    func run(
        _ job: JobRequest, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock {
            live += 1
            maxConcurrent = max(maxConcurrent, live)
            started.append(job.id)
        }
        defer { lock.withLock { live -= 1 } }
        for event in emits { events.yield(event) }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        return JobResult(output: output, isError: false)
    }
}

/// Never emits, never returns on its own: the shape that used to hang forever.
private final class SilentExecutor: Executor, @unchecked Sendable {
    let descriptor = ExecutorCatalog.native
    private let lock = NSLock()
    private var cancelled = false
    var wasCancelled: Bool { lock.withLock { cancelled } }

    func run(
        _ job: JobRequest, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            lock.withLock { cancelled = true }
            throw error
        }
        return JobResult(output: "", isError: false)
    }
}

private struct FailingExecutor: Executor {
    let descriptor = ExecutorCatalog.native
    func run(
        _ job: JobRequest, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        throw ChatError.unreachable
    }
}
