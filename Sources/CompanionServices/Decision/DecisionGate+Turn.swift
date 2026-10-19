import CompanionCore
import Foundation

/// Where one turn's words went: answered as a yes/no to the open question,
/// or planned as a fresh order that `run` still has to carry out.
package enum TurnRoute: Sendable {
    case answered(DecisionOutcome)
    case planned(DecisionStep)
}

/// The turn-level decision a hold and a typed message share, so the two
/// paths cannot drift on what a "sí" answers or when the head is asked.
extension DecisionGate {
    /// An open question answers from these words before any plan sees
    /// them: a "sí" must never be reclassified as a fresh order. A plan
    /// prepared for the same words is dropped when the question takes them.
    /// `typed` reads the answer as a whole typed message, not a spoken one.
    package func route(
        _ utterance: String, canDelegate: Bool, budget: Duration?,
        provider: (any DecisionProvider)?, prepared: Task<DecisionStep, Never>? = nil,
        typed: Bool = false
    ) async -> TurnRoute {
        if let answered = await answerConfirmation(utterance, typed: typed) {
            prepared?.cancel()
            return .answered(answered)
        }
        return .planned(await plan(
            utterance, canDelegate: canDelegate, budget: budget, provider: provider, prepared: prepared))
    }

    /// The delegation head for these words, started now so it overlaps the
    /// router. Checked and started inside one actor turn: a yes/no to an
    /// open question is answered on the Mac and never goes out to be judged
    /// a second time, even when the route clears the question right after.
    package func delegationVerdict(
        _ utterance: String, judge: DecisionJudge, typed: Bool = false
    ) -> Task<DecisionAnswer?, Never>? {
        guard !answersPendingConfirmation(utterance, typed: typed) else { return nil }
        return Task { await judge.delegationVerdict(utterance) }
    }

    /// Why the router does not run this turn, or nil when it does. A hosted
    /// judge passes both: the toggle is about running a local model, and
    /// the fast-brain skip (15c-4/15c-7: Cerebras already picked the tool by
    /// commit; N1's cascade added up to 0.9 s and never won a hold against
    /// it, wave-15c §1) was measured against the local 4B, not Jev.
    package static func skip(hosted: Bool, enabled: Bool, fastBrain: Bool) -> DecisionPassReason? {
        if hosted { return nil }
        guard enabled else { return .disabled }
        return fastBrain ? .fastBrain : nil
    }
}
