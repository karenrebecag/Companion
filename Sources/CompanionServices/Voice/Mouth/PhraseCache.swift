import Foundation

/// Short notices repeat; hashing UTF-8 keeps the key stable across launches.
package struct PhraseCache: Sendable {
    private static let maxChars = 80

    private let directory: URL
    /// Wave 15f-5: what else changes the audio (voice, speed, style). Empty
    /// keeps the keys every existing cache already has on disk.
    private let variant: String

    package init(directory: URL) {
        self.init(directory: directory, variant: "")
    }

    private init(directory: URL, variant: String) {
        self.directory = directory
        self.variant = variant
    }

    /// The same directory, keyed apart: audio stored under one variant is
    /// never read back under another.
    package func scoped(_ variant: String) -> PhraseCache {
        PhraseCache(directory: directory, variant: variant)
    }

    package func data(for phrase: String) throws -> Data? {
        guard phrase.count <= Self.maxChars else { return nil }
        let url = fileURL(for: phrase)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    package func store(_ data: Data, for phrase: String) throws {
        guard phrase.count <= Self.maxChars else { return }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL(for: phrase), options: .atomic)
    }

    private func fileURL(for phrase: String) -> URL {
        // Unit separator: no phrase or variant boundary can be forged by text.
        let key = variant.isEmpty ? phrase : variant + "\u{1F}" + phrase
        return directory.appendingPathComponent(Self.fnv1a(key))
    }

    static func fnv1a(_ phrase: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in phrase.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
