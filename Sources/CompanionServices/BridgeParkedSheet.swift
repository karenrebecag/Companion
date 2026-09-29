import CompanionCore
import Foundation

/// The one approval sheet a bridge connection can have on screen at a time
/// (the session-open sheet or a per-call sheet; they never overlap, `handle`
/// is awaited serially). Lock-guarded and synchronous so the guard can park
/// it before the sheet is shown, and so `stop()`, the EOF watcher and a new
/// connection can all withdraw it without racing the answer.
final class BridgeParkedSheet: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ApprovalRequest?
    private var withdrawn: Set<String> = []

    func park(_ request: ApprovalRequest) {
        lock.withLock { current = request }
    }

    /// Takes the sheet to withdraw it and remembers that WE did, so the
    /// resulting denial is not mistaken for the user's.
    func takeForWithdrawal() -> ApprovalRequest? {
        lock.withLock {
            guard let request = current else { return nil }
            current = nil
            withdrawn.insert(request.requestId)
            return request
        }
    }

    /// Call once the sheet's answer is back. True when it was withdrawn
    /// rather than answered by the user or the deadline.
    func settle(_ request: ApprovalRequest) -> Bool {
        lock.withLock {
            if current?.requestId == request.requestId { current = nil }
            return withdrawn.remove(request.requestId) != nil
        }
    }

    /// `settle` for a sheet whose request the caller never saw (the per-call
    /// gate builds it inside `check`). Sheets are serial, so "any withdrawn"
    /// is "this one".
    func settleCurrent() -> Bool {
        lock.withLock {
            current = nil
            let wasWithdrawn = !withdrawn.isEmpty
            withdrawn.removeAll()
            return wasWithdrawn
        }
    }
}
