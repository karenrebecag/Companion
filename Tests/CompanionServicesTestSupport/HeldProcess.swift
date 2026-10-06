import CompanionCore
import Foundation

/// Launches a process that stays silent until the test releases it, so an
/// executor's session write can be made to land after a history clear.
package final class HoldLauncher: ProcessLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var launches: [[String]] = []
    package let handle: HoldHandle

    /// What the process prints once released, one line per read, then EOF.
    package init(lines: [String] = ["listo"]) {
        handle = HoldHandle(lines: lines)
    }

    package var launchedArguments: [[String]] { lock.withLock { launches } }

    package func launch(
        executable: String, arguments: [String], cwd: String?
    ) async -> (any ProcessHandle)? {
        let pending: CheckedContinuation<Void, Never>? = lock.withLock {
            didStart = true
            launches.append(arguments)
            let pending = started
            started = nil
            return pending
        }
        pending?.resume()
        return handle
    }

    package func waitUntilLaunched() async {
        let already = lock.withLock { didStart }
        if already { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if didStart { return true }
                started = cont
                return false
            }
            if resumeNow { cont.resume() }
        }
    }

    package func release() { handle.release() }
}

package final class HoldHandle: ProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let lines: [String]
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false
    private var reads = 0

    init(lines: [String]) { self.lines = lines }

    package func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            let pending = waiter
            waiter = nil
            return pending
        }
        pending?.resume()
    }

    package func sendLine(_ line: String) async throws {}

    package func readLine() async -> String? {
        let turn = lock.withLock { () -> Int in
            let n = reads
            reads += 1
            return n
        }
        // Only the first read waits for the release; the rest drain.
        if turn == 0 {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let go = lock.withLock { () -> Bool in
                    if released { return true }
                    waiter = cont
                    return false
                }
                if go { cont.resume() }
            }
        }
        return turn < lines.count ? lines[turn] : nil
    }

    package func terminate() async {}
    package var isRunning: Bool { lock.withLock { reads == 0 } }
}
