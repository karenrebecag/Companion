import Foundation

/// One number, two readers: the actor that denies on the deadline and the
/// sheet's countdown ring must agree, or the ring lies (19-1b).
package enum ApprovalTiming {
    /// 60, was 120: two minutes of ring read as forever (Karen, 19-1c).
    package static let autoDeny: TimeInterval = 60
}

/// The user's answer to a permission request. `remember` is the sheet's
/// toggle (Wave 10c 3B.3): keep this decision for the session.
package struct ApprovalResponse: Sendable, Equatable {
    package var requestId: String
    package var approved: Bool
    package var remember: Bool
    /// The deadline denied it, nobody answered: a caller that counts refusals
    /// (the bridge's cool-down) must not count silence as one.
    package var timedOut: Bool

    package init(requestId: String, approved: Bool, remember: Bool = false, timedOut: Bool = false) {
        self.requestId = requestId
        self.approved = approved
        self.remember = remember
        self.timedOut = timedOut
    }
}

/// Where a permission is asked and answered. In Core since Wave 10c: the
/// chat layer gates `open_url` through the same actor the specialist uses,
/// and the chat layer cannot see Services.
package protocol ApprovalsProvider: Sendable {
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse
    func resolve(requestId: String, approved: Bool) async -> Bool
    /// `remember` keeps the decision for the process's life, keyed by
    /// `ApprovalKey`. Providers without a memory take the default.
    func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool
    /// A decision already taken for this request's key, or nil to ask.
    func remembered(_ approval: ApprovalRequest) async -> Bool?
}

extension ApprovalsProvider {
    package func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved)
    }

    package func remembered(_ approval: ApprovalRequest) async -> Bool? { nil }
}

/// What the system's owner check answered. `unavailable` is not a refusal:
/// nobody said no, the machine cannot ask (no Touch ID and no password set).
package enum OwnerCheck: Sendable, Equatable {
    case confirmed, refused, unavailable
}

/// Proof that the person at the Mac, not a prompt or an agent, approves.
/// Core cannot import LocalAuthentication, so the adapter lives in Services.
package protocol OwnerVerifying: Sendable {
    /// Whether `verify` could show a dialog right now. Asking never shows one.
    func canVerify() async -> Bool
    /// Cancelling the calling task closes the dialog. Never returns
    /// `confirmed` unless the system confirmed this very call.
    func verify(reason: String) async -> OwnerCheck
}

/// What QA mode decided for one action that would have opened a sheet.
package enum QAVerdict: Sendable, Equatable {
    /// QA is off, or the action keeps its sheet (the session grant): the
    /// caller asks the way it always has.
    case notInQA
    case act
    case granted
    case refused(code: String)
    case unavailable(code: String)
    /// Another owner check is already on screen. Not a no from the owner.
    case busy
}

/// Puente QA D5: the one decision point in front of every sheet. Core owns
/// the port because the chat layer cannot see Services.
package protocol QAGating: Sendable {
    func decide(_ request: ApprovalRequest, call: ToolCallRef, said: String) async -> QAVerdict
    /// Whether QA mode could be turned on: the owner check can be shown.
    func canVerify() async -> Bool
}
