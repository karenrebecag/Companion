import CompanionCore
import Foundation

/// Every process group Companion started and has not seen die.
///
/// Two jobs. One is a ceiling: without it each job piles on shells until the
/// Mac crawls, and a limit nobody enforces is documentation. The other is the
/// sweep at quit — a net, never a guarantee: a crash or a Force Quit gives the
/// app no chance to run anything, and macOS has no `PR_SET_PDEATHSIG` to fall
/// back on. What survives a crash survives; that limit is real and stated.
package final class ProcessRegistry: @unchecked Sendable {
    /// Generous enough for parallel jobs, low enough that a runaway loop hits
    /// a wall instead of the scheduler.
    package static let defaultCap = 8

    package static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var live: Set<pid_t> = []
    private var pending = 0
    private let cap: Int

    package init(cap: Int = ProcessRegistry.defaultCap) {
        self.cap = cap
    }

    package var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return live.count
    }

    /// Reserve BEFORE spawning: a pid only exists once the spawn returns, so
    /// checking the ceiling against the live set alone would let two racing
    /// callers both pass it. The reservation is what makes the cap real.
    func reserve() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard live.count + pending < cap else { return false }
        pending += 1
        return true
    }

    func commit(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        pending -= 1
        live.insert(pid)
    }

    /// The spawn failed: give the slot back or the ceiling leaks downward
    /// until nothing can run at all.
    func release() {
        lock.lock()
        defer { lock.unlock() }
        pending -= 1
    }

    func forget(_ pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        live.remove(pid)
    }

    /// Kills every group still standing. Called from the app delegate on quit.
    package func terminateAll() {
        let doomed = drain()
        for pid in doomed {
            ProcessGroupRunner.terminateGroup(pid)
        }
    }

    private func drain() -> [pid_t] {
        lock.lock()
        defer { lock.unlock() }
        let all = Array(live)
        live.removeAll()
        return all
    }
}
