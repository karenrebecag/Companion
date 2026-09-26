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
        attachments: [String] = [], language: AppLanguage = .en,
        skills: String = ""
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
        // The catalog closes the job (Wave 11a): paths to read_file, so the
        // specialist opens the skill the parent named instead of guessing it.
        if !skills.isEmpty { out += "\n" + skills }
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
}

/// Code review 2026-09-25 (HIGH-B): what the end of a job tells the voice.
/// Realtime hands the model `instruction`, a system item it answers in its
/// own words. Classic has no model on the other side of the synthesizer, so
/// it says `spokenLine` (ours, fixed) and asks the hold brain to summarize
/// `summarySource` in a turn of its own — the instruction is never spoken.
public struct JobAnnouncement: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case queued
        case done(result: String)
        case failed(reason: String)
    }

    public var goal: String
    public var outcome: Outcome
    public var language: AppLanguage

    public init(goal: String, outcome: Outcome, language: AppLanguage) {
        self.goal = goal
        self.outcome = outcome
        self.language = language
    }

    public var instruction: String {
        switch outcome {
        case .queued: return Escalation.queuedAnnouncement(goal, language)
        case .done: return Escalation.jobDoneAnnouncement(goal, language)
        case .failed(let reason):
            return Escalation.jobFailedAnnouncement(
                goal, reason: Escalation.resultSummary(reason), language)
        }
    }

    public var spokenLine: String {
        switch outcome {
        case .queued: return Escalation.jobQueuedSpoken(language)
        case .done: return Escalation.jobDoneSpoken(language)
        case .failed: return Escalation.jobFailedSpoken(language)
        }
    }

    /// What the summarizing turn reads; nil when there is nothing to add.
    public var summarySource: String? {
        let text: String
        switch outcome {
        case .queued: return nil
        case .done(let result): text = result
        case .failed(let reason): text = reason
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
