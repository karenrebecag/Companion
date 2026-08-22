import CompanionCore
import Foundation

/// Screen copy for the chat surface. The wording lives in the catalogs
/// (en.lproj is the source); this stays the seam every view goes through, so
/// a new string cannot enter the app monolingual by accident.
public enum ChatCopy {
    public static var emptyKey: String { Localized.string("chat.key.empty") }

    public static func error(_ error: Error) -> String {
        if let chat = error as? ChatError {
            return chatCopy(chat)
        }
        if let secret = error as? SecretStoreError {
            return secretCopy(secret)
        }
        if error is PersistenceError {
            return Localized.string("chat.error.persistence")
        }
        return Localized.string("chat.error.generic")
    }

    public static var malformedKey: String {
        Localized.string("chat.key.malformed")
    }

    public static func handoff(_ h: Handoff) -> String {
        String(format: Localized.string("chat.handoff.pending"), h.goal)
    }

    private static func chatCopy(_ error: ChatError) -> String {
        switch error {
        case .unauthorized, .invalidKey:
            return Localized.string("chat.error.invalidKey")
        case .forbidden:
            return Localized.string("chat.error.forbidden")
        case .rateLimited:
            return Localized.string("chat.error.rateLimited")
        case .timeout, .unreachable:
            return Localized.string("chat.error.unreachable")
        case .httpStatus(let code):
            return String(
                format: Localized.string("chat.error.httpStatus"), code)
        case .noProvider:
            return Localized.string("chat.error.noProvider")
        case .empty:
            return Localized.string("chat.error.empty")
        }
    }

    private static func secretCopy(_ error: SecretStoreError) -> String {
        switch error {
        case .denied:
            return Localized.string("chat.secret.denied")
        case .emptyValue:
            return emptyKey
        case .notAvailable, .unexpected:
            return Localized.string("chat.secret.failed")
        }
    }

    /// Tool names are wire identifiers, not copy: they stay as the specialist
    /// reports them so a step can be matched to a log line.
    public static func step(_ tool: String, _ summary: String) -> String {
        summary.isEmpty ? tool : "\(tool): \(summary)"
    }

    public static func stepDone(_ tool: String, ok: Bool) -> String {
        String(
            format: Localized.string(ok ? "chat.step.done" : "chat.step.failed"),
            tool)
    }

    public static var approvalPending: String {
        Localized.string("chat.approval.pending")
    }

    public static func approvalAnswer(_ approved: Bool) -> String {
        Localized.string(
            approved ? "chat.approval.granted" : "chat.approval.denied")
    }

    public static var jobDone: String { Localized.string("chat.job.done") }
    public static var jobFailed: String { Localized.string("chat.job.failed") }

    public static func attached(_ name: String) -> String {
        String(format: Localized.string("chat.attach.done"), name)
    }

    public static func attachFailed(_ error: AttachmentError) -> String {
        switch error {
        case .tooLarge: return Localized.string("chat.attach.tooLarge")
        case .unreadable: return Localized.string("chat.attach.unreadable")
        case .io: return Localized.string("chat.attach.io")
        }
    }

    /// Readable summary of a tool request: raw JSON is not a decision aid.
    /// Nothing to translate — it is the specialist's own input echoed back.
    public static func approvalDetail(
        tool: String, inputJSON: String
    ) -> String {
        guard let data = inputJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return tool }
        let interesting = ["command", "path", "url", "query", "content"]
        for key in interesting {
            if let value = object[key] as? String, !value.isEmpty {
                return value.count > 200 ? String(value.prefix(200)) + "…" : value
            }
        }
        return tool
    }
}
