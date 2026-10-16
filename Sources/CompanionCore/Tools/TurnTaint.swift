import Foundation

/// Whether this turn has put something of the user's outside the work folder in
/// front of the model. One instance is shared by every lane that can send
/// something out of the Mac (the parent's open_url, the browser tools, a
/// delegated job), so the exit gate has a single memory.
package final class TurnTaint: @unchecked Sendable {
    private let lock = NSLock()
    private var tainted: Bool

    package init(seed: Bool = false) {
        tainted = seed
    }

    package var isTainted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tainted
    }

    package func mark() {
        lock.lock()
        defer { lock.unlock() }
        tainted = true
    }

    package func reset() {
        lock.lock()
        defer { lock.unlock() }
        tainted = false
    }
}
