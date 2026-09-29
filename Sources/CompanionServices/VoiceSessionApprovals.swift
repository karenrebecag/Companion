import CompanionCore
import Foundation

/// The two permission channels a live session answers into: a job's
/// approval and an MCP tool's. Split out of VoiceSession when it crossed the
/// 400-line gate. What they touch is not `private` any more but still
/// actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    func noteMCPApproval(_ request: ApprovalRequest) async {
        pendingMCPApproval = request
    }

    /// The permission the specialist is blocked on. One at a time: the job
    /// queue is serial, so a new request means the previous one is settled.
    ///
    /// Deliberately silent: a job is assistive UI and does not interrupt to
    /// ask. The sheet shows the request; `resolve_approval` stays declared so
    /// a spoken "yes" still lands, but nobody is told out loud. The price,
    /// chosen: a request nobody looks at dies in the auto-deny (ApprovalTiming).
    func noteApproval(_ request: ApprovalRequest) async {
        pendingApproval = request
    }

    /// The model turned the user's spoken answer into a decision. Nothing
    /// pending means the sheet already answered it (or the model invented the
    /// call): resolving anyway would grant a permission nobody asked about.
    func answerPendingApproval(_ approved: Bool) async -> Bool {
        // An MCP approval outranks a job approval: it arrived through the
        // live session the user is answering into.
        if let mcp = pendingMCPApproval {
            pendingMCPApproval = nil
            await realtime.send(RealtimeCodec.mcpApprovalResponse(
                requestId: mcp.requestId, approve: approved))
            await realtime.requestResponse()
            return true
        }
        guard let pending = pendingApproval else {
            Log.app("voice: approval answered with nothing pending")
            return false
        }
        // F-D (security review 16k-3): `resolve_approval` is a call the
        // MODEL makes — and a connected app's read output is words an
        // attacker can plant in front of that model. An app write approved
        // by a "spoken yes" the user never spoke would be the injection's
        // whole payoff, so app writes take the sheet's click, always.
        if pending.toolName.hasPrefix(ApprovalCopy.appToolPrefix) {
            Log.app("voice: app write approvals need the sheet, not resolve_approval")
            return false
        }
        pendingApproval = nil
        // Not resolved here: the answer goes to the session reducer, which
        // resolves what the sheet shows (the first of its queue) with the
        // sheet's rules. Two notions of "pending" let a spoken yes grant a
        // request nobody was looking at (security review 2026-09-06).
        eventBox.yield(.approvalSpoken(approved: approved))
        return true
    }
}
