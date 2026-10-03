import CoreGraphics
import Foundation

/// Whether the login session is showing the lock screen. Read before acting
/// and again after, so a lock that lands mid-action is reported as an
/// unknown outcome rather than a success nobody saw.
package enum SessionLock {
    package static func isLocked() -> Bool {
        guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return info["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
