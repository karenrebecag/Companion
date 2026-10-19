import Foundation

/// What the router made of one turn. In Core so the typed chat, which
/// cannot see the gate, reads the same outcome the hold does.
package enum DecisionOutcome: Sendable, Equatable {
    case passThrough(DecisionPassReason)
    case acted(ParentToolOutcome, ToolCallRef)
    case confirm(String)
    case declined
    case delegate(Handoff)
}

/// A typed message's turn, decided: the outcome, and whether the delegation
/// head took `delegate` off the brain's tools for a pass-through.
package struct TypedDecision: Sendable, Equatable {
    package var outcome: DecisionOutcome
    package var withdrawsDelegate: Bool

    package init(outcome: DecisionOutcome, withdrawsDelegate: Bool) {
        self.outcome = outcome
        self.withdrawsDelegate = withdrawsDelegate
    }
}

/// The typed chat's door to the same router the voice hold goes through.
package protocol TurnDeciding: Sendable {
    func decide(_ utterance: String, canDelegate: Bool) async -> TypedDecision
}
