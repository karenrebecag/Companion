import Foundation

/// The session reducer (Wave 12a). Pure: `handle(event) -> [Effect]`. It
/// owns `SessionProjection.kind`; nothing else writes it. The voice machine
/// keeps deciding how to capture and play; this one translates its snapshots
/// into chrome and adds what the voice cannot see: typed turns, the parent's
/// hands, the specialist's job and the sheet.
public struct SessionMachine: Sendable, Equatable {
    public private(set) var projection = SessionProjection()
    /// Seconds Completed stays on screen before Idle.
    public static let completedDelay: TimeInterval = 1.5
    /// Seconds Pending waits for the voice to answer before giving up.
    public static let pendingTimeout: TimeInterval = 12
    /// Seconds a hold session may rest, mic closed, before it hangs up. The
    /// software gate closes the ear, not the hardware: with the window gone
    /// nothing of ours showed the microphone was still taken (security
    /// review 2026-09-06). Long enough for the next hold to find it warm.
    public static let voiceIdleTimeout: TimeInterval = 20
    /// Seconds "didn't hear you" and the hold hint stay before leaving on
    /// their own, as Incredible's card does (spec 16c §2). A permission or
    /// a failure stays: it carries the way out.
    public static let noticeDelay: TimeInterval = 6

    private var voice = TurnSnapshot.idle
    private var typedBusy = false
    /// A job whose FIRST action you refuse is stopped whole (10c 3B.4).
    /// Counted on the job's own requests only: the parent's `open_url`
    /// gate shares the queue but is not the job's action (security review
    /// 2026-09-06).
    private var jobApprovedOnce = false
    /// The key is down but still under the tap threshold: the mic is open
    /// locally, nothing has left the machine and no reply has been cut.
    private var provisional = false

