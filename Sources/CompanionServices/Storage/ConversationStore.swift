import CompanionCore
import Foundation

package final class ConversationStore: ConversationStoring, Sendable {
    package static let cap = 30

    private let directory: URL
    private let cap: Int
    private static let trashPrefix = ".companion-history-clear-"

    private let makeDirectory: @Sendable (URL) throws -> Void

    package static let defaultMakeDirectory: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// `makeDirectory` is a seam: the put-back after a failed recreate cannot
    /// be reached on a real disk without breaking the folder it restores.
    package init(
        directory: URL, cap: Int = ConversationStore.cap,
        makeDirectory: @escaping @Sendable (URL) throws -> Void = ConversationStore.defaultMakeDirectory
    ) {
        self.directory = directory
        self.cap = cap
        self.makeDirectory = makeDirectory
        Self.sweepLeftovers(beside: directory)
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
                    id: stored.id, title: stored.title, updatedAt: stored.updatedAt))
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
    package func clearHistory() throws {
        Self.sweepLeftovers(beside: directory)
        try replaceConversationDirectory()
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
            try fm.moveItem(at: directory, to: trash)
        } catch {
            throw PersistenceError.io
        }
        do {
            try ensureDirectory()
        } catch {
            putBack(trash)
            throw PersistenceError.io
        }
        do {
            try fm.removeItem(at: trash)
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
            })
    }
}

private struct StoredConversation: Codable {
    var id: String
    var title: String
    var updatedAt: Date
    var messages: [StoredMessage]
}

private struct StoredMessage: Codable {
    var role: String
    var text: String
    var attachments: [String]?
    /// Absent in every file written before 16m-6.
    var choice: Bool?
}
