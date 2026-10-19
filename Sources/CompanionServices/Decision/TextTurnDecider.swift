import CompanionCore
import Foundation

/// The typed chat's turn through the same gate, judge and head the hold
/// uses. One judge pin per message: there is no second seam to share it
/// with, and a key saved mid-message counts from the next one. No
/// speculation: a typed message arrives whole.
package struct TextTurnDecider: TurnDeciding {
    /// The head's verdict is waited for this long after the router passes,
    /// the same wait the hold gives it once its context is in.
    package static let delegationWait: Duration = .milliseconds(300)

    private let gate: DecisionGate
    private let judge: DecisionJudge
    private let config: any ConfigProviding

    package init(gate: DecisionGate, judge: DecisionJudge, config: any ConfigProviding) {
        self.gate = gate
        self.judge = judge
        self.config = config
    }

    package func decide(_ utterance: String, canDelegate: Bool) async -> TypedDecision {
        let turn = judge.pinned()
        let current = config.current
        let verdict = canDelegate ? await gate.delegationVerdict(utterance, judge: turn) : nil
        defer { verdict?.cancel() }
        let hosted = turn.usesHostedJudge
        let outcome: DecisionOutcome
        if let skipped = DecisionGate.skip(
            hosted: hosted, enabled: current.decision.enabled, fastBrain: false) {
            outcome = .passThrough(skipped)
        } else {
            switch await gate.route(
                utterance, canDelegate: canDelegate,
                budget: hosted ? current.decision.hostedBudget : nil, provider: turn) {
            case .answered(let answered):
                outcome = answered
            case .planned(let step):
                outcome = await gate.run(step, utterance: utterance, language: current.language)
            }
        }
        guard case .passThrough = outcome, canDelegate else {
            return TypedDecision(outcome: outcome, withdrawsDelegate: false)
        }
        let answer = await DecisionJudge.verdict(verdict, within: Self.delegationWait)
        return TypedDecision(
            outcome: outcome,
            withdrawsDelegate: !DelegationHead.offersDelegate(utterance: utterance, answer))
    }
}
