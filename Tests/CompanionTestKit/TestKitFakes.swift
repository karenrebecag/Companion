import Foundation

/// Suspends callers of `wait()` until `open()`; `entered` tells a test the
/// code under test reached the gate.
package final class TestGate: @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var didEnter = false

    package var entered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didEnter
    }

    package func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            didEnter = true
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    package func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// Un reloj manual: `sleep` se queda parado hasta que el test lo suelta.
package final class ManualSleeper: @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var armedDelays: [TimeInterval] = []
    package var pending: Int { lock.withLock { waiters.count } }

    /// How many waits of this length have registered. `SessionModel` starts its
    /// timers as tasks that hop off the main actor, so `send` returning does not
    /// mean the wait exists yet: `fire()` only wakes registered waiters, and a
    /// fire that runs first is lost for good. Wait on this before firing.
    package func armed(_ seconds: TimeInterval) -> Int { lock.withLock { armedDelays.filter { $0 == seconds }.count } }

    /// 4.9 is not a binary-exact delay. Callers that subtract elapsed time
    /// compare with a tolerance instead of `==`.
    package func armed(near seconds: TimeInterval, tolerance: TimeInterval) -> Int {
        lock.withLock { armedDelays.filter { abs($0 - seconds) <= tolerance }.count }
    }

    package var delays: [TimeInterval] { lock.withLock { armedDelays } }

    package func sleep(_ seconds: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            lock.withLock { armedDelays.append(seconds); waiters.append(continuation) }
        }
        try Task.checkCancellation()
    }

    package func fire() {
        let all = lock.withLock { let w = waiters; waiters = []; return w }
        for waiter in all { waiter.resume() }
    }
}

/// Controllable clock for `ChatViewModel`'s injected `now`: the rollover
/// window is measured against it, never wall time, so a test can cross the
/// idle limit without sleeping.
package final class RolloverClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    package init(_ start: Date) { self.current = start }
    package var date: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }
    package func advance(by seconds: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock()
    }
}
