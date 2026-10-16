import CompanionCore
import Foundation

/// Puente QA D1: the second switch under "Prestar las manos". It lives in
/// memory on purpose, not in `UserDefaults`: a grant that widens what an outside
/// agent can do must not survive the process that the person saw it turned on in.
/// Posts on every real change so the App layer can close the bridge session and
/// the shim redoes its hello with the new tool list.
package enum QAScopePreference {
    nonisolated private static let state = Flag()

    /// On only while the hands are lent: turning that off takes QA with it
    /// (`HandsLendingPreference`), and this reads both so an order of events
    /// can never leave QA on over closed hands.
    nonisolated package static var enabled: Bool {
        state.value && HandsLendingPreference.enabled
    }

    /// Turning it on needs the hands lent and an owner check that can be shown
    /// (Touch ID or the password). Turning it off is always allowed. Returns
    /// whether the switch ended up on, so a caller can say why it did not.
    @discardableResult
    nonisolated package static func set(_ on: Bool, handsLent: Bool, canVerify: Bool) -> Bool {
        let next = on && handsLent && canVerify
        guard state.swap(next) != next else { return next }
        NotificationCenter.default.post(name: .companionQAScopeDidChange, object: nil)
        return next
    }

    nonisolated package static func disable() {
        guard state.swap(false) else { return }
        NotificationCenter.default.post(name: .companionQAScopeDidChange, object: nil)
    }
}

private nonisolated final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var current = false

    nonisolated var value: Bool { lock.withLock { current } }

    /// Stores `next` and returns what was there before.
    nonisolated func swap(_ next: Bool) -> Bool {
        lock.withLock {
            defer { current = next }
            return current
        }
    }
}
