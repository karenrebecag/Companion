import CompanionCore
import Foundation

/// Serial job runner: one specialist works at a time, each with a time budget
/// and a way to be cancelled. The budget races the work itself, so a job that
/// hangs without emitting a single event still dies on schedule.
public actor JobQueue {
    public enum QueueError: Error, Sendable, Equatable {
        case budgetExhausted
        case cancelled
    }

    private let budget: TimeInterval
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var currentJobID: String?
    private var currentWork: Task<JobResult, Error>?

    public init(budget: TimeInterval = 15 * 60) {
        self.budget = budget
    }

    public var isBusy: Bool { busy }
    public var runningJobID: String? { currentJobID }

    /// Awaits its turn, runs the executor under the budget, then lets the next
    /// job through. Events flow straight to the caller's continuation.
    public func submit(
        _ job: JobRequest,
        to executor: any Executor,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        await takeTurn()
        currentJobID = job.id
        defer {
            currentJobID = nil
            currentWork = nil
            releaseTurn()
        }

        let work = Task { try await executor.run(job, events: events) }
        currentWork = work
        do {
            return try await race(work, budget: budget)
        } catch is CancellationError {
            work.cancel()
            throw QueueError.cancelled
        } catch let error as QueueError {
            work.cancel()
            throw error
        }
    }

    /// Cancels the job in flight; queued callers keep their place in line.
    public func cancelCurrent() {
        currentWork?.cancel()
    }

    // MARK: - Serialization

    private func takeTurn() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        busy = true
    }

    private func releaseTurn() {
        busy = false
        guard !waiters.isEmpty else { return }
        // FIFO: the job that has waited longest goes next.
        let next = waiters.removeFirst()
        next.resume()
    }

    // MARK: - Budget

    /// Races the work against the budget. A group is used instead of checking
    /// the clock on each event: a silent executor must also time out.
    private func race(
        _ work: Task<JobResult, Error>, budget: TimeInterval
    ) async throws -> JobResult {
        try await withThrowingTaskGroup(of: JobResult.self) { group in
            group.addTask { try await work.value }
            group.addTask {
                try await Task.sleep(for: .seconds(budget))
                throw QueueError.budgetExhausted
            }
            // Cancelling the group only cancels the tasks IN it; the work
            // task was created outside, so it must be cancelled by hand or a
            // timed-out executor keeps running to completion.
            defer {
                group.cancelAll()
                work.cancel()
            }
            guard let first = try await group.next() else {
                throw QueueError.cancelled
            }
            return first
        }
    }
}
