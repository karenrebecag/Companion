import Foundation

/// Which specialist thread belongs to which folder. Keyed by executor AND
/// workdir on purpose: the same CLI pointed at another directory is another
/// conversation, and resuming across folders mixes unrelated work.
package struct ExecutorSessionKey: Hashable, Sendable {
    package var executor: ExecutorID
    package var workdir: String

    package init(executor: ExecutorID, workdir: String) {
        self.executor = executor
        self.workdir = workdir
    }
}

/// Where a specialist thread lives between app launches. The in-memory id on
/// the executor died with the process, so every restart started a new thread
/// and "what were we doing?" had no possible answer.
package protocol ExecutorSessionStoring: Sendable {
    func session(for key: ExecutorSessionKey) -> String?
    func set(_ id: String?, for key: ExecutorSessionKey)
    /// What a running job pins. Only a clear moves it.
    func currentGeneration() -> Int
}

/// The generation a running job captured. Absent means the write is new and
/// may use the generation that is current now.
package enum ExecutorSessionWrite {
    @TaskLocal package static var generation: Int?
}

/// One counter per sessions file. A clear moves it only after the file is
/// gone, so a job that started before the clear cannot put that file back.
/// A thread switch does not move it: that must not drop a specialist thread.
package final class ExecutorSessionEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    package func current() -> Int {
        lock.withLock { value }
    }

    package func withLock<T>(_ body: () throws -> T) rethrows -> T {
        try lock.withLock(body)
    }

    /// The body and the bump share the lock. A throw leaves the generation
    /// where the in-flight job still expects it.
    package func commit(_ body: () throws -> Void) rethrows {
        try lock.withLock {
            try body()
            value += 1
        }
    }

    package func write(seen: Int, _ body: () -> Void) {
        lock.withLock {
            guard seen == value else { return }
            body()
        }
    }
}

package enum ExecutorSessionEpochs {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var epochs: [String: ExecutorSessionEpoch] = [:]

    /// The same path string from the store and from the history clear.
    /// Symlinks are not resolved: Foundation drops the /private prefix only
    /// while the file exists, which split one file into two epochs. The
    /// prefix is dropped here instead, whether or not the file is there.
    package static func shared(file: URL) -> ExecutorSessionEpoch {
        let key = stableKey(file)
        return lock.withLock {
            if let existing = epochs[key] { return existing }
            let made = ExecutorSessionEpoch()
            epochs[key] = made
            return made
        }
    }

    private static func stableKey(_ file: URL) -> String {
        let path = file.standardizedFileURL.path
        for root in ["/private/var/", "/private/tmp/", "/private/etc/"] where path.hasPrefix(root) {
            return String(path.dropFirst("/private".count))
        }
        return path
    }
}

package enum ExecutorSessions: Sendable {
    /// "Resume whatever was last", for a CLI that keeps that notion itself.
    /// Hermes does; claude does not — and a flag that fails would stay in the
    /// store poisoning every later launch, so for claude it means "start
    /// fresh" instead (scar from the prototype's SessionStore).
    package static let latest = "latest"

    package static func effective(
        _ session: String?, for executor: ExecutorID
    ) -> String? {
        guard session == latest else { return session }
        return executor.rawValue.hasPrefix("claude") ? nil : latest
    }
}
