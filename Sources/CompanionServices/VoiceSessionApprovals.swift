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
    /// ask. The sheet shows the request and nobody is told out loud, so a
    /// spoken "yes" to it asks for the click (`SpokenYes`). The price, chosen:
    /// a request nobody looks at dies in the auto-deny (ApprovalTiming).
    func noteApproval(_ request: ApprovalRequest) async {
        pendingApproval = request
        pendingApprovalSeen = ApprovalSighting(requestId: request.requestId)
    }

    /// The voice has said the question of `requestId` (review 16h-2 round
    /// 3): the one moment a later hold's "yes" can be an answer to it.
    /// Nothing calls this today: by the product decision of 2026-08-22 the
    /// voice does not ask, so every spoken yes asks for the click. It is
    /// the seam the day the voice asks again.
    func approvalAnnounced(_ requestId: String) {
        if pendingApprovalSeen?.requestId == requestId { pendingApprovalSeen?.announcedAt = now() }
    }

    private func spokenYesAdmitted(_ seen: ApprovalSighting?) -> Bool {
        SpokenYes.admits(
            realtime: machine.snapshot.pipeline == .realtime,
            announcedAt: seen?.announcedAt, holdStartedAt: timeline.pressed)
    }

    /// The model turned the user's spoken answer into a decision. Nothing
    /// pending means the sheet already answered it (or the model invented the
    /// call): resolving anyway would grant a permission nobody asked about.
    func answerPendingApproval(_ approved: Bool) async -> SpokenApproval {
        // An MCP approval outranks a job approval: it arrived through the
        // live session the user is answering into.
        // HACK: MCP approvals keep the spoken path they had before 16h-2 —
        // realtime has no sheet for them, and refusing the spoken yes left
        // them unapprovable and hanging on the server. Upgrade trigger: when
        // a sheet exists for MCP approvals (or Karen picks an explicit "no"),
        // route this branch through `SpokenYes.admits` like the job's.
        if let mcp = pendingMCPApproval {
            pendingMCPApproval = nil
            await realtime.send(RealtimeCodec.mcpApprovalResponse(
                requestId: mcp.requestId, approve: approved))
            await realtime.requestResponse()
            return .resolved
        }
        guard let pending = pendingApproval else {
            Log.app("voice: approval answered with nothing pending")
            return .nothingPending
        }
        // Refusing is the safe direction: a spoken "no" resolves without a
        // click, whoever asked. Only a "yes" has to prove it is the user's.
        if approved { guard admitsSpokenYes(to: pending) else { return .needsClick } }
        pendingApproval = nil
        // Not resolved here: the answer goes to the session reducer, which
        // resolves what the sheet shows (the first of its queue) with the
        // sheet's rules. Two notions of "pending" let a spoken yes grant a
        // request nobody was looking at (security review 2026-09-06).
        eventBox.yield(.approvalSpoken(approved: approved))
        return .resolved
    }

    private func admitsSpokenYes(to pending: ApprovalRequest) -> Bool {
        // F-D (security review 16k-3): `resolve_approval` is a call the
        // MODEL makes — and a connected app's read output is words an
        // attacker can plant in front of that model. An app write approved
        // by a "spoken yes" the user never spoke would be the injection's
        // whole payoff, so app writes take the sheet's click, always.
        if pending.toolName.hasPrefix(ApprovalCopy.appToolPrefix) {
            Log.app("voice: app write approvals need the sheet, not resolve_approval")
            return false
        }
        // 16h-2 (security M1, round 3): with the voice free while a job
        // runs, a "yes" in a new turn may answer something else.
        guard spokenYesAdmitted(pendingApprovalSeen) else {
            Log.app("voice: spoken approval refused: not announced before this hold")
            return false
        }
        return true
    }
}