    public init() {}

    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        let before = projection.kind
        let wasRestingWarm = restingWarm
        projection.cards = []
        var effects: [SessionEffect] = []
        switch event {
        case .voice(let snapshot):
            effects += observe(snapshot)
        case .typedSubmitted:
            typedBusy = true
            begin()
            projection.kind = .processing(.thinking)
        case .typedReplyStreaming:
            if typedBusy, case .processing = projection.kind {
                projection.kind = .processing(.speaking)
            }
        case .typedReplyFinished:
            typedBusy = false
            effects += rest()
        case .parentActing(let targets):
            begin()
            projection.targets = targets
            projection.kind = .processing(.toolExecuting)
        case .parentActed:
            projection.targets = []
            effects += rest()
        case .job(let jobEvent):
            effects += observe(jobEvent)
        case .jobFinished:
            guard projection.job != nil else { return [] }
            projection.job = nil
            jobApprovedOnce = false
            effects += rest()
        case .approvalAnswered(let id, let approved, let remember):
            guard let request = remove(id) else { return [] }
            let ofJob = Self.isJobRequest(request) && projection.job != nil
            let stops = !approved && ofJob && !jobApprovedOnce
            if approved, ofJob { jobApprovedOnce = true }
            effects.append(.resolveApproval(
                requestId: id, approved: approved, remember: remember && !stops))
            if stops { effects += stop() }
        case .approvalSpoken(let approved):
            guard let first = projection.approval else { return [] }
            return handle(.approvalAnswered(
                requestId: first.requestId, approved: approved, remember: false))
        case .approvalSettled(let id):
            _ = remove(id)
        case .approvalDropped(let id):
            guard remove(id) != nil else { return [] }
            effects.append(.resolveApproval(requestId: id, approved: false, remember: false))
        case .hoverEntered:
            if projection.kind == .idle { projection.kind = .hover }
        case .hoverLeft:
            if projection.kind == .hover { projection.kind = .idle }
        case .completedTimerExpired:
            if projection.kind == .processing(.completed) {
                projection.kind = .idle
                projection.dictation = nil
            }
        case .pressed:
            begin()
            projection.holding = true
            projection.kind = .listening
            effects.append(.startListening)
        case .pressedProvisionally:
            begin()
            projection.holding = true
            provisional = true
            projection.kind = .listening
            effects.append(.startProvisionalListening)
        case .holdConfirmed:
            guard projection.holding, provisional else { return [] }
            provisional = false
            effects.append(.confirmListening)
        case .released:
            guard projection.holding else { return [] }
            projection.holding = false
            provisional = false
            projection.kind = .processing(.pending)
            effects += [.stopListening(commit: true), .schedulePendingExpiry(Self.pendingTimeout)]
        case .tapped:
            if projection.holding {
                projection.holding = false
                effects.append(.stopListening(commit: false))
            }
            projection.notice = .holdHint
            projection.cards = [.holdHint]
            projection.kind = restingKind()
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .holdCancelled:
            guard projection.holding else { return [] }
            projection.holding = false
            provisional = false
            effects.append(.stopListening(commit: false))
            projection.kind = replyOrRestingKind()
        case .heardNothing:
            projection.holding = false
            projection.notice = .couldntHear
            projection.cards = [.couldntHear]
            projection.kind = restingKind()
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .noticeExpired:
            if let notice = projection.notice, Self.fades(notice) { projection.notice = nil }
        case .pendingTimedOut:
            if projection.kind == .processing(.pending) { projection.kind = restingKind() }
        case .voiceIdleExpired:
            if restingWarm { effects.append(.hangUpVoice) }
        case .partialTranscript(let text):
            if projection.kind == .listening { projection.partial = text }
        case .dictating(let app):
            if projection.kind == .listening { projection.dictation = app }
        case .dictated(let app):
            guard projection.kind == .processing(.pending) else { return [] }
            projection.holding = false
            projection.dictation = app
            projection.kind = .processing(.completed)
            effects.append(.scheduleCompletedExpiry(Self.completedDelay))
        case .dictationFailed(let failure):
            // A notice, not a transition: the words are already on their
            // way to Companion and its turn owns the kind.
            let card = Self.card(for: failure)
            projection.notice = card
            projection.cards = [card]
        case .handsLent(let client):
            projection.handsLentTo = client
        case .handsActed:
            projection.handsPulse = (projection.handsPulse + 1) % 1_000
        case .stop:
            guard projection.kind != .idle else { return [] }
            if voice.state == .thinking || voice.state == .speaking {
                effects.append(.cancelVoiceOutput)
            }
            // Inside the release tail the voice still listens: the commit
            // has not left yet, and Esc must be what stops it.
            if projection.holding || inReleaseTail {
                effects.append(.stopListening(commit: false))
            }
            provisional = false
            effects += stop()
        }
        // The partial belongs to the hold and to the wait for its words;
        // any other phase has its own line.
        if projection.kind != .listening, projection.kind != .processing(.pending) {
            projection.partial = nil
        }
        // The dictation lives as long as its hold shows: the field while
        // listening, the paste while pending, the app's name in Completed.
        switch projection.kind {
        case .listening, .processing(.pending), .processing(.completed): break
        default: projection.dictation = nil
        }
        if restingWarm, !wasRestingWarm {
            effects.append(.scheduleVoiceIdleExpiry(Self.voiceIdleTimeout))
        }
        if projection.kind != before {
            effects.append(.logTransition(from: before, to: projection.kind))
        }
        return effects
    }

    /// A session a hold opened, resting with the mic closed and nothing of
    /// ours on screen that says the hardware is still taken. Hands-free
    /// muted from the window is not this: its button shows the state.
    private var restingWarm: Bool {
        guard voice.state == .listening, voice.muted, voice.holdArmed, !projection.holding
        else { return false }
        switch projection.kind {
        case .idle, .hover, .processing(.completed): return true
        default: return false
        }
    }

    private mutating func observe(_ snapshot: TurnSnapshot) -> [SessionEffect] {
        voice = snapshot
        projection.pipeline = snapshot.pipeline
        projection.voice = Self.status(of: snapshot)
        switch snapshot.state {
        case .connecting:
            break
        case .listening where snapshot.muted:
            // The voice is warm with the mic closed: the chrome rests, except
            // while Pending waits for the text just sent, or while a press
            // is still being served.
            if projection.kind == .processing(.pending) || projection.holding { break }
            if case .processing = projection.kind {
                return rest()
            }
            if projection.kind == .listening { projection.kind = .idle }
        case .listening:
            begin()
            projection.kind = .listening
        case .thinking:
            projection.kind = projection.job != nil
                ? .processing(.subAgentRunning) : .processing(.thinking)
        case .speaking:
            projection.kind = .processing(.speaking)
        case .idle:
            // Classic hold arms Speech while TurnMachine is still idle.
            // Clearing holding here dropped FN-up (live 2026-09-07).
            if projection.holding { break }
            projection.holding = false
            if projection.job != nil {
                projection.kind = .processing(.subAgentRunning)
            } else if !typedBusy, projection.kind != .processing(.completed) {
                projection.kind = .idle
            }
        case .error:
            // The failure is a reason and a card, not a mode: the voice may
            // sit in its own error state, the chrome goes back to rest.
            let failure = snapshot.failure ?? .sessionDropped
            projection.holding = false
            projection.interruption = .failure(failure)
            projection.notice = Self.card(for: failure)
            projection.cards = [Self.card(for: failure)]
            projection.kind = projection.job != nil
                ? .processing(.subAgentRunning) : .idle
            if Self.fades(Self.card(for: failure)) {
                return [.scheduleNoticeExpiry(Self.noticeDelay)]
            }
        }
        return []
    }

    private static func fades(_ notice: SessionCard) -> Bool {
        notice == .couldntHear || notice == .holdHint
    }

    /// Something new started: whatever the resting chrome was showing is
    /// over.
    private mutating func begin() {
        projection.interruption = nil
        projection.notice = nil
        projection.partial = nil
        projection.dictation = nil
    }

    /// Released, and the voice has not moved past listening yet.
    private var inReleaseTail: Bool {
        projection.kind == .processing(.pending) && voice.state == .listening
            && voice.holdArmed && !voice.muted
    }

    /// A press cancelled under the threshold never cut the reply, so the
    /// chrome goes back to it instead of painting Idle over a voice that
    /// is still talking.
    private func replyOrRestingKind() -> SessionKind {
        guard projection.job == nil else { return .processing(.subAgentRunning) }
        switch voice.state {
        case .thinking: return .processing(.thinking)
        case .speaking: return .processing(.speaking)
        default: return .idle
        }
    }

    /// Where a hold that produced nothing lands: the job's row if one runs,
    /// otherwise Idle straight away (no Completed for nothing).
    private func restingKind() -> SessionKind {
        projection.job != nil ? .processing(.subAgentRunning) : .idle
    }

    private mutating func observe(_ event: JobEvent) -> [SessionEffect] {
        switch event {
        case .started(let goal):
            if projection.job == nil {
                projection.job = JobTimeline(goal: goal)
                jobApprovedOnce = false
            } else {
                // A second announcement only names the job; its approvals
                // so far still count.
                projection.job?.goal = goal
            }
            begin()
            projection.kind = .processing(.subAgentRunning)
        case .stepStarted(let tool, let summary):
            append(JobTimeline.step(tool, summary))
        case .stepFinished:
            // One row per tool use: the next step starting is what "done"
            // looks like.
            break
        case .thought(let text):
            append(JobStepInfo(tool: JobSteps.Thinking.tool, label: text))
        case .approvalRequested(let request):
            // After a Stop, and before anything new starts, a request can
            // only come from the job that was just stopped: it dies with it
            // instead of reopening the sheet (security review 2026-09-06).
            // The bridge's session grant is the one exception: it comes from
            // a NEW connection, never from the stopped child, and Stop's
            // stale `userStopped` (cleared only when a turn opens) was
            // silently denying every grant at rest — no sheet, no user
            // (seen live 2026-09-28). Surfacing it keeps the user, not the
            // ghost of the last Stop, as the authority. The exemption leans
            // on a convention: this name is minted only in
            // `BridgeSession.handleSessionApproval` — every job-side path
            // either auto-denies stream approvals before they reach here
            // (`ClaudeCodeExecutor`) or cannot produce the name.
            if projection.interruption == .userStopped, projection.job == nil,
               request.toolName != BridgePolicy.sessionApprovalTool {
                return [.resolveApproval(
                    requestId: request.requestId, approved: false, remember: false)]
            }
            projection.approvalQueue.append(request)
            projection.cards = [.approval(request)]
        case .card(let card):
            projection.cards = [.answer(card)]
        case .approvalDenied(let tool):
            projection.cards = [.approvalAnswered(tool: tool, approved: false, remembered: false)]
        case .approvalRemembered(let tool, let approved):
            projection.cards = [.approvalAnswered(tool: tool, approved: approved, remembered: true)]
        }
        return []
    }

    /// A voice-born job only exists as events: a step before its name still
    /// opens the card, nameless rather than not at all.
    private mutating func append(_ step: JobStepInfo) {
        if projection.job == nil {
            projection.job = JobTimeline(goal: nil)
            projection.kind = .processing(.subAgentRunning)
        }
        projection.job?.steps.append(step)
    }

    /// Where the chrome goes when a piece of work ends: the job's row if one
    /// runs, the typed turn if one is open, the voice if it is live, and
    /// otherwise Completed with its timer.
    private mutating func rest() -> [SessionEffect] {
        if projection.job != nil {
            projection.kind = .processing(.subAgentRunning)
            return []
        }
        if typedBusy {
            projection.kind = .processing(.thinking)
            return []
        }
        switch voice.state {
        case .listening where !voice.muted:
            projection.kind = .listening
        case .thinking:
            projection.kind = .processing(.thinking)
        case .speaking:
            projection.kind = .processing(.speaking)
        case .idle, .connecting, .error, .listening:
            projection.kind = .processing(.completed)
            return [.scheduleCompletedExpiry(Self.completedDelay)]
        }
        return []
    }

    private mutating func stop() -> [SessionEffect] {
        var effects: [SessionEffect] = []
        if projection.job != nil {
            effects.append(.cancelJob)
            projection.job = nil
        }
        for request in projection.approvalQueue {
            effects.append(.resolveApproval(
                requestId: request.requestId, approved: false, remember: false))
        }
        projection.approvalQueue = []
        jobApprovedOnce = false
        // A typed turn in flight is abandoned too; a flag left true kept the
        // chrome painting the voice's last phase for ever (code review
        // 2026-09-06).
        typedBusy = false
        projection.holding = false
        projection.targets = []
        projection.interruption = .userStopped
        projection.kind = .idle
        return effects
    }

    private mutating func remove(_ requestId: String) -> ApprovalRequest? {
        guard let index = projection.approvalQueue.firstIndex(where: { $0.requestId == requestId })
        else { return nil }
        return projection.approvalQueue.remove(at: index)
    }

    /// The parent's own gates travel the same queue as the specialist's
    /// requests; only the specialist's are the job's actions.
    private static func isJobRequest(_ request: ApprovalRequest) -> Bool {
        ParentTool(rawValue: request.toolName) == nil
    }

    private static func status(of snapshot: TurnSnapshot) -> VoiceStatus {
        switch snapshot.state {
        case .idle, .error: .off
        case .connecting: .connecting
        case .listening, .thinking, .speaking: snapshot.muted ? .muted : .live
        }
    }

    private static func card(for failure: DictationFailure) -> SessionCard {
        switch failure {
        case .needsAccessibility: .permission(.accessibilityDenied)
        }
    }

    private static func card(for failure: TurnFailure) -> SessionCard {
        switch failure {
        case .micDenied, .speechDenied, .accessibilityDenied: .permission(failure)
        case .notHeard, .micSilent: .couldntHear
        default: .failure(failure)
        }
    }
}
