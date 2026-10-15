import Foundation

/// How QA mode settles an approval that would otherwise open a sheet (puente
/// QA, D5). Pure: the gate that acts on it lives in Services.
package enum QAApprovalPolicy {
    package enum Decision: Sendable, Equatable {
        case act, ownerCheck, sheet
    }

    package enum Outcome: Sendable, Equatable {
        case granted
        case refused(code: String)
        case unavailable(code: String)
    }

    /// The session sheet stays a click even in QA: it grants the agent its
    /// reach, so an agent cannot be the one to answer it.
    package static func decide(band: ActionBand, tool: String) -> Decision {
        if tool == BridgePolicy.sessionApprovalTool { return .sheet }
        switch band {
        case .act, .confirm: return .act
        case .critical: return .ownerCheck
        }
    }

    package static func outcome(for check: OwnerCheck) -> Outcome {
        switch check {
        case .confirmed: return .granted
        case .refused: return .refused(code: "owner_refused")
        case .unavailable: return .unavailable(code: "owner_unavailable")
        }
    }
}
