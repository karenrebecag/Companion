import CompanionCore
import Foundation


/// Coordinator that routes handoffs to executors via JobQueue.
/// Converts a Handoff into a JobRequest, selects an executor,
/// submits to the queue, and exposes events to the UI.
public struct JobRunner: Sendable, JobSubmitter {
    private let executorProvider: ExecutorProviderProtocol
    private let queue: JobQueue
    private let approvals: any ApprovalsProvider
    /// A closure, not a value: the failure the user reads has to follow the
    /// language they picked a minute ago, not the one at construction time.
    private let language: @Sendable () -> AppLanguage

    public init(
        executorProvider: ExecutorProviderProtocol,
        queue: JobQueue,
        approvals: any ApprovalsProvider,
        language: @escaping @Sendable () -> AppLanguage = { .en }
    ) {
        self.executorProvider = executorProvider
        self.queue = queue
        self.approvals = approvals
        self.language = language
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
            // El error interno va al log; a la usuaria le llega el porqué en
            // humano ("Job failed: processLaunchFailed" en el hilo fue real).
            Log.app("jobs: job failed (\(error))")
            return JobResult(
                output: Self.failureText(for: error, language()),
                isError: true)
        }
    }

    static func failureText(
        for error: Error, _ language: AppLanguage = .en
    ) -> String {
        let english = language == .en
        switch error {
        case JobQueue.QueueError.budgetExhausted:
            return english
                ? "The job took longer than allowed and was stopped."
                : "El encargo tardó más de la cuenta y se detuvo."
        case JobQueue.QueueError.cancelled, is CancellationError:
            return english ? "Job cancelled." : "Encargo cancelado."
        case ExecutorError.processLaunchFailed:
            return english
                ? "I could not start the specialist on this Mac."
                : "No pude arrancar el especialista en esta Mac."
        default:
            return english
                ? "The job could not be completed."
                : "El encargo no se pudo completar."
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
