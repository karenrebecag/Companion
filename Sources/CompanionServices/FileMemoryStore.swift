import CompanionCore
import Foundation

/// Companion's memory on disk: plain markdown the user can open and edit.
/// `core.md` is the stable profile, `sessions/` holds one short summary per
/// session, `notes/` holds what the specialist was asked to remember. No
/// vectors, no database — files are debuggable and honest (9j-2).
public final class FileMemoryStore: MemoryStore, @unchecked Sendable {
    private let root: URL
    private let recentSessions: Int

    public init(
        root: URL = MemoryLocation.directory(),
        recentSessions: Int = 3
    ) {
        self.root = root
        self.recentSessions = recentSessions
    }

    /// First run: the profile the user already wrote in Settings becomes the
    /// starting core, so memory begins knowing what Companion already knew.
    public func ensureCore(seed: String) {
        let core = root.appendingPathComponent("core.md")
        guard !FileManager.default.fileExists(atPath: core.path) else { return }
        ensureDirectories()
        let trimmed = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.isEmpty
            ? "# Sobre la usuaria\n\n(Companion aún no sabe nada; "
                + "este archivo es tuyo — edítalo.)\n"
            : "# Sobre la usuaria\n\n" + trimmed + "\n"
        do {
            try content.write(to: core, atomically: true, encoding: .utf8)
        } catch {
            Log.app("memory: could not seed core.md (\(error))")
        }
    }

    public func load() -> MemoryPack {
        let core = readFile(root.appendingPathComponent("core.md"))
        return MemoryPack(
            core: core.trimmingCharacters(in: .whitespacesAndNewlines),
            recentSessions: recentFiles(in: "sessions", limit: recentSessions),
            notes: recentFiles(in: "notes", limit: 5))
    }

    public func appendSession(_ summary: String) throws {
        ensureDirectories()
        let stamp = Self.stamp()
        let file = root.appendingPathComponent("sessions/\(stamp).md")
        try summary.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - Internals

    /// Newest last, so the prompt reads oldest-to-newest like a diary.
    private func recentFiles(in folder: String, limit: Int) -> [String] {
        let dir = root.appendingPathComponent(folder)
        // A missing folder is the normal empty state, not an error.
        let names: [String]
        do {
            names = try FileManager.default
                .contentsOfDirectory(atPath: dir.path)
        } catch {
            return []
        }
        return names.filter { $0.hasSuffix(".md") }.sorted().suffix(limit)
            .map { readFile(dir.appendingPathComponent($0)) }
            .filter { !$0.isEmpty }
    }

    /// A file that cannot be read is an empty memory, said once in the log —
    /// never a crash and never a silent lie mid-session.
    private func readFile(_ url: URL) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                Log.app("memory: unreadable \(url.lastPathComponent)")
            }
            return ""
        }
    }

    private func ensureDirectories() {
        for sub in ["", "sessions", "notes"] {
            do {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(sub),
                    withIntermediateDirectories: true)
            } catch {
                Log.app("memory: could not create \(sub.isEmpty ? "root" : sub)")
            }
        }
    }

    static func stamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: now)
    }
}
