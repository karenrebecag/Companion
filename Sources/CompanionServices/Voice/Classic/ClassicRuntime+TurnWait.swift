import CompanionCore
import Foundation
import Synchronization

/// Whoever settles first decides the wait; the loser's result is dropped.
private final class WaitLatch: Sendable {
    private let settled = Mutex(false)
    func claim() -> Bool {
        settled.withLock { done in
            defer { done = true }
            return !done
        }
    }
}

extension ClassicRuntime {
    /// Interruptions-by-cause R1: one deadline for every cause of a cut.
    static let defaultTurnWaitDeadline: @Sendable () async -> Void = {
        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            // Cancelled: the predecessor finished first; the race ignores it.
        }
    }

    /// Waits for the cut turn before this one, at most `turnWaitDeadline`.
    /// Returns true when the deadline won and the predecessor still runs.
    ///
    /// Two loose tasks race to resume one continuation, on purpose not
    /// structured (ADR 008): `await previous.value` is not interrupted by
    /// cancellation, so a `withTaskGroup` timeout would wait for it anyway
    /// and bound nothing. The predecessor is never cancelled or awaited
    /// here; its watcher simply outlives the race until it ends.
    func waitForPrevious(_ previous: Task<Void, Never>) async -> Bool {
        let deadline = turnWaitDeadline
        let latch = WaitLatch()
        return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let timer = Task {
                await deadline()
                if latch.claim() { done.resume(returning: true) }
            }
            Task {
                await previous.value
                if latch.claim() {
                    timer.cancel()
                    done.resume(returning: false)
                }
            }
        }
    }
}
