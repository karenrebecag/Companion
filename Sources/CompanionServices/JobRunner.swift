import CompanionCore
import Foundation


/// Coordinator that routes handoffs to executors via JobQueue.
/// Converts a Handoff into a JobRequest, selects an executor,
/// submits to the queue, and exposes events to the UI.
public struct JobRunner: Sendable, JobSubmitter {
    private let executorProvider: ExecutorProviderProtocol
    private let queue: JobQueue
    private let approvals: any ApprovalsProvider

    public init(
        executorProvider: ExecutorProviderProtocol,
        queue: JobQueue,
        approvals: any ApprovalsProvider
    ) {
        self.executorProvider = executorProvider
        self.queue = queue
        self.approvals = approvals
    }

    /// Convert a Handoff into a JobRequest with a unique ID.
    public func handoffToRequest(_ handoff: Handoff) async -> JobRequest {
        JobRequest(
            id: UUID().uuidString,
            goal: handoff.goal,
            context: handoff.context
        )
    }

    /// Submit a handoff for execution: select executor, queue the job,
    /// return the result.
    public func submit(
        _ handoff: Handoff,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        let job = await handoffToRequest(handoff)
        let executor = executorProvider.selectExecutor(for: handoff)
        do {
            return try await queue.submit(job, to: executor, events: events)
        } catch {
            return JobResult(output: "Job failed: \(error)", isError: true)
        }
    }

    /// Cancel the job currently running.
    public func resolveApproval(requestId: String, approved: Bool) async {
        _ = await approvals.resolve(requestId: requestId, approved: approved)
    }

    public func cancel() async {
        await queue.cancelCurrent()
    }

    /// Query if the queue is busy.
    public var isBusy: Bool {
        get async {
            await queue.isBusy
        }
    }
}

/// Abstraction for selecting an executor based on a Handoff.
public protocol ExecutorProviderProtocol: Sendable {
    func selectExecutor(for handoff: Handoff) -> any Executor
}

/// Default implementation: always selects the native executor.
public struct DefaultExecutorProvider: ExecutorProviderProtocol {
    private let nativeExecutor: any Executor

    public init(nativeExecutor: any Executor) {
        self.nativeExecutor = nativeExecutor
    }

    public func selectExecutor(for _: Handoff) -> any Executor {
        nativeExecutor
    }
}
