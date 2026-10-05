import CompanionCore
import CryptoKit
import Foundation

/// The copies kept around a save of the user's file. They live in a private
/// folder of the app, not next to the file: a stray copy in the user's folder
/// is clutter they did not ask for, and a private store can be capped without
/// touching anything of theirs. Fail-open: a snapshot never blocks the save.
package struct FileVersions: Sendable {
    package enum Trigger: String, Sendable, Equatable {
        case preSave
        case postSave
    }

    package enum Outcome: Sendable, Equatable {
        case saved(URL)
        /// Nothing at that path, or not a regular file: nothing to lose.
        case noPrevious
        /// Bigger than the cap; the caller says so instead of pretending.
        case tooLarge(Int)
        /// The copy could not be made; the save goes ahead anyway.
        case failed
    }

    package struct Version: Sendable, Equatable {
        package let url: URL
        package let trigger: Trigger
        package let date: Date
    }

    package static let defaultMaxBytes = 50 * 1024 * 1024

    /// A folder that was just created is empty until its copy lands; another snapshot's
    /// sweep must not take it from under that copy.
    private static let emptyFolderGrace: TimeInterval = 60

    private let root: URL
    package var rootPath: String { root.path }
    private let maxVersions: Int
    private let maxBytes: Int
    private let maxAge: TimeInterval
    private let maxTotalBytes: Int
    private let now: @Sendable () -> Date

    package init(
        root: URL,
        maxVersions: Int = 20,
        maxBytes: Int = FileVersions.defaultMaxBytes,
        maxAge: TimeInterval = 30 * 24 * 3600,
        maxTotalBytes: Int = 1024 * 1024 * 1024,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.root = root
        self.maxVersions = maxVersions
        self.maxBytes = maxBytes
        self.maxAge = maxAge
        self.maxTotalBytes = maxTotalBytes
        self.now = now
    }

    /// Same place as the other private stores (attachments, conversations).
    package static func standard(
        appSupport: URL = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> FileVersions {
        FileVersions(root: appSupport.appendingPathComponent("Companion/file-versions", isDirectory: true))
    }

    /// Keyed by where the path really lands, so a link and its target share
    /// one history.
    private func folder(for path: String) -> URL {
        let real = (path as NSString).resolvingSymlinksInPath
        let digest = SHA256.hash(data: Data(real.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(String(digest.prefix(24)), isDirectory: true)
    }

    /// Oldest first.
    package func versions(of path: String) -> [Version] {
        let directory = folder(for: path)
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) } catch { return [] }
        return names.compactMap { name in
            Self.parse(name).map { Version(url: directory.appendingPathComponent(name), trigger: $0.trigger, date: $0.date) }
        }.sorted { $0.date < $1.date }
    }

    package func snapshot(_ path: String, trigger: Trigger) -> Outcome {
        let real = (path as NSString).resolvingSymlinksInPath
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: real) } catch { return .noPrevious }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return .noPrevious }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maxBytes else { return .tooLarge(size) }

        let directory = folder(for: real)
        do {
            // Root first and on its own: with intermediate directories the mode would only
            // reach the last component, leaving the root at the umask's.
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // createDirectory leaves an existing one as it was: an older run may have left it looser.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let copy = directory.appendingPathComponent(Self.name(trigger: trigger, at: now(), original: real))
            try FileManager.default.copyItem(atPath: real, toPath: copy.path)
            // The source can be swapped for a link between the check and the copy; a link in
            // the store would read whatever it points at later.
            guard try copy.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                try FileManager.default.removeItem(at: copy)
                return .failed
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
            prune(keeping: copy)
            return .saved(copy)
        } catch {
            // Constant text: the error and the path would put the user's file names in the log.
            Log.app("file versions: snapshot failed")
            return .failed
        }
    }

    // MARK: - Names

    /// `<microseconds>-<trigger>-<id>-<original name>`. The stamp is the version's age and
    /// order (micro, not milli: a pre and a post of a tiny file can land in the same
    /// millisecond); the original name is only a hint for a human.
    private static func name(trigger: Trigger, at date: Date, original: String) -> String {
        let stamp = String(Int(date.timeIntervalSince1970 * 1_000_000))
        // APFS caps a name in bytes, so the hint is cut by bytes, never by characters.
        let hint = byteSafe((original as NSString).lastPathComponent, limit: 120)
        return [stamp, trigger.rawValue, String(UUID().uuidString.prefix(8)), hint].joined(separator: "-")
    }

    private static func parse(_ name: String) -> (trigger: Trigger, date: Date)? {
        let parts = name.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let micro = Double(parts[0]), let trigger = Trigger(rawValue: String(parts[1])) else {
            return nil
        }
        return (trigger, Date(timeIntervalSince1970: micro / 1_000_000))
    }

    private static func byteSafe(_ text: String, limit: Int) -> String {
        var out = ""
        var bytes = 0
        for character in text {
            bytes += String(character).utf8.count
            if bytes > limit { break }
            out.append(character)
        }
        return out
    }

    // MARK: - Retention

    private struct Entry {
        let url: URL
        let date: Date
        let size: Int
    }

    /// Age and the per-file count judge every folder; the global cap judges the whole
    /// store. `fresh` is never removed: it is the copy the caller was promised. It is
    /// matched by its unique file name, because URLs from a directory listing do not
    /// compare equal to the one built here. Its folder is never swept either.
    /// Only what the store made is touched: a child named like a store folder (24 hex
    /// characters), not a link, and inside it only names that parse.
    private func prune(keeping fresh: URL) {
        let folders: [URL]
        do { folders = try storeFolders() } catch { return }
        let freshName = fresh.lastPathComponent
        let cutoff = now().addingTimeInterval(-maxAge)
        var survivors: [Entry] = []
        for directory in folders {
            let all = entries(in: directory)
            for entry in all where entry.date < cutoff && entry.url.lastPathComponent != freshName { remove(entry.url) }
            let live = all.filter { $0.date >= cutoff || $0.url.lastPathComponent == freshName }
            let overflow = max(0, live.count - maxVersions)
            let doomed = live.filter { $0.url.lastPathComponent != freshName }.prefix(overflow)
            for entry in doomed { remove(entry.url) }
            survivors.append(contentsOf: live.filter { entry in !doomed.contains { $0.url == entry.url } })
            if directory.lastPathComponent != fresh.deletingLastPathComponent().lastPathComponent { removeIfEmpty(directory) }
        }
        var total = survivors.reduce(0) { $0 + $1.size }
        for entry in survivors.sorted(by: { $0.date < $1.date }) where total > maxTotalBytes && entry.url.lastPathComponent != freshName {
            remove(entry.url)
            total -= entry.size
        }
    }

    private func storeFolders() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]).filter { url in
            let name = url.lastPathComponent
            guard name.count == 24, name.allSatisfy(\.isHexDigit) else { return false }
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]) } catch { return false }
            return values.isSymbolicLink == false && values.isDirectory == true
        }
    }

    private func entries(in directory: URL) -> [Entry] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        } catch { return [] }
        return urls.compactMap { url in
            guard let parsed = Self.parse(url.lastPathComponent) else { return nil }
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) } catch { return nil }
            guard values.isRegularFile == true else { return nil }
            return Entry(url: url, date: parsed.date, size: values.fileSize ?? 0)
        }.sorted { $0.date < $1.date }
    }

    /// Empty on disk, not just "no entry we recognise": a foreign file inside keeps the folder.
    private func removeIfEmpty(_ directory: URL) {
        do {
            guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else { return }
            let modified = try directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, now().timeIntervalSince(modified) < Self.emptyFolderGrace { return }
            try FileManager.default.removeItem(at: directory)
        } catch { return }
    }

    private func remove(_ url: URL) {
        do { try FileManager.default.removeItem(at: url) } catch { Log.app("file versions: prune failed") }
    }
}
