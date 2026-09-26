import CompanionCore
import Foundation

/// Companion's memory on disk: plain markdown the user can open and edit.
/// `core.md` is the stable profile, `sessions/` holds one short summary per
/// session, `notes/` holds what the specialist was asked to remember. No
/// vectors, no database — files are debuggable and honest (9j-2).
public final class FileMemoryStore: MemoryStore, MemoryBrowsing, @unchecked Sendable {
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

    // MARK: - Settings › Memoria (16g)

    public func entries() -> [MemoryEntry] {
        let listed = [("sessions", MemoryEntry.Kind.session), ("notes", .note)].flatMap { folder, kind in
            names(in: folder).map { name in
                MemoryEntry(
                    id: "\(folder)/\(name)", kind: kind, day: String(name.prefix(10)),
                    text: readFile(root.appendingPathComponent(folder).appendingPathComponent(name)))
            }
        }
        // The stamp in the name orders them; the folder only breaks a tie.
        return listed.filter { !$0.text.isEmpty }.sorted {
            let (a, b) = (stamp($0.id), stamp($1.id))
            return a == b ? $0.id > $1.id : a > b
        }
    }

    /// Only an id this store listed can be forgotten: the id arrives from a
    /// view, so it is matched against the folder, never joined into a path
    /// on its own (a "../core.md" would otherwise reach the profile).
    public func forget(_ id: String) throws {
        // Safe only because entries() lists nothing readFile refused: a link
        // reads as empty and is filtered out before it can be matched here.
        guard let entry = entries().first(where: { $0.id == id }) else {
            throw MemoryBrowsingError.notAnEntry
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent(entry.id))
        Log.app("memory: forgot one \(entry.kind.rawValue)")
    }

    private func stamp(_ id: String) -> Substring {
        id.split(separator: "/").last ?? Substring(id)
    }

    /// The one place a memory folder is listed. A linked folder counts as
    /// missing: its files would pass the per-file check and leak whatever
    /// directory it points at (security re-review 16g).
    private func names(in folder: String) -> [String] {
        let dir = root.appendingPathComponent(folder)
        do {
            if try dir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                Log.app("memory: skipped a linked folder")
                return []
            }
            return try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".md") }
        } catch {
            // A missing folder is the normal empty state, not an error.
            return []
        }
    }

    // MARK: - Internals

    /// Newest last, so the prompt reads oldest-to-newest like a diary.
    private func recentFiles(in folder: String, limit: Int) -> [String] {
        let dir = root.appendingPathComponent(folder)
        return names(in: folder).sorted().suffix(limit)
            .map { readFile(dir.appendingPathComponent($0)) }
            .filter { !$0.isEmpty }
    }

    /// A file that cannot be read is an empty memory, said once in the log —
    /// never a crash and never a silent lie mid-session.
    private func readFile(_ url: URL) -> String {
        // Only a plain file is memory: a link would carry whatever it points
        // at into Settings and into the prompt (security review 16g).
        guard Self.isPlainFile(url) else {
            if FileManager.default.fileExists(atPath: url.path) {
                Log.app("memory: skipped a non-regular file")
            }
            return ""
        }
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

    /// Asked without following links: a link reports as a link, never as
    /// the regular file behind it.
    static func isPlainFile(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            return values.isSymbolicLink != true && values.isRegularFile == true
        } catch {
            return false
        }
    }

    static func stamp(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: now)
    }
}
