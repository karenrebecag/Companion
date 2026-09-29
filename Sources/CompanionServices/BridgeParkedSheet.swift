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
    private var currentOwner = 0
    /// Withdrawn request id -> the connection (epoch) that raised it, so a
    /// late continuation of a gone connection settles only its own.
    private var withdrawn: [String: Int] = [:]
    private var limit = BridgeSheetLimit()
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// False when the sheet-shown limit is spent: the caller must not show
    /// the sheet. Counted here, at the one place every sheet passes through.
    func park(_ request: ApprovalRequest, owner: Int) -> Bool {
        lock.withLock {
            guard limit.admit(now: now()) else { return false }
            current = request
            currentOwner = owner
            return true
        }
    }

    /// Takes the sheet to withdraw it and remembers that WE did, so the
    /// resulting denial is not mistaken for the user's.
    func takeForWithdrawal() -> ApprovalRequest? {
        lock.withLock {
            guard let request = current else { return nil }
            current = nil
            withdrawn[request.requestId] = currentOwner
            return request
        }
    }

    /// Call once the sheet's answer is back. True when it was withdrawn
    /// rather than answered by the user or the deadline.
    func settle(_ request: ApprovalRequest) -> Bool {
        lock.withLock {
            if current?.requestId == request.requestId { current = nil }
            return withdrawn.removeValue(forKey: request.requestId) != nil
        }
    }

    /// `settle` for a sheet whose request the caller never saw (the per-call
    /// gate builds it inside `check`). Scoped to `owner`: after a connection
    /// replaced this one, the shared slot may already hold the NEW
    /// connection's sheet, and this late call must not wipe it or consume a
    /// withdrawal that is not its own.
    func settleCurrent(owner: Int) -> Bool {
        lock.withLock {
            if currentOwner == owner { current = nil }
            let mine = withdrawn.filter { $0.value == owner }.keys
            mine.forEach { withdrawn.removeValue(forKey: $0) }
            return !mine.isEmpty
        }
    }
}
