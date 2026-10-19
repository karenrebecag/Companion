import Foundation

/// What the router made of one turn. In Core so the typed chat, which
/// cannot see the gate, reads the same outcome the hold does.
package enum DecisionOutcome: Sendable, Equatable {
    case passThrough(DecisionPassReason)
    case acted(ParentToolOutcome, ToolCallRef)
    case confirm(String)
    case declined
    case delegate(Handoff)
    /// The router's own line about the running job: what it stopped, or
    /// the question it asks back.
    case said(String)
    /// A yes to "should I stop what I'm doing?": stop this job, and only it.
    case stopJob(JobID, goal: String)
    /// A no to that question: the job goes on and the words that raised it
    /// reach the brain as she said them.
    case carryOn(String)
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

/// What typed text the router may judge at all. Pasted code, an email or a
/// long paragraph is never a short command, and judging it would send all of
/// it to the hosted judge (Karen, 2026-10-19: no setting, a shape rule). Two
/// hundred characters holds any order the router can carry out.
package enum TypedCommand {
    package static let maxLength = 200

    package static func mayBeJudged(_ text: String) -> Bool {
        text.count <= maxLength && !text.contains(where: \.isNewline)
    }
}

/// The typed chat's door to the same router the voice hold goes through.
package protocol TurnDeciding: Sendable {
    func decide(_ utterance: String, canDelegate: Bool) async -> TypedDecision
    /// Drops the question still waiting for a yes/no, unanswered.
    func dropOpenQuestion() async
}
