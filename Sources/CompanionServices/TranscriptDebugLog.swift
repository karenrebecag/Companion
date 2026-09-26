import CompanionCore
import Foundation

/// Wave 15d-6: the hold's words, written only when Karen turns debugging on
/// (`Config.debugTranscripts`). A sink of its own, never `Log`: the main log
/// is shared in bug reports and must stay free of anything said.
public final class TranscriptDebugLog: @unchecked Sendable {
    /// Key prefixes of the providers the app holds keys for; a key read
    /// aloud or echoed by the model must not land in a plain-text file.
    /// `sk_` is ElevenLabs (security review 2026-09-25).
    private static let keyPrefixes = ["sk-", "sk_", "gsk_", "csk-", "xai-"]
    private static let keyMinLength = 20

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func standard(home: URL) -> TranscriptDebugLog {
        TranscriptDebugLog(
            fileURL: home.appendingPathComponent("Library/Logs/Companion-transcripts.log"))
    }

    public func heard(_ text: String) { write(tag: "heard", text) }

    public func said(_ text: String) { write(tag: "said", text) }

    /// Debugging off: yesterday's words do not stay on disk (spec 15d §6.4).
    public func discard() {
        lock.withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                Log.app("transcripts: discard failed")
            }
        }
    }

    static func line(tag: String, _ text: String, at date: Date = Date()) -> String {
        // One entry per line: a line break inside what was heard must not
        // forge a second `said=` entry.
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        let stamp = ISO8601DateFormatter().string(from: date)
        return "\(stamp) \(tag)=\(redacted(flat))\n"
    }

    /// A key can sit anywhere in a word — after "(", a quote, "clave:" — so
    /// the scan looks for the prefix at every position, not per token.
    static func redacted(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var index = 0
        while index < chars.count {
            let end = keyEnd(in: chars, from: index)
            if end - index >= keyMinLength {
                out += "[redacted]"
                index = end
            } else {
                out.append(chars[index])
                index += 1
            }
        }
        return out
    }

    /// Where a key starting at `start` ends; `start` when none starts there.
    private static func keyEnd(in chars: [Character], from start: Int) -> Int {
        let startsKey = keyPrefixes.contains { prefix in
            let candidate = chars[start...].prefix(prefix.count)
            return String(candidate) == prefix
        }
        guard startsKey else { return start }
        var end = start
        while end < chars.count, isKeyCharacter(chars[end]) { end += 1 }
        return end
    }

    private static func isKeyCharacter(_ char: Character) -> Bool {
        (char.isASCII && (char.isLetter || char.isNumber)) || char == "-" || char == "_"
    }

    private func write(tag: String, _ text: String) {
        let data = Data(Self.line(tag: tag, text).utf8)
        lock.withLock {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                Log.app("transcripts: directory failed")
                return
            }
            // O_NOFOLLOW: a symlink planted where the log goes would send
            // the user's words wherever it points. fchmod on every append:
            // a file some other process left 0644 is tightened before any
            // word lands in it, not only when this code created it.
            let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else {
                Log.app("transcripts: open refused (errno \(errno))")
                return
            }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            guard fchmod(fd, 0o600) == 0 else {
                Log.app("transcripts: chmod failed (errno \(errno))")
                return
            }
            do {
                try handle.write(contentsOf: data)
            } catch {
                Log.app("transcripts: write failed")
            }
        }
    }
}

extension VoiceSession {
    /// Composition-root call, once, like `attachDecision`: the runtime
    /// still checks `Config.debugTranscripts` per turn before writing.
    public func attachTranscriptLog(_ log: TranscriptDebugLog) {
        classic.transcripts = log
    }
}
