import Foundation

/// Short notices repeat; hashing UTF-8 keeps the key stable across launches.
public struct PhraseCache: Sendable {
    private static let maxChars = 80

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func data(for phrase: String) throws -> Data? {
        guard phrase.count <= Self.maxChars else { return nil }
        let url = fileURL(for: phrase)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func store(_ data: Data, for phrase: String) throws {
        guard phrase.count <= Self.maxChars else { return }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL(for: phrase), options: .atomic)
    }

    private func fileURL(for phrase: String) -> URL {
        directory.appendingPathComponent(Self.fnv1a(phrase))
    }

    private static func fnv1a(_ phrase: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in phrase.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
