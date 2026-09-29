import CompanionCore
import Foundation

/// The two permission channels a live session answers into: a job's
/// approval and an MCP tool's (both close on the sheet's click). Split out of VoiceSession when it crossed the
/// 400-line gate. What they touch is not `private` any more but still
/// actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    /// The user's own MCP server asks to run a tool. It joins the same sheet
    /// as every other permission: the model reads the request aloud but its
    /// boolean settles nothing (Wave 20c D2).
    func noteMCPApproval(_ request: ApprovalRequest) async {
        let id = request.requestId
        pendingMCPApprovals[id] = request
        let timeout = mcpApprovalTimeout
        mcpApprovalTimers[id] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeout))
            } catch {
                return
            }
            await self?.mcpApprovalExpired(id)
        }
        eventBox.yield(.job(.approvalRequested(request)))
    }

    /// Nobody clicked in time. The sheet's own ring empties without closing
    /// it and these requests never enter `Approvals`, so the deny is driven
    /// here: OpenAI must not wait for ever, and the sheet must not outlive
    /// the answer.
    private func mcpApprovalExpired(_ requestId: String) async {
        guard pendingMCPApprovals[requestId] != nil else { return }
        await approvalClosed(requestId, approved: false)
        eventBox.yield(.approvalDropped(requestId: requestId))
    }

    /// The session ended: its request ids die with the connection, so a late
    /// click must find nothing to answer, and no sheet may outlive them.
    func dropPendingMCPApprovals() {
        let ids = Array(pendingMCPApprovals.keys)
        pendingMCPApprovals = [:]
        for timer in mcpApprovalTimers.values { timer.cancel() }
        mcpApprovalTimers = [:]
        for id in ids { eventBox.yield(.approvalDropped(requestId: id)) }
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
        guard let pending = pendingApproval else {
            Log.app("voice: approval answered with nothing pending")
            return false
        }
        // Wave 20c D1 (supersedes F-D's `app:` prefix denylist): the model
        // makes this call and any text it reads can plant the yes, so only
        // low-risk requests are its to settle. Everything else, the
        // bridge's hands included, waits for the sheet's click.
        guard ApprovalRisk.of(toolName: pending.toolName) == .low else {
            Log.app("voice: \(pending.toolName) needs the sheet, not resolve_approval")
            return false
        }
        // HACK: the model's boolean is trusted for low-risk requests; the
        // heard words (`SpokenConfirmation.reading`) are not compared to it
        // because the transcript arrives on a different path than the tool
        // call and may lag it. Upgrade trigger: the first low-risk tool that
        // spends money or leaves the Mac, or the transcript reaching this
        // actor with the call.
        pendingApproval = nil
        // Not resolved here: the reducer resolves this exact request only if
        // the sheet is showing it, with the sheet's rules. Two notions of
        // "pending" let a spoken yes grant a request nobody was looking at
        // (security review 2026-09-06).
        eventBox.yield(.approvalSpoken(requestId: pending.requestId, approved: approved))
        return true
    }

    /// The sheet closed this request (click, drop, settled elsewhere): a note
    /// for it must not be answerable any more.
    ///
    /// An MCP request is answered here, with the sheet's verdict: no verdict
    /// (dropped, settled elsewhere) is a no, so OpenAI never waits forever.
    public func approvalClosed(_ requestId: String, approved: Bool? = nil) async {
        if pendingApproval?.requestId == requestId { pendingApproval = nil }
        mcpApprovalTimers.removeValue(forKey: requestId)?.cancel()
        if pendingMCPApprovals.removeValue(forKey: requestId) != nil {
            await realtime.send(RealtimeCodec.mcpApprovalResponse(
                requestId: requestId, approve: approved ?? false))
            await realtime.requestResponse()
        }
    }
}
