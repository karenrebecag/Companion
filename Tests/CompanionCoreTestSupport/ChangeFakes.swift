import CompanionCore
import Foundation

/// An observer that sees what the test scripts: records every begin, settle
/// and cancel so a test can prove the watch opened before the action and
/// that a failed action never waited.
package final class FakeChangeWatcher: AXChangeWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var _report: ChangeReport
    private var _begun: [Int32] = []
    private var _settled = 0
    private var _cancelled = 0
    private var _order: [String] = []
    private var _timings: [SettleTiming] = []
    package var report: ChangeReport {
        get { lock.withLock { _report } }
        set { lock.withLock { _report = newValue } }
    }
    package var begun: [Int32] { lock.withLock { _begun } }
    package var settled: Int { lock.withLock { _settled } }
    package var cancelled: Int { lock.withLock { _cancelled } }
    package var order: [String] { lock.withLock { _order } }
    package var timings: [SettleTiming] { lock.withLock { _timings } }

    package init(report: ChangeReport = ChangeReport(changes: [], watching: true)) {
        _report = report
    }

    package func begin(pid: Int32) -> any AXChangeWatch {
        lock.withLock {
            _begun.append(pid)
            _order.append("begin")
        }
        return Watch(owner: self)
    }

    package func note(_ event: String) { lock.withLock { _order.append(event) } }

    private struct Watch: AXChangeWatch {
        let owner: FakeChangeWatcher
        func settle(_ timing: SettleTiming) async -> ChangeReport {
            owner.lock.withLock {
                owner._settled += 1
                owner._timings.append(timing)
                owner._order.append("settle")
                return owner._report
            }
        }
        func cancel() { owner.lock.withLock { owner._cancelled += 1 } }
    }
}
