import Foundation

/// Gap 1. Incredible counts Screen Recording only when it is granted AND a
/// capture was verified; the switch on with captures failing is its own
/// dead end, so it gets its own state instead of reading as granted.
package enum ScreenRecordingStatus: String, Sendable, Equatable {
    case notGranted, grantedUnverified, verified, stale
}

/// Holds the verified state the sight reads before every capture. It only
/// probes, never asks: the one path that asks is the user's tap or the
/// welcome's refocus re-request.
package final class ScreenRecordingGate: @unchecked Sendable {
    private let checker: any ScreenRecordingChecking
    private let log: @Sendable (String) -> Void
    private let reprobeInterval: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var current: ScreenRecordingStatus
    /// Bumped on every result, so a probe that started before a newer one
    /// landed cannot overwrite it.
    private var epoch = 0
    private var lastProbe: Date?
    private var lost: (@Sendable () -> Void)?

    package init(
        checker: any ScreenRecordingChecking,
        reprobeInterval: TimeInterval = 30,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.checker = checker
        self.reprobeInterval = reprobeInterval
        self.now = now
        self.log = log
        current = checker.isGranted() ? .grantedUnverified : .notGranted
    }

    /// Set after construction: the session that shows the card is built
    /// after the sight that owns this gate.
    package func onLost(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { lost = handler }
    }

    package var status: ScreenRecordingStatus { lock.withLock { current } }
    package var sightReady: Bool { status == .verified }

    /// The state with the preflight read live: a capture the preflight
    /// refuses never reaches the gate, so a revoke would otherwise keep
    /// reading as whatever the last probe saw.
    package var grantedStatus: ScreenRecordingStatus {
        checker.isGranted() ? status : .notGranted
    }

    @discardableResult
    package func verify() async -> ScreenRecordingStatus {
        let started = lock.withLock { () -> Int in
            lastProbe = now()
            return epoch
        }
        // Without the grant the probe itself could raise the system prompt.
        guard checker.isGranted() else { return apply(.notGranted, since: started) }
        let captured = await checker.verify()
        return apply(captured ? .verified : nil, since: started)
    }

    /// The sight's way back from off: the next capture probes again, but at
    /// most once per interval, so a turn never pays for a probe each time.
    @discardableResult
    package func reprobeIfDue() async -> ScreenRecordingStatus {
        let due = lock.withLock { () -> Bool in
            guard current != .verified else { return false }
            guard let lastProbe else { return true }
            return now().timeIntervalSince(lastProbe) >= reprobeInterval
        }
        return due ? await verify() : status
    }

    /// A capture that failed may be a lost grant or a passing hiccup; the
    /// probe tells them apart, so one bad frame does not turn sight off.
    @discardableResult
    package func captureFailed() async -> ScreenRecordingStatus {
        await verify()
    }

    package func captureSucceeded() {
        apply(.verified, since: nil)
    }

    /// `nil` means the probe failed with the grant on: stale if sight had
    /// worked, unverified if it never had.
    @discardableResult
    private func apply(_ result: ScreenRecordingStatus?, since started: Int?) -> ScreenRecordingStatus {
        let (previous, next) = lock.withLock { () -> (ScreenRecordingStatus, ScreenRecordingStatus) in
            if let started, started != epoch { return (current, current) }
            let previous = current
            let lost = previous == .verified || previous == .stale
            current = result ?? (lost ? .stale : .grantedUnverified)
            epoch += 1
            return (previous, current)
        }
        if previous != next { log("screen-recording: \(previous.rawValue) -> \(next.rawValue)") }
        // Only a grant that worked and stopped is a loss; one that never
        // worked is the welcome's to explain.
        if previous == .verified, next != .verified, let lost = lock.withLock({ self.lost }) { lost() }
        return next
    }
}
