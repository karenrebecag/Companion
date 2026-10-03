import CompanionCore
import Foundation

/// An observer that sees what the test scripts: records every begin, settle
/// and cancel so a test can prove the watch opened before the action and
/// that a failed action never waited.
package final class FakeChangeWatcher: AXChangeWatching, @unchecked Sendable {
    private let lock = NSLock()
    package var report: ChangeReport
    package private(set) var begun: [Int32] = []
    package private(set) var settled = 0
    package private(set) var cancelled = 0
    package private(set) var order: [String] = []
    package private(set) var timings: [SettleTiming] = []

    package init(report: ChangeReport = ChangeReport(changes: [], watching: true)) {
        self.report = report
    }

    package func begin(pid: Int32) -> any AXChangeWatch {
        lock.withLock {
            begun.append(pid)
            order.append("begin")
        }
        return Watch(owner: self)
    }

    package func note(_ event: String) { lock.withLock { order.append(event) } }

    private struct Watch: AXChangeWatch {
        let owner: FakeChangeWatcher
        func settle(_ timing: SettleTiming) async -> ChangeReport {
            owner.lock.withLock {
                owner.settled += 1
                owner.timings.append(timing)
                owner.order.append("settle")
            }
            return owner.report
        }
        func cancel() { owner.lock.withLock { owner.cancelled += 1 } }
    }
}
