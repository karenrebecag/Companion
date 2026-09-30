import Foundation

/// Security review 2026-09-25 (HIGH-1): a goal object written in the reply
/// TEXT is not a `delegate` call. The model may be reading back what the
/// user copied or what a page said, so a content goal is either an echo of
/// this turn's perceived input (dropped) or a proposal the user approves
/// through the same seam as any other permission.
public enum HandoffProposal {
    /// True when `goal`, normalized, occurs inside any source. An empty goal
    /// is never an echo: there is nothing to attribute.
    public static func isEcho(goal: String, in sources: [String]) -> Bool {
        let needle = normalize(goal)
        guard !needle.isEmpty else { return false }
        return sources.contains { normalize($0).contains(needle) }
    }

    /// Every field of the turn's context that came from outside the user's
    /// own words.
    public static func echoSources(_ context: TurnContext?) -> [String] {
        guard let context else { return [] }
        var sources: [String] = []
        if let app = context.focusedApp { sources.append(app) }
        sources += context.openDocuments
        if let clipboard = context.clipboard { sources.append(clipboard.preview) }
        if let summary = context.screenSummary { sources.append(summary) }
        sources += context.screenSnippets.map(\.text)
        return sources
    }

    /// The permission the sheet shows. `toolName` stays `delegate`, which
    /// has no `ApprovalKey`: "remember" can never turn one proposal into a
    /// standing grant for the next.
    public static func request(for handoff: Handoff, id: String) -> ApprovalRequest {
        let payload: [String: String] = ["goal": handoff.goal, "context": handoff.context]
        let input: String
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            input = String(decoding: data, as: UTF8.self)
        } catch {
            input = "{}"
        }
        return ApprovalRequest(
            requestId: id, toolName: "delegate", summary: handoff.goal, inputJSON: input)
    }

    /// Own words, never the model's: the question cannot carry injected text.
    public static func question(_ language: AppLanguage) -> String {
        switch language {
        case .es: return "¿Lo delego?"
        case .en: return "Delegate that?"
        }
    }

    /// Case- and diacritic-folded, every whitespace run one space, trimmed:
    /// the model rarely reads injected text back byte for byte.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
