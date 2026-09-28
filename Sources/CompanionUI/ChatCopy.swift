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

    /// What the model is told a card showed. Names, never coordinates: the
    /// point of the card channel is that the payload does not reach it.
    public static func cardShown(_ card: Card) -> String {
        switch card.payload {
        case .locations(let block):
            let names = block.locations.map(\.name).joined(separator: ", ")
            return String(
                format: Localized.string("chat.card.locations"), names)
        case .gallery:
            return Localized.string("chat.card.gallery")
        case .stats, .table, .chart:
            return Localized.string("chat.card.data")
        }
    }

    public static var jobStopped: String {
        Localized.string("chat.job.stopped")
    }

    /// Was hardcoded Spanish in the UI layer, outside the catalog, where the
    /// static gate could not see it because it is not a `Text(...)`.
    public static func jobFailedNotice(_ error: Error) -> String {
        String(format: Localized.string("chat.job.failed"), "\(error)")
    }

    /// The specialist IS running. Used to mark what was delegated.
    public static func handoff(_ h: Handoff) -> String {
        String(format: Localized.string("chat.handoff.started"), h.goal)
    }

    /// Only when there is no runner wired at all — tests, and a composition
    /// with the specialist left out.
    public static func handoffUnavailable(_ h: Handoff) -> String {
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

    /// The user's "no", painted as a decision (Wave 10c 3B.4).
    public static func approvalDeniedTool(_ tool: String) -> String {
        String(format: Localized.string("chat.approval.deniedTool"), tool)
    }

    /// Answered from the session's memory, no sheet (Wave 10c 3B.2).
    public static func approvalRemembered(_ tool: String, approved: Bool) -> String {
        String(format: Localized.string(
            approved ? "chat.approval.rememberedAllow" : "chat.approval.rememberedDeny"), tool)
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
        // Parsed the way the executor parses (repair included): the sheet
        // must show exactly what will run (security review 2026-09-05).
        guard let object = ToolArguments.parse(inputJSON) else { return tool }
        // Wave 15g, review 2026-09-25 M1: the hands ask only about text the
        // user did not say, so the sheet shows all of it — a cut would hide
        // the part that runs. Return names the app, and in a command app the
        // line it would run.
        if tool == ParentTool.typeText.rawValue, let text = object["text"] as? String {
            return text
        }
        // Wave 16a: a destructive click names the button and its app.
        if tool == ParentTool.click.rawValue, let label = object["label"] as? String {
            let app = object["app"] as? String ?? ""
            return app.isEmpty ? label : "\(label) · \(app)"
        }
        if tool == ParentTool.pressKey.rawValue, let key = object["key"] as? String {
            var detail = key
            if let app = object["app"] as? String, !app.isEmpty { detail += " · \(app)" }
            if let line = object["line"] as? String, !line.isEmpty { detail += "\n\(line)" }
            return detail
        }
        // `goal`: a proposed handoff (security review 2026-09-25) is
        // approved on what it would delegate, never on the word "delegate".
        let interesting = ["command", "path", "url", "query", "content", "goal"]
        for key in interesting {
            if let value = object[key] as? String, !value.isEmpty {
                return value.count > 200 ? String(value.prefix(200)) + "…" : value
            }
        }
        return tool
    }
}
