import Foundation

/// Which listen owns the classic mic and ear, and the ear's stop still in
/// flight. `ClassicRuntime`'s async methods run off the session actor, so
/// `requestListen`, `stopIO` and a turn's `stopEar` reach this state from
/// different threads (code review 2026-09-24, found by the sanitizer).
final class ClassicEarOwnership: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var stopping: Task<String, Never>?

    /// A new listen takes the mic and ear; returns its generation.
    func claim() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    var pendingStop: Task<String, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return stopping
    }

    /// Queues `stop` behind the stop already in flight, so waiting on the
    /// newest one covers them all.
    func queueStop(_ stop: @escaping @Sendable () async -> String) -> Task<String, Never> {
        lock.lock()
        defer { lock.unlock() }
        let previous = stopping
        let next = Task {
            _ = await previous?.value
            return await stop()
        }
        stopping = next
        return next
    }
}
