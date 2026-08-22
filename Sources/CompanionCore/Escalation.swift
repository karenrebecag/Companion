import Foundation

/// Compact handoff from the conversational layer to a specialist.
/// A malformed or truncated `delegate` call must not escalate — the speaker
/// keeps talking whatever text it already has.
public struct Handoff: Sendable, Equatable {
    public var goal: String
    public var context: String

    public init(goal: String, context: String) {
        self.goal = goal
        self.context = context
    }

    public static func parse(toolName: String, arguments: String) -> Handoff? {
        guard toolName == "delegate" else { return nil }
        guard let data = arguments.data(using: .utf8) else { return nil }
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else { return nil }
            obj = parsed
        } catch {
            return nil
        }
        guard let goal = (obj["goal"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !goal.isEmpty
        else { return nil }
        let context = (obj["context"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Handoff(goal: goal, context: context)
    }
}

public enum Escalation: Sendable {
    /// Copy for both languages lives in EscalationCopy.swift; this file is
    /// the shape of a handoff, not its wording.

    public static func jobPrompt(
        _ h: Handoff, workdir: String, desktop: String,
        attachments: [String] = [], language: AppLanguage = .en
    ) -> String {
        let l = jobLabels(language)
        var out = "\(l.job): \(h.goal)\n"
        if !h.context.isEmpty { out += "\(l.context): \(h.context)\n" }
        out += "\(l.workdir): \(workdir)\n"
        out += "\(l.desktop): \(desktop)"
        if !attachments.isEmpty {
            out += "\n" + l.attachments
            for path in attachments { out += "\n- \(path)" }
        }
        return out
    }

    public static func executorPrompt(
        _ h: Handoff, original: String, workdir: String, desktop: String,
        language: AppLanguage = .en
    ) -> String {
        let l = jobLabels(language)
        var out: String
        switch language {
        case .en:
            out = "Companion is handing you work. You have the tools; she "
                + "only spoke with the user.\n"
        case .es:
            out = "Companion te pasa trabajo. Tú tienes las herramientas; "
                + "ella solo habló con el usuario.\n"
        }
        out += "\(l.job): \(h.goal)\n"
        if !h.context.isEmpty { out += "\(l.context): \(h.context)\n" }
        out += "\(l.workdir): \(workdir)\n"
        out += "\(l.desktop): \(desktop)\n"
        switch language {
        case .en:
            out += "Original request: «\(original)»\n"
            out += "Do the work (files, commands, a plan). A full answer for "
            out += "a screen. Start with a one-line summary; the voice reads "
            out += "only that opening."
        case .es:
            out += "Petición original: «\(original)»\n"
            out += "Haz el trabajo (archivos, comandos, plan). Respuesta "
            out += "completa para pantalla. Empieza con un resumen de una "
            out += "línea; la voz lee solo ese arranque."
        }
        return out
    }

    public static func voiceTurnPrompt(
        _ text: String, firstTurn: Bool, language: AppLanguage = .en
    ) -> String {
        firstTurn ? voicePreamble(language) + text : text
    }
}
