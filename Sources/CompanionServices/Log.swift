import Foundation

public enum Log: Sendable {
    /// Mutable sink: App injects the file so tests never touch ~/Library/Logs.
    private final class Sink: @unchecked Sendable {
        let lock = NSLock()
        var fileURL: URL?
        var failed = false
    }

    private static let sink = Sink()

    public static func configure(fileURL: URL) {
        sink.lock.lock()
        sink.fileURL = fileURL
        sink.failed = false
        sink.lock.unlock()
    }

    public static func app(_ message: String) { write(tag: "app", message: message) }

    public static func chat(_ message: String) { write(tag: "chat", message: message) }

    public static func audio(_ message: String) { write(tag: "audio", message: message) }

    private static func write(tag: String, message: String) {
        sink.lock.lock()
        defer { sink.lock.unlock() }
        guard let url = sink.fileURL, !sink.failed else { return }

        let line = "\(timestamp()) [\(tag)] \(message)\n"
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            sink.failed = true
            return
        }

        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let handle = try FileHandle(forWritingTo: url)
                defer {
                    // Already wrote; a close error must not disable later logs.
                    do { try handle.close() } catch {}
                }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                sink.failed = true
            }
        } else {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                sink.failed = true
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
