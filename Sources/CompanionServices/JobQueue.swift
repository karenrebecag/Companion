import CompanionCore
import Foundation

/// Serial job runner: one specialist works at a time, each with a time budget
/// and a way to be cancelled. The budget races the work itself, so a job that
/// hangs without emitting a single event still dies on schedule.
public actor JobQueue {
    public enum QueueError: Error, Sendable, Equatable {
        case budgetExhausted
        case cancelled
        /// 16h-2 (L2): the user's own brake, told apart from a teardown or
        /// any other cancellation so only this one goes unannounced.
        case stoppedByUser
    }

    private let budget: TimeInterval
    private var busy = false
    /// Each waiter learns whether it may run (true) or was stopped while
    /// still in line (false).
    private var waiters: [(id: String, turn: CheckedContinuation<Bool, Never>)] = []
    private var currentJobID: String?
    private var currentWork: Task<JobResult, Error>?
    /// The user stopped the job running now: whatever it ends with is hers.
    private var stopRequested = false
    /// Counts the user's stops (review 16h-2 round 3). A job handed the turn
    /// wakes on its own time; if a stop landed since it got in line, it
    /// belongs to that stop even though the line was already empty.
    private var stopEpoch = 0
    /// 16q-1: jobs stopped one by one, by the id their owner minted. Kept
    /// even when the job is not in the queue yet (named and announced, not
    /// submitted) or was handed the turn a moment ago, so a stop can never
    /// be lost between two awaits.
    // HACK: capped list, oldest out. A job stopped this many stops ago that
    // is only now submitted would run. Upgrade trigger: the owner reports
    // "submitted" and the id is dropped when that job ends instead of by count.
    private var stoppedIDs: [String] = []
    private static let stoppedCap = 32
    /// Test seam: runs on the actor right after the turn is handed to the
    /// next waiter, the one instant a stop can land between "you're next"
    /// and that job starting.
    var afterHandover: (@Sendable (isolated JobQueue) -> Void)?

    func setAfterHandover(_ hook: @escaping @Sendable (isolated JobQueue) -> Void) {
        afterHandover = hook
    }

    public init(budget: TimeInterval = 15 * 60) {
        self.budget = budget
    }

    public var isBusy: Bool { busy }
    public var runningJobID: String? { currentJobID }
    /// Jobs waiting their turn behind the running one.
    public var waitingCount: Int { waiters.count }

    /// Awaits its turn, runs the executor under the budget, then lets the next
    /// job through. Events flow straight to the caller's continuation.
    public func submit(
        _ job: JobRequest,
        to executor: any Executor,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        let epoch = stopEpoch
        guard !stoppedIDs.contains(job.id) else { throw QueueError.stoppedByUser }
        guard await takeTurn(for: job.id) else { throw QueueError.stoppedByUser }
        guard epoch == stopEpoch, !stoppedIDs.contains(job.id) else {
            releaseTurn()
            throw QueueError.stoppedByUser
        }
        currentJobID = job.id
        stopRequested = false
        defer {
            currentJobID = nil
            currentWork = nil
            releaseTurn()
        }

        let work = Task { try await executor.run(job, events: events) }
        currentWork = work
        let result: JobResult
        do {
            result = try await race(work, budget: budget)
        } catch {
            work.cancel()
            // A job killed by the brake often answers with an error of its
            // own (a CLI's `is_error`); after the user's stop it is hers.
            if stopRequested { throw QueueError.stoppedByUser }
            if error is CancellationError { throw QueueError.cancelled }
            throw error
        }
        if stopRequested, result.isError { throw QueueError.stoppedByUser }
        return result
    }

    /// 16q-1: one job's own stop. The one in flight is cancelled and its end
    /// is the user's; one still in line leaves without ever running; the
    /// rest of the line keeps its place and the total brake is untouched.
    public func cancel(job id: String) {
        stoppedIDs.append(id)
        if stoppedIDs.count > Self.stoppedCap { stoppedIDs.removeFirst(stoppedIDs.count - Self.stoppedCap) }
        if currentJobID == id {
            stopRequested = true
            currentWork?.cancel()
        } else if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).turn.resume(returning: false)
        }
    }

    /// Cancels the job in flight; queued callers keep their place in line.
    public func cancelCurrent() {
        currentWork?.cancel()
    }

    /// The user's stop (16h-2 B1): the job in flight AND every job still in
    /// line. A waiter learns it was stopped and never runs, so nothing it
    /// would have done — steps, approvals — ever starts.
    public func cancelAll() {
        stopEpoch += 1
        let line = waiters
        waiters = []
        for waiter in line { waiter.turn.resume(returning: false) }
        if currentWork != nil { stopRequested = true }
        currentWork?.cancel()
    }

    // MARK: - Serialization

    private func takeTurn(for id: String) async -> Bool {
        guard busy else {
            busy = true
            return true
        }
        return await withCheckedContinuation { continuation in
            waiters.append((id: id, turn: continuation))
        }
    }

    private func releaseTurn() {
        guard !waiters.isEmpty else {
            busy = false
            return
        }
        // FIFO: the job that has waited longest goes next. The turn is
        // handed over still busy: clearing it first let a newcomer slip in
        // before the waiter woke, and two jobs ran at once.
        let next = waiters.removeFirst()
        next.turn.resume(returning: true)
        afterHandover?(self)
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
