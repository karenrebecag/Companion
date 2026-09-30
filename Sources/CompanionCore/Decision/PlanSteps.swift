import Foundation

/// One step of what the user asked for. A `Plan` names a single action; the
/// rest of a compound request ("...and tell me what is in the first note")
/// is a question the router cannot answer by acting.
package enum PlanStep: Sendable, Equatable {
    case act(DecisionAction)
    case read
}

extension Plan {
    /// The action, then a read step when a later clause asks to be told
    /// something. Only reads add steps: "open Notes and Safari" or "open it
    /// and close it" is still one routed action, as before.
    package var steps: [PlanStep] {
        guard action != .none else { return [] }
        return [.act(action)] + (CompoundRequest.asksToRead(utterance) ? [.read] : [])
    }
}

package enum CompoundRequest: Sendable {
    /// Folded, matched at the start of a clause. Whole phrases, not bare
    /// "cual" or "what": "abre Spotify y cual quieras" asks for nothing back.
    private static let readLeads = [
        "dime", "digame", "cuentame", "lee ", "leeme", "muestrame", "que hay", "que dice",
        "cual es", "cuales son", "cual fue", "que pide", "que tiene", "tell me", "read ",
        "show me", "what is", "what's", "whats", "what does", "what are", "what do",
        "what did", "what was", "let me know",
    ]

    private static let clauseBreaks = [" y ", " and ", ", ", " luego ", " then ", " despues ", " after that "]

    /// A read in any clause of a request with more than one: the router can
    /// act, but only the model can also answer.
    package static func asksToRead(_ utterance: String) -> Bool {
        var clauses = [CandidateSets.fold(utterance)]
        for mark in clauseBreaks {
            clauses = clauses.flatMap { $0.components(separatedBy: mark) }
        }
        guard clauses.count > 1 else { return false }
        return clauses.contains { clause in
            let lead = clause.trimmingCharacters(in: .whitespacesAndNewlines)
            return readLeads.contains { lead.hasPrefix($0) }
        }
    }
}
