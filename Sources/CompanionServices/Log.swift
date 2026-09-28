import Foundation

public enum Log: Sendable {
    /// Mutable sink: App injects the file so tests never touch ~/Library/Logs.
    private final class Sink: @unchecked Sendable {
        let lock = NSLock()
        var fileURL: URL?
        var failed = false
    }

    private static let sink = Sink()

    /// Code review 2026-09-24 (medio): tests run in parallel and each one
    /// that pointed the process-wide sink at its own file could lose its
    /// lines to the next. A capture binds to the task tree instead.
    @TaskLocal private static var capture: URL?

    public static func configure(fileURL: URL) {
        sink.lock.lock()
        sink.fileURL = fileURL
        sink.failed = false
        sink.lock.unlock()
    }

    /// Routes every line logged by `body` and the tasks it starts (not
    /// detached ones) to `url`, leaving the process-wide sink untouched.
    public static func capturing<R>(
        to url: URL,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R
    ) async rethrows -> R {
        try await $capture.withValue(url, operation: body, isolation: isolation)
    }

    public static func app(_ message: String) { write(tag: "app", message: message) }

    public static func chat(_ message: String) { write(tag: "chat", message: message) }

    public static func audio(_ message: String) { write(tag: "audio", message: message) }

    /// Wave 17: the local bridge (socket, hello, calls). Never the tool
    /// arguments or `output` — only name, outcome, target and a char count.
    public static func bridge(_ message: String) { write(tag: "bridge", message: message) }

    private static func write(tag: String, message: String) {
        let line = "\(timestamp()) [\(tag)] \(message)\n"
        sink.lock.lock()
        defer { sink.lock.unlock() }
        if let captured = capture {
            // A failed capture only loses its own test's lines; the test
            // reading them is what reports it.
            _ = append(line, to: captured)
            return
        }
        guard let url = sink.fileURL, !sink.failed else { return }
        if !append(line, to: url) { sink.failed = true }
    }

    /// Caller holds `sink.lock`. False when the line could not be written.
    private static func append(_ line: String, to url: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            return false
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
                return true
            } catch {
                return false
            }
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
