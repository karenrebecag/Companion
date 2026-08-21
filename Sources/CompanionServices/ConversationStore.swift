import CompanionCore
import Foundation

public final class ConversationStore: ConversationStoring, Sendable {
    public static let cap = 30

    private let directory: URL
    private let cap: Int

    public init(directory: URL, cap: Int = ConversationStore.cap) {
        self.directory = directory
        self.cap = cap
    }

    public func list() throws -> [ConversationMeta] {
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

    public func save(_ record: ConversationRecord) throws {
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

    public func load(_ id: String) throws -> ConversationRecord? {
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

    private func ensureDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
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
                    attachments: $0.attachmentPaths.isEmpty ? nil : $0.attachmentPaths)
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
                    attachmentPaths: $0.attachments ?? [])
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
}
