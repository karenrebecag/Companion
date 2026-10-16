import CompanionCore
import Foundation

/// An `OwnerVerifying` whose answer the test sets. With `hold` on, `verify`
/// stays open until `release` or until its task is cancelled, which is how a
/// test keeps a dialog "on screen".
package final class FakeOwnerCheck: OwnerVerifying, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: OwnerCheck
    private var _canVerify = true
    private var _hold: Bool
    private var _calls: [String] = []
    private var _cancellations = 0
    private var waiter: CheckedContinuation<OwnerCheck, Never>?

    package init(result: OwnerCheck = .confirmed, hold: Bool = false) {
        _result = result
        _hold = hold
    }

    package var result: OwnerCheck {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    package var canVerifyNow: Bool {
        get { lock.withLock { _canVerify } }
        set { lock.withLock { _canVerify = newValue } }
    }
    /// The reasons passed to `verify`, in call order.
    package var calls: [String] { lock.withLock { _calls } }
    package var cancellations: Int { lock.withLock { _cancellations } }
    package var isWaiting: Bool { lock.withLock { waiter != nil } }

    package func canVerify() async -> Bool { canVerifyNow }

    package func verify(reason: String) async -> OwnerCheck {
        let held = lock.withLock { () -> Bool in
            _calls.append(reason)
            return _hold
        }
        guard held else { return result }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let late = lock.withLock { () -> OwnerCheck? in
                    if _cancellations > 0 { return .refused }
                    waiter = continuation
                    return nil
                }
                if let late { continuation.resume(returning: late) }
            }
        } onCancel: {
            let pending = lock.withLock { () -> CheckedContinuation<OwnerCheck, Never>? in
                _cancellations += 1
                defer { waiter = nil }
                return waiter
            }
            pending?.resume(returning: .refused)
        }
    }

    /// Answers the held `verify` with the programmed result.
    package func release() {
        let pending = lock.withLock { () -> CheckedContinuation<OwnerCheck, Never>? in
            defer { waiter = nil }
            return waiter
        }
        pending?.resume(returning: result)
    }
}
