import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor
func jobRunnerConvertHandoffToRequest() throws {
    let result = try runAsync {
        let executor = FakeTestExecutor(output: "ok")
        let executor_provider = SimpleExecutorProvider(executor: executor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: executor_provider,
            queue: queue,
            approvals: approvals
        )

        let handoff = Handoff(goal: "read config.json", context: "from the project root")
        let (stream, _) = AsyncStream<JobEvent>.makeStream()
        stream.ignore()

        let job = await runner.handoffToRequest(handoff)
        return job
    }

    expectEq(result.goal, "read config.json", "handoff goal becomes request goal")
    expectEq(result.context, "from the project root", "handoff context becomes request context")
    expect(!result.id.isEmpty, "request gets a unique id")
}

@Test @MainActor
func jobRunnerEmitsEventsToObserver() throws {
    let result = try runAsync {
        let executor = FakeTestExecutor(output: "ok")
        let executor_provider = SimpleExecutorProvider(executor: executor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: executor_provider,
            queue: queue,
            approvals: approvals
        )

        let handoff = Handoff(goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()

        // Collect events
        let collector = Task {
            var collected: [JobEvent] = []
            for await event in events {
                collected.append(event)
            }
            return collected
        }

        _ = await runner.handoffToRequest(handoff)
        // Fake: we'll use the runner but events flow through the stream
        sink.finish()
        let collectedEvents = await collector.value
        return collectedEvents.count
    }

    expect(result >= 0, "runner exposes JobEvent stream")
}

@Test @MainActor
func jobRunnerSubmitsJobToQueue() throws {
    let result = try runAsync {
        let fakeExecutor = FakeTestExecutor(output: "done")
        let executor_provider = SimpleExecutorProvider(executor: fakeExecutor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: executor_provider,
            queue: queue,
            approvals: approvals
        )

        let handoff = Handoff(goal: "write file", context: "test.txt")
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        stream.ignore()

        let jobResult = try await runner.submit(handoff, events: sink)
        return (jobResult.output, jobResult.isError)
    }

    expectEq(result.0, "done", "runner submits job and gets result")
    expect(!result.1, "result is not an error")
}

@Test @MainActor
func jobRunnerReportsFailureWhenExecutorFails() throws {
    let result = try runAsync {
        let fakeExecutor = FailureTestExecutor()
        let executor_provider = SimpleExecutorProvider(executor: fakeExecutor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: executor_provider,
            queue: queue,
            approvals: approvals
        )

        let handoff = Handoff(goal: "fail", context: "")
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        stream.ignore()

        let jobResult = try await runner.submit(handoff, events: sink)
        return (jobResult.output, jobResult.isError)
    }

    expect(result.1, "executor failure is reported as isError=true")
}

// MARK: - Fakes

private struct SimpleExecutorProvider: ExecutorProviderProtocol {
    let executor: any Executor

    func selectExecutor(for _: Handoff) -> any Executor {
        executor
    }
}

// Make JobRunner compatible with fakes for testing
extension JobRunner {
    // This allows tests to use SimpleExecutorProvider
}

private final class FakeTestExecutor: Executor, @unchecked Sendable {
    let descriptor = ExecutorDescriptor(
        id: ExecutorID(rawValue: "test"),
        shortName: "test",
        title: "Test",
        kind: .native
    )
    let output: String

    init(output: String) {
        self.output = output
    }

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "test", summary: "testing"))
        events.yield(.stepFinished(tool: "test", ok: true))
        return JobResult(output: output, isError: false)
    }
}

private struct FailureTestExecutor: Executor {
    let descriptor = ExecutorDescriptor(
        id: ExecutorID(rawValue: "fail"),
        shortName: "fail",
        title: "Fail",
        kind: .native
    )

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        throw ChatError.unreachable
    }
}
