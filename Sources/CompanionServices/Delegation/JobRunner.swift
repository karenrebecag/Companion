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

    /// Convert a Handoff into a JobRequest with a unique ID. `id` is the one
    /// its owner minted (16q-1): the queue stops a job by it.
    public func handoffToRequest(_ handoff: Handoff, id: JobID = .mint()) async -> JobRequest {
        JobRequest(
            id: id.raw,
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
        try await submit(handoff, as: .mint(), events: events)
    }

    /// Same, under the id its owner named, so `cancel(job:)` can find it.
    public func submit(
        _ handoff: Handoff,
        as id: JobID,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        let job = await handoffToRequest(handoff, id: id)
        events.yield(.started(goal: handoff.goal))
        let executor = executorProvider.selectExecutor(for: handoff)
        do {
            return try await queue.submit(job, to: executor, events: events)
        } catch {
            // El error interno va al log; a la usuaria le llega el porqué en
            // humano ("Job failed: processLaunchFailed" en el hilo fue real).
            Log.app("jobs: job failed (\(error))")
            return JobResult(
                output: Self.failureText(for: error, language()),
                isError: true, cancelled: Self.isCancellation(error))
        }
    }

    /// The user's stop, and only hers (L2): a teardown or a task
    /// cancellation is a failure the voice may still report.
    static func isCancellation(_ error: Error) -> Bool {
        (error as? JobQueue.QueueError) == .stoppedByUser
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
        case JobQueue.QueueError.stoppedByUser:
            return english ? "Stopped." : "Encargo detenido."
        case JobQueue.QueueError.cancelled, is CancellationError:
            return english ? "Job cancelled." : "Encargo cancelado."
        case ExecutorError.emptyResult:
            return english
                ? "The specialist finished without reporting anything."
                : "El especialista terminó sin reportar nada."
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

    public func resolveApproval(requestId: String, approved: Bool) async {
        await resolveApproval(requestId: requestId, approved: approved, remember: false)
    }

    public func resolveApproval(requestId: String, approved: Bool, remember: Bool) async {
        _ = await approvals.resolve(requestId: requestId, approved: approved, remember: remember)
    }

    /// One job's own stop (16q-1): the rest of the line keeps its place.
    public func cancel(job id: JobID) async {
        await queue.cancel(job: id.raw)
    }

    /// Every caller of this is the user's brake (the island, the menu, the
    /// sheet's refusal, a spoken "para"): running and queued jobs alike.
    public func cancel() async {
        await queue.cancelAll()
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
