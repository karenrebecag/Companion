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
