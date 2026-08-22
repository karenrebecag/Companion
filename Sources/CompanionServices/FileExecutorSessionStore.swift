import CompanionCore
import Foundation

/// Specialist threads on disk, next to the conversations. Nested by executor
/// then workdir so no separator can be confused with a path component.
/// A store that cannot be read is an empty store: a corrupt file must cost a
/// fresh thread, never a job.
public final class FileExecutorSessionStore: ExecutorSessionStoring, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func session(for key: ExecutorSessionKey) -> String? {
        lock.withLock { load()[key.executor.rawValue]?[key.workdir] }
    }

    public func set(_ id: String?, for key: ExecutorSessionKey) {
        lock.withLock {
            var all = load()
            var byWorkdir = all[key.executor.rawValue] ?? [:]
            byWorkdir[key.workdir] = id
            all[key.executor.rawValue] = byWorkdir
            save(all)
        }
    }

    private func load() -> [String: [String: String]] {
        // No file yet is the normal first run, not a failure worth a line.
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(
                [String: [String: String]].self, from: data)
        } catch {
            Log.app("sessions: store ilegible; arranco vacío")
            return [:]
        }
    }

    private func save(_ all: [String: [String: String]]) {
        do {
            let data = try JSONEncoder().encode(all)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Losing the id costs a fresh thread next launch, nothing more.
            Log.app("sessions: no pude guardar el hilo del especialista")
        }
    }
}
