import CompanionCore
import Foundation

package final class ConversationStore: ConversationStoring, Sendable {
    package static let cap = 30

    private let directory: URL
    private let cap: Int
    private static let trashPrefix = ".companion-history-clear-"

    private let makeDirectory: @Sendable (URL) throws -> Void
    private let moveItem: @Sendable (URL, URL) throws -> Void
    private let removeItem: @Sendable (URL) throws -> Void

    package static let defaultMoveItem: @Sendable (URL, URL) throws -> Void = { from, to in
        try FileManager.default.moveItem(at: from, to: to)
    }

    package static let defaultRemoveItem: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.removeItem(at: url)
    }

    package static let defaultMakeDirectory: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// The three file seams exist because the put-back and the rollback of a
    /// clear cannot be reached on a real disk without breaking the folder
    /// they restore.
    package init(
        directory: URL, cap: Int = ConversationStore.cap,
        makeDirectory: @escaping @Sendable (URL) throws -> Void = ConversationStore.defaultMakeDirectory,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void = ConversationStore.defaultMoveItem,
        removeItem: @escaping @Sendable (URL) throws -> Void = ConversationStore.defaultRemoveItem
    ) {
        self.directory = directory
        self.cap = cap
        self.makeDirectory = makeDirectory
        self.moveItem = moveItem
        self.removeItem = removeItem
        // A crash between parking the sessions file and the rename leaves
        // the only copy inside the live folder. Put it back before anything
        // else reads it.
        sessionEpoch.withLock {
            Self.sweepLeftovers(beside: directory)
            Self.restoreParkedSessions(beside: directory)
        }
    }

    package func list() throws -> [ConversationMeta] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw PersistenceError.io
        }
        var metas: [ConversationMeta] = []
        for url in files where url.pathExtension == "json" {
            if let stored = decodeStored(at: url) {
                metas.append(ConversationMeta(
                    id: stored.id, title: stored.title, updatedAt: stored.updatedAt,
                    run: stored.run?.taskRun))
            }
        }
        metas.sort { $0.updatedAt > $1.updatedAt }
        return Array(metas.prefix(cap))
    }

    package func save(_ record: ConversationRecord) throws {
        guard !record.messages.isEmpty else { return }
        try ensureDirectory()
        let data: Data
        do {
            data = try makeEncoder().encode(stored(from: record))
        } catch {
            throw PersistenceError.encoding
        }
        do {
            try data.write(to: try fileURL(for: record.id), options: .atomic)
        } catch {
            throw PersistenceError.io
        }
        prune()
    }

    /// Tasks started in chats are these conversation files. There is no
    /// second task directory. The rename is the cut: deleting files one by
    /// one can stop halfway and leave some chats behind. A failure before
    /// the cut keeps every chat and throws; one after it counts as cleared and
    /// leaves the old folder for the next sweep, never a partial set back in
    /// the live folder.
    ///
    /// executor-sessions.json is the sibling the app writes beside this
    /// folder. The parent also holds memory, skills and attachments, so the
    /// clear parks that one file inside the folder and lets the rename cut
    /// both. The generation moves only when the cut sticks, so a job that
    /// started earlier cannot write the file back.
    package func clearHistory() throws {
        try sessionEpoch.commit {
            Self.sweepLeftovers(beside: directory)
            Self.restoreParkedSessions(beside: directory)
            do {
                try parkSessionsIntoConversations()
                try replaceConversationDirectory()
            } catch {
                Self.restoreParkedSessions(beside: directory)
                throw error
            }
        }
    }

    /// The sibling file next to this folder; it must match the name the
    /// composition root gives the live sessions store.
    private static let sessionsFileName = "executor-sessions.json"
    /// Not json: list() decodes every json file in the folder as a chat.
    private static let parkedSessionsName = ".executor-sessions-clear"

    private var sessionEpoch: ExecutorSessionEpoch {
        ExecutorSessionEpochs.shared(file: Self.sessionsFile(beside: directory))
    }

    private static func sessionsFile(beside directory: URL) -> URL {
        directory.deletingLastPathComponent().appendingPathComponent(sessionsFileName)
    }

    private static func parkedSessions(in directory: URL) -> URL {
        directory.appendingPathComponent(parkedSessionsName)
    }

    private func parkSessionsIntoConversations() throws {
        let fm = FileManager.default
        let live = Self.sessionsFile(beside: directory)
        guard fm.fileExists(atPath: live.path) else { return }
        if !fm.fileExists(atPath: directory.path) {
            try ensureDirectory()
        }
        let parked = Self.parkedSessions(in: directory)
        if fm.fileExists(atPath: parked.path) {
            do {
                try removeItem(parked)
            } catch {
                throw PersistenceError.io
            }
        }
        do {
            try moveItem(live, parked)
        } catch {
            throw PersistenceError.io
        }
    }

    private static func restoreParkedSessions(beside directory: URL) {
        let fm = FileManager.default
        let parked = parkedSessions(in: directory)
        guard fm.fileExists(atPath: parked.path) else { return }
        let live = sessionsFile(beside: directory)
        if fm.fileExists(atPath: live.path) {
            // The live file is what a resume would read. The parked copy is
            // the leftover of a cut that already moved on.
            try? fm.removeItem(at: parked)
            return
        }
        do {
            try fm.moveItem(at: parked, to: live)
        } catch {
            Log.chat("could not restore the specialist sessions")
        }
    }

    package func load(_ id: String) throws -> ConversationRecord? {
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw PersistenceError.io
        }
        do {
            return record(from: try makeDecoder().decode(
                StoredConversation.self, from: data))
        } catch {
            throw PersistenceError.decoding
        }
    }

    private func fileURL(for id: String) throws -> URL {
        guard Self.isSafeID(id) else { throw PersistenceError.io }
        return directory.appendingPathComponent("\(id).json")
    }

    /// Ids are path components; reject traversal before touching disk.
    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty
            && id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            && !id.contains("..")
    }

    private func replaceConversationDirectory() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let trash = directory.deletingLastPathComponent()
            .appendingPathComponent(Self.trashPrefix + UUID().uuidString, isDirectory: true)
        do {
            try moveItem(directory, trash)
        } catch {
            throw PersistenceError.io
        }
        do {
            try ensureDirectory()
        } catch {
            putBack(trash)
            throw PersistenceError.io
        }
        // The parked sessions are the erased tasks' resume ids: take them out
        // on their own first, so a trash folder that stays does not keep them.
        let stranded = Self.parkedSessions(in: trash)
        if fm.fileExists(atPath: stranded.path) {
            do {
                try removeItem(stranded)
            } catch {
                Log.chat("could not remove the parked specialist sessions; the next launch sweeps them")
            }
        }
        do {
            try removeItem(trash)
        } catch {
            // The rename already cut every chat from the live folder: the
            // clear happened, and the leftover is the sweep's to remove.
            Log.chat("could not remove the old conversations folder; the next clear sweeps it")
        }
    }

    /// Only when nothing was deleted yet: the folder moved aside goes back.
    private func putBack(_ trash: URL) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
            try fm.moveItem(at: trash, to: directory)
        } catch {
            Log.chat("could not put the conversations folder back")
        }
        // The sessions file rode along inside the folder. Put it back beside
        // the folder, or a failed clear would hide it from --resume.
        Self.restoreParkedSessions(beside: directory)
    }

    /// What a crash or a failed removal left beside the live folder.
    private static func sweepLeftovers(beside directory: URL) {
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        let siblings: [URL]
        do {
            siblings = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        } catch {
            // A parent that does not exist yet is the first run, not a failure.
            if fm.fileExists(atPath: parent.path) {
                Log.chat("could not list the folder to sweep for leftovers")
            }
            return
        }
        for url in siblings where url.lastPathComponent.hasPrefix(trashPrefix) {
            do {
                try fm.removeItem(at: url)
            } catch {
                Log.chat("could not sweep a leftover conversations folder")
            }
        }
    }

    private func ensureDirectory() throws {
        do {
            try makeDirectory(directory)
        } catch {
            throw PersistenceError.io
        }
    }

    private func prune() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch {
            return
        }
        var ranked: [(url: URL, updatedAt: Date)] = []
        for url in files where url.pathExtension == "json" {
            if let stored = decodeStored(at: url) {
                ranked.append((url, stored.updatedAt))
            }
        }
        ranked.sort { $0.updatedAt > $1.updatedAt }
        guard ranked.count > cap else { return }
        for extra in ranked[cap...] {
            do {
                try FileManager.default.removeItem(at: extra.url)
            } catch {
                // Log removal failures but do not stop pruning.
                Log.chat("failed to remove old conversation file")
            }
        }
    }

    private func decodeStored(at url: URL) -> StoredConversation? {
        do {
            let data = try Data(contentsOf: url)
            return try makeDecoder().decode(StoredConversation.self, from: data)
        } catch {
            // Log without path component to avoid exposing file names.
            Log.chat("skipping unreadable conversation file")
            return nil
        }
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func stored(from record: ConversationRecord) -> StoredConversation {
        StoredConversation(
            id: record.id,
            title: record.title,
            updatedAt: record.updatedAt,
            run: record.run.map(StoredRun.init),
            messages: record.messages.map {
                StoredMessage(
                    role: $0.role,
                    text: $0.text,
                    attachments: $0.attachmentPaths.isEmpty ? nil : $0.attachmentPaths,
                    choice: $0.fromChoice ? true : nil)
            })
    }

    private func record(from stored: StoredConversation) -> ConversationRecord {
        ConversationRecord(
            id: stored.id,
            title: stored.title,
            updatedAt: stored.updatedAt,
            messages: stored.messages.map {
                ConversationMessage(
                    role: $0.role,
                    text: $0.text,
                    attachmentPaths: $0.attachments ?? [],
                    fromChoice: $0.choice ?? false)
            },
            run: stored.run?.taskRun)
    }
}

private struct StoredConversation: Codable {
    var id: String
    var title: String
    var updatedAt: Date
    /// Absent in every file written before 16j-3.
    var run: StoredRun?
    var messages: [StoredMessage]
}

private struct StoredRun: Codable {
    /// A string, not the enum: a state this build does not know must drop the
    /// badge, not make the whole conversation unreadable.
    var state: String
    var startedAt: Date
    var finishedAt: Date?

    init(_ run: TaskRun) {
        state = run.state.rawValue
        startedAt = run.startedAt
        finishedAt = run.finishedAt
    }

    var taskRun: TaskRun? {
        TaskRun.State(rawValue: state).map {
            TaskRun(state: $0, startedAt: startedAt, finishedAt: finishedAt)
        }
    }
}

private struct StoredMessage: Codable {
    var role: String
    var text: String
    var attachments: [String]?
    /// Absent in every file written before 16m-6.
    var choice: Bool?
}
