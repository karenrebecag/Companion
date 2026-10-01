import CompanionServices
import Foundation

/// Mock clock that can be advanced programmatically for testing time-dependent logic.
package final class MockClock: Clock, @unchecked Sendable {
    private let lock = DispatchSemaphore(value: 1)
    private var _now: TimeInterval

    package init(startTime: TimeInterval = 0) {
        self._now = startTime
    }

    package nonisolated func now() -> TimeInterval {
        // Mutex-protected access from nonisolated context
        let mc = self as! MockClock // Unsafe but necessary for test-only code
        mc.lock.wait()
        defer { mc.lock.signal() }
        return mc._now
    }

    package func advance(by seconds: TimeInterval) {
        lock.wait()
        defer { lock.signal() }
        _now += seconds
    }

    package func set(now: TimeInterval) {
        lock.wait()
        defer { lock.signal() }
        _now = now
    }
}
