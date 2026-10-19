import CompanionCore
import Foundation

/// What the sheet shows first, as the reducer reported it; `requestId` nil
/// means the sheet is empty.
struct SheetFront: Sendable, Equatable {
    let requestId: String?
}

/// The two permission channels a live session answers into: a job's
/// approval and an MCP tool's (both close on the sheet's click). Split out of VoiceSession when it crossed the
/// 400-line gate. What they touch is not `private` any more but still
/// actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    /// 16q-1: a remote MCP tool's permission is a sheet, like the parent's
    /// gates: Allow / Deny, the auto-deny of `ApprovalTiming`, and the
    /// server hears the answer only once the user gave it. A spoken "yes"
    /// never approves it (`answerPendingApproval`): Incredible accepts one
    /// because a judge model checks the word, and Companion has no judge;
    /// and the model's boolean settles nothing here (20c D2).
    func noteMCPApproval(_ request: ApprovalRequest) async {
        // The id is the server's: one already waiting means a repeat or a
        // forgery. Fail closed: the original is refused (its own flow tells
        // the server, once) instead of two sheets sharing one answer.
        if let waiting = pendingMCPApprovals.first(where: { $0.requestId == request.requestId }) {
            Log.app("voice: duplicate MCP approval id; refusing it")
            await mcpGuard.withdraw(waiting)
            return
        }
        pendingMCPApprovals.append(request)
        let decision = await mcpGuard.decide(request)
        // Dropped with its session (20c D2): the id died with the connection,
        // so nothing is sent; the sheet only has to let go of it.
        let live = pendingMCPApprovals.contains { $0.requestId == request.requestId }
        pendingMCPApprovals.removeAll { $0.requestId == request.requestId }
        // Answered by a click, the auto-deny or a "no": whichever it was, the
        // sheet must not keep a request the server already heard about.
        eventBox.yield(.approvalSettled(requestId: request.requestId))
        guard live else { return }
        await realtime.send(RealtimeCodec.mcpApprovalResponse(
            requestId: request.requestId, approve: decision.approved))
        await realtime.requestResponse()
    }

    /// The session ended: its MCP request ids die with the connection, so a
    /// late click must find nothing to answer, and no sheet may outlive them
    /// (20c D2). Refused where the sheet's own answer would be, so the one
    /// decision point still closes each of them once.
    func dropPendingMCPApprovals() async {
        let dropped = pendingMCPApprovals
        pendingMCPApprovals = []
        for request in dropped { await mcpGuard.withdraw(request) }
    }

    /// The words the user said in the hold that just ended, as the ear heard
    /// them. What a spoken yes is checked against (security M3). Stamped with
    /// the press the hold STARTED with, not the live one: a hold cut by a new
    /// press reports late, and the live press would lend its words to the new
    /// hold. An empty report, or words of another hold, clear the last words
    /// so a yes cannot outlive its hold.
    func noteHeard(_ text: String, pressed: TimeInterval?) {
        guard !text.isEmpty, let pressed, pressed == timeline.pressed else {
            heardThisHold = nil
            return
        }
        heardThisHold = HeardInHold(text: text, pressed: pressed)
    }

    /// A request left the sheet by some road (click, stop, its job ended):
    /// the session forgets it, so a permission that no longer exists is
    /// neither announced nor answered (16q-1 review, security M2).
    package func approvalClosed(requestId: String) async {
        // Round 2 (C2): the close and the note that announced the request are
        // unordered tasks. Remembering the id makes a late note a no-op.
        // A repeat close would take a second slot and push a distinct id out.
        if !closedApprovals.contains(requestId) {
            closedApprovals.append(requestId)
            if closedApprovals.count > Self.closedApprovalCap {
                closedApprovals.removeFirst(closedApprovals.count - Self.closedApprovalCap)
            }
        }
        // The sheet changed: a yes said before it no longer answers it.
        heardThisHold = nil
        if pendingApproval?.requestId == requestId {
            pendingApproval = nil
            pendingApprovalSeen = nil
        }
        if parkedParentApproval == requestId { parkedParentApproval = nil }
    }

    /// A parent gate's sheet: armed and asked like a job's, and remembered as
    /// the parent's so a press over its question can answer it (2a). Realtime
    /// never asks and never holds an answer.
    func noteParentApproval(_ request: ApprovalRequest) async {
        if machine.snapshot.pipeline != .realtime, !closedApprovals.contains(request.requestId) {
            parkedParentApproval = request.requestId
        }
        await noteApproval(request)
        await askApprovalAloud(request)
    }

    /// Karen's D2 (P2): a press over a resting turn whose parent question was
    /// said answers the sheet instead of cutting the turn. A question not
    /// said yet is no question, and the press is the cut #87 made.
    var answerHoldArmed: Bool {
        guard machine.snapshot.sheetParked, let id = parkedParentApproval,
              livePendingApproval?.requestId == id,
              let seen = pendingApprovalSeen, seen.requestId == id, seen.announcedAt != nil
        else { return false }
        return true
    }

    /// The release of an answer hold. True when it settled the hold; false
    /// hands it back to the ordinary release (the sheet closed meanwhile).
    func answerParkedSheet(_ requestId: String) async -> Bool {
        guard machine.snapshot.sheetParked, livePendingApproval?.requestId == requestId else { return false }
        let generation = holdGeneration
        await classic.flushEarlyAudio()
        let words = await classic.stopEar().value.trimmingCharacters(in: .whitespacesAndNewlines)
        // A newer press owns the session now.
        guard generation == holdGeneration else { return true }
        noteHeard(words, pressed: timeline.pressed)
        guard words.isEmpty || SpokenYes.affirms(words) || SpokenNo.refuses(words) else {
            // No answer: these words are a turn of their own, and the new
            // turn cancels the parked one (#87), and gets the pin the press
            // held back.
            classic.parentTools?.beginTurn()
            classic.leftoverHeard = words
            commitTimeline()
            await apply(.holdReleased(hasSpeech: true))
            return true
        }
        screen?.cancel()
        classic.cancelPressedContext()
        if words.isEmpty { eventBox.yield(.heardNothing) }
        // Back at rest before anything answers: the click may land any time.
        await apply(.holdDiscarded)
        guard !words.isEmpty else { return true }
        if SpokenNo.refuses(words) {
            await refuseParkedSheet(requestId)
            return true
        }
        // The one place a spoken yes is judged, so a later decision about it
        // changes the rule there, not this path.
        if await answerPendingApproval(true) == .needsClick {
            await jobAnnounce(JobAnnouncement(
                goal: "", outcome: .needsClick, language: configProvider.current.language))
        }
        return true
    }

    /// D3: the voice's "no" goes the same single road as any spoken answer
    /// (`answerPendingApproval`). The mark comes first so the round the
    /// refusal wakes ends on the "no" line; a no the sheet did not take
    /// refused nothing and takes its mark back.
    // HACK: a click on Deny that the reducer applies instead of the spoken
    // no (which it then drops) is heard as the voice's: same refusal, only
    // the line and the model's round differ. A click to Allow there is the
    // click's, since the round only counts a sheet that ended refused.
    // Upgrade trigger: the sheet reporting who answered it.
    private func refuseParkedSheet(_ requestId: String) async {
        // The ear's awaits ran after the press was armed: the sheet may be
        // another request by now, and this no was not about it.
        guard livePendingApproval?.requestId == requestId else { return }
        // `answerPendingApproval` answers an MCP request first: this no was
        // said to the parent's question, so it is spent on neither.
        guard pendingMCPApprovals.isEmpty else {
            await jobAnnounce(JobAnnouncement(
                goal: "", outcome: .needsClick, language: configProvider.current.language))
            return
        }
        classic.noteRefusedByVoice(requestId)
        switch await answerPendingApproval(false) {
        case .resolved:
            return
        case .needsClick:
            classic.forgetRefusedByVoice(requestId)
            await jobAnnounce(JobAnnouncement(
                goal: "", outcome: .needsClick, language: configProvider.current.language))
        case .nothingPending:
            classic.forgetRefusedByVoice(requestId)
        }
    }

    /// The reducer's report of what the sheet shows (C2): a spoken answer
    /// for any other request would be dropped there.
    package func approvalFront(requestId: String?) async {
        sheetFront = SheetFront(requestId: requestId)
    }

    /// The pending job request, unless it died on the actor's deadline: the
    /// auto-deny tells nobody here, so it expires by the same clock.
    var livePendingApproval: ApprovalRequest? {
        guard let pending = pendingApproval else { return nil }
        if let seen = pendingApprovalSeen, seen.requestId == pending.requestId,
           now() - seen.shownAt >= ApprovalTiming.autoDeny {
            pendingApproval = nil
            pendingApprovalSeen = nil
            return nil
        }
        return pending
    }

    /// The permission the specialist is blocked on. One at a time: the job
    /// queue is serial, so a new request means the previous one is settled.
    ///
    /// Only arms the request: the sheet shows it and `askApprovalAloud` says
    /// the question in classic. Until the voice has said it (`approvalAnnounced`)
    /// a spoken "yes" asks for the click (`SpokenYes`), and a request nobody
    /// looks at dies in the auto-deny (ApprovalTiming).
    func noteApproval(_ request: ApprovalRequest) async {
        guard !closedApprovals.contains(request.requestId) else { return }
        // A new request is a new question: the last words answered another.
        heardThisHold = nil
        pendingApproval = request
        pendingApprovalSeen = ApprovalSighting(requestId: request.requestId, shownAt: now())
    }

    /// 16q-1 (audit decision 3): in classic the voice asks a job's permission
    /// in one short sentence and the card carries the detail; the yes is
    /// then the click's or, through `SpokenYes`, a spoken one in a later
    /// hold. The sentence is ours and fixed: nothing from the request is
    /// spoken, so a tool's payload cannot put words in the voice's mouth.
    /// Realtime does not ask (a spoken yes never counts there).
    func askApprovalAloud(_ request: ApprovalRequest) async {
        guard machine.snapshot.pipeline != .realtime,
              !closedApprovals.contains(request.requestId) else { return }
        await jobAnnounce(JobAnnouncement(
            goal: request.summary, outcome: .asking(requestId: request.requestId),
            language: configProvider.current.language))
    }

    /// The voice has said the question of `requestId` (review 16h-2 round
    /// 3): the one moment a later hold's "yes" can be an answer to it.
    /// Called when the audio of a classic job's permission question ends
    /// (16q-1; the product decision of 2026-08-22 that the voice does not ask
    /// was reversed for classic on 2026-09-29, when Karen approved matching
    /// Incredible). Realtime never calls it.
    func approvalAnnounced(_ requestId: String) {
        if pendingApprovalSeen?.requestId == requestId { pendingApprovalSeen?.announcedAt = now() }
    }

    /// The words, only if they were said in the hold now answering.
    private var heardOfThisHold: String? {
        guard let heard = heardThisHold, heard.pressed == timeline.pressed else { return nil }
        return heard.text
    }

    private func spokenYesAdmitted(_ seen: ApprovalSighting?) -> Bool {
        SpokenYes.admits(
            realtime: machine.snapshot.pipeline == .realtime,
            announcedAt: seen?.announcedAt, holdStartedAt: timeline.pressed, heard: heardOfThisHold)
    }

    /// The model turned the user's spoken answer into a decision. Nothing
    /// pending means the sheet already answered it (or the model invented the
    /// call): resolving anyway would grant a permission nobody asked about.
    func answerPendingApproval(_ approved: Bool) async -> SpokenApproval {
        // An MCP approval outranks a job approval: it arrived through the
        // live session the user is answering into. It only exists in
        // realtime, where `SpokenYes` is always false, so a yes is the
        // click's and only a no resolves here (16q-1).
        if let mcp = pendingMCPApprovals.last {
            guard !approved else {
                Log.app("voice: MCP approvals need the sheet, not resolve_approval")
                return .needsClick
            }
            // The newest one: the request the model just asked about. Refused
            // where the sheet's own answer would be: the actor wakes
            // `noteMCPApproval`, which tells the server and clears the sheet.
            // Any older one stays on the sheet for its own click.
            // It is listed before the actor parks it: a "no" in that window
            // refused nothing, and the model must not say it did.
            guard await mcpGuard.withdraw(mcp) else {
                Log.app("voice: spoken no for an MCP request not parked yet; needs the sheet")
                return .needsClick
            }
            return .resolved
        }
        guard let pending = livePendingApproval else {
            Log.app("voice: approval answered with nothing pending")
            return .nothingPending
        }
        // C2: the reducer drops an answer for a request the sheet is not
        // showing. Yes or no, it takes the click; the request stays armed
        // for when it reaches the front.
        if let front = sheetFront, front.requestId != pending.requestId {
            Log.app("voice: spoken answer for a request the sheet is not showing; needs the click")
            return .needsClick
        }
        // Refusing is the safe direction: a spoken "no" resolves without a
        // click, whoever asked. Only a "yes" has to prove it is the user's.
        if approved { guard admitsSpokenYes(to: pending) else { return .needsClick } }
        pendingApproval = nil
        // Not resolved here: the answer goes to the session reducer, which
        // resolves this exact request, only while the sheet shows it, with
        // the sheet's rules. Two notions of "pending" let a spoken yes grant a
        // request nobody was looking at (security review 2026-09-06).
        eventBox.yield(.approvalSpoken(requestId: pending.requestId, approved: approved))
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
        // Q1 D1 (a): a parent's sheet takes the click whatever its risk, so
        // the risk list can never be what lets a voice approve one. An ADR
        // that changes that changes this guard.
        guard pending.requestId != parkedParentApproval else {
            Log.app("voice: a parent sheet needs the click, not a spoken yes")
            return false
        }
        // 20c D1: only a request whose worst case is small is the voice's to
        // settle, whatever was said. Allowlist: a tool nobody classified, the
        // bridge's hands, a write or a browser action takes the click.
        guard ApprovalRisk.of(toolName: pending.toolName) == .low, !pending.isMCP else {
            Log.app("voice: a request above low risk needs the sheet, not resolve_approval")
            return false
        }
        // 16h-2 (security M1, round 3): with the voice free while a job
        // runs, a "yes" in a new turn may answer something else.
        guard spokenYesAdmitted(pendingApprovalSeen) else {
            Log.app("voice: spoken approval refused: not announced, or not a yes she said")
            return false
        }
        // No reset of the words here: the caller clears `pendingApproval`, and the
        // only way to arm another request is `noteApproval`, which clears them.
        return true
    }
}
