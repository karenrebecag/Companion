import Foundation

/// The session reducer (Wave 12a). Pure: `handle(event) -> [Effect]`. It
/// owns `SessionProjection.kind`; nothing else writes it. The voice machine
/// keeps deciding how to capture and play; this one translates its snapshots
/// into chrome and adds what the voice cannot see: typed turns, the parent's
/// hands, the specialist's job and the sheet.
package struct SessionMachine: Sendable, Equatable {
    package internal(set) var projection = SessionProjection()
    /// 0.2 s, Incredible's settle (local reference; brief isla-ciclo-y-legibilidad K1).
    package static let settleDelay: TimeInterval = 0.2
    /// 1.5 s, Incredible's settle floor (local reference; brief isla-ciclo-y-legibilidad K1).
    package static let settleFloor: TimeInterval = 1.5
    /// How long the hands aura outlives the last executed bridge call: long
    /// enough to bridge the gap between an agent's consecutive steps without
    /// flicker, short enough that an idle-but-open session goes dark.
    package static let handsGlowLinger: TimeInterval = 4
    /// Seconds Pending waits for the voice to answer before giving up.
    package static let pendingTimeout: TimeInterval = 12
    /// Seconds a hold session may rest, mic closed, before it hangs up. The
    /// software gate closes the ear, not the hardware: with the window gone
    /// nothing of ours showed the microphone was still taken (security
    /// review 2026-09-06). Long enough for the next hold to find it warm.
    package static let voiceIdleTimeout: TimeInterval = 20
    /// Seconds "didn't hear you" and the hold hint stay before leaving on
    /// their own, as Incredible's card does (spec 16c §2). A permission or
    /// a failure stays: it carries the way out.
    package static let noticeDelay: TimeInterval = 6
    /// 4.9 s, Incredible's dictation countdown (local reference; brief isla-ciclo-y-legibilidad K4).
    package static let dictationCardDelay: TimeInterval = 4.9
    /// The reel's ceiling per turn (16m-2, security review).
    package static let touchedCap = 12

    /// The pointer is over the dictation card: its clock is paused (K4).
    var dictationHeld = false
    /// The pointer is over a countdown notice. A notice armed while this is
    /// set starts paused; the flag drops when that notice leaves.
    var noticeHeld = false
    /// The pointer is over the panel. A settle armed while this is set starts
    /// paused. It tracks the pointer, so a new turn does not clear it.
    var settleHeld = false
    /// The answer popover is open. Only the expanded card holds the island
    /// open: a card nobody opened does not, so the view tells the reducer.
    var answerOpen = false
    /// Once per run: a lost grant stays lost until the user acts in Settings.
    var screenRecordingCardShown = false
    var voice = TurnSnapshot.idle
    var typedBusy = false
    /// Ids minted for steps whose producer sent none; never reused in a session.
    var stepsMinted = 0
    /// The key is down but still under the tap threshold: the mic is open
    /// locally, nothing has left the machine and no reply has been cut.
    var provisional = false
    /// 16h-2: the jobs the user stopped. Anything they still say is late.
    var stoppedJobs: [JobID] = []
    var finishedJobs: [JobID] = []
    /// Which job asked each queued request; untagged requests have none.
    var approvalOwners: [String: JobID] = [:]
    /// 16h-3: what the TURN has done and proved so far. Rounds of hands add to
    /// it; only a new turn (`openTurn`) drops it. Published as a notice when
    /// the chrome reaches rest, never mid-step.
    var turnReceipt: ActionReceipt?
    var receiptPublished = false
    /// P1: the user's wait before passive (0: never) and the arm now running.
    var passiveAfter: TimeInterval = 0
    var passiveArm = 0

    /// Where step times come from. Injected so Core never reads the wall clock
    /// in the reducer and tests can move time by hand.
    let clock: SessionClock

    package init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = SessionClock(now: clock)
    }

    /// Every request that leaves the sheet during an event, by any road, is
    /// reported once (`approvalClosed`), so the voice session never announces
    /// or answers a request that is no longer there (16q-1 review, M2).
    package mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        let queued = projection.approvalQueue.map(\.requestId)
        var effects = reduce(event) + presence(after: event)
        let still = Set(projection.approvalQueue.map(\.requestId))
        effects += queued.filter { !still.contains($0) }.map { .approvalClosed(requestId: $0) }
        // C2: a spoken answer lands only on the front; the voice is told
        // which one that is so it never reports an answer that went nowhere.
        let front = projection.approval?.requestId
        if front != queued.first { effects.append(.approvalFront(requestId: front)) }
        return effects
    }

    mutating func reduce(_ event: SessionEvent) -> [SessionEffect] {
        let before = projection.kind
        let wasRestingWarm = restingWarm
        let wasBlocked = settleBlocked
        projection.cards = []
        var effects: [SessionEffect] = []
        switch event {
        case .voice(let snapshot):
            effects += observe(snapshot)
        case .typedSubmitted:
            typedBusy = true
            openTurn()
            projection.touched = []
            projection.kind = .processing(.thinking)
        case .typedReplyStreaming:
            if typedBusy, case .processing = projection.kind {
                projection.kind = .processing(.speaking)
            }
        case .typedReplyFinished:
            typedBusy = false
            turnOver()
            effects += rest()
        case .parentActing(let targets):
            begin()
            projection.targets = targets
            // HACK: capped ring, newest wins. A looping turn must not grow
            // the reel without bound (security review 16m). Upgrade trigger:
            // the first turn that legitimately touches more apps than the
            // cap and needs the full history — then it moves to a summary.
            //
            // look, click and the others name no target: a blank one would
            // paint an empty chip in the reel.
            //
            // A repeat moves to the end: the reel shows the app touched last,
            // where the agent is acting now (brief isla-ciclo-y-legibilidad K8).
            for target in targets.filter(ParentTool.names) {
                projection.touched.removeAll { $0 == target }
                projection.touched.append(target)
                if projection.touched.count > Self.touchedCap {
                    projection.touched.removeFirst()
                }
            }
            projection.kind = .processing(.toolExecuting)
        case .parentActed:
            projection.targets = []
            effects += rest()
        case .job(let jobEvent, let id):
            effects += observe(jobEvent, from: id)
        case .jobFinished(_, let id):
            effects += dropApprovals(of: id)
            // Not the running job: nothing about the turn changes, but the
            // sheet it asked on may have just left.
            guard finish(id) else {
                return effects + settleOnceUnblocked(
                    wasCompleted: before == .processing(.completed), wasBlocked: wasBlocked)
            }
            effects += rest()
        case .approvalAnswered(let id, let approved, let remember):
            let owner = approvalOwners[id]
            guard let request = remove(id) else { return [] }
            // A job whose FIRST action you refuse is stopped whole (10c
            // 3B.4). Counted on the running job's own requests only.
            let ofJob = isActiveJobs(request, owner: owner)
            let stops = !approved && ofJob && projection.job?.approvedOnce != true
            if approved, ofJob { projection.job?.approvedOnce = true }
            effects.append(.resolveApproval(
                requestId: id, approved: approved, remember: remember && !stops))
            if stops, let owner { effects += stopJob(owner) }
        case .approvalSpoken(let id, let approved):
            // Named (16q-1) AND the one the sheet shows (20c D1): a yes admitted
            // for one request never reaches another, and never one the user
            // cannot see while she answers.
            guard projection.approval?.requestId == id else { return [] }
            return reduce(.approvalAnswered(requestId: id, approved: approved, remember: false))
        case .approvalSettled(let id):
            _ = remove(id)
        case .approvalWithdrawn(let id):
            // The actor already ended the wait: nothing to resolve. A card
            // already answered is gone, and then there is nothing to explain.
            guard remove(id) != nil else { return [] }
            if let current = projection.notice, !Self.fades(current) { return effects }
            projection.notice = .approvalWithdrawn
            projection.cards = [.approvalWithdrawn]
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .approvalDropped(let id):
            guard remove(id) != nil else { return [] }
            effects.append(.resolveApproval(requestId: id, approved: false, remember: false))
        case .hoverEntered:
            let fresh = !settleHeld
            settleHeld = true
            if projection.kind == .idle { projection.kind = .hover }
            if fresh, showsSettle { effects.append(.pauseCompletedExpiry) }
        case .hoverLeft:
            let held = settleHeld
            settleHeld = false
            if projection.kind == .hover { projection.kind = .idle }
            // The panel's leave is the backstop for a card hover-out SwiftUI
            // lost when the panel went click-through.
            let noticeWasHeld = noticeHeld
            let cardWasHeld = dictationHeld
            noticeHeld = false
            dictationHeld = false
            if noticeWasHeld { effects.append(.resumeNoticeExpiry) }
            // Under a blocker the paused settle must stay dead: the blocker
            // leaving arms a fresh one, and a resume here would race it.
            if (held && showsSettle && !settleBlocked) || (cardWasHeld && showsDictationCard) {
                effects.append(.resumeCompletedExpiry)
            }
        case .answerOpened:
            answerOpen = true
        case .answerClosed:
            answerOpen = false
        case .completedTimerExpired:
            // A notice, a sheet or an open answer that arrived during the
            // settle still needs the island; the last one leaving re-arms it.
            // The dictation card keeps its own clock whatever is up (K4).
            if projection.kind == .processing(.completed),
               projection.dictatedText != nil || !settleBlocked {
                projection.kind = .idle
                projection.dictation = nil
                projection.dictatedText = nil
            }
        case .pressed:
            openTurn()
            projection.holding = true
            projection.touched = []
            projection.kind = .listening
            effects.append(.startListening)
        case .pressedProvisionally:
            openTurn()
            projection.holding = true
            provisional = true
            projection.touched = []
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
        case .receipt(let receipt):
            turnReceipt = turnReceipt?.merging(receipt) ?? receipt
            receiptPublished = false
        case .connectAppSuggested(let slug, let name):
            // A nudge, not a transition: whatever the turn is doing keeps
            // the kind; the card offers the way to the Apps page and
            // leaves on its own like couldntHear.
            projection.notice = .connectApp(slug: slug, name: name)
            projection.cards = [.connectApp(slug: slug, name: name)]
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .signInAppSuggested(let slug, let name):
            // Same nudge as connectAppSuggested: the account exists, its
            // session does not, and the way out is the same Apps page.
            projection.notice = .signInApp(slug: slug, name: name)
            projection.cards = [.signInApp(slug: slug, name: name)]
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .replyCut:
            // News about a voice that is back: with it off, or a failure or
            // permission card up, "back online" would be false or would bury
            // what the user must act on.
            guard projection.voice != .off else { return [] }
            if let current = projection.notice, !Self.fades(current) { return [] }
            // Same nudge shape as the app suggestions: the turn keeps its kind.
            projection.notice = .replyCut
            projection.cards = [.replyCut]
            effects.append(.scheduleNoticeExpiry(Self.noticeDelay))
        case .noticeExpired(let armedFor):
            // A clock armed for a notice that is gone or replaced does nothing.
            if let notice = projection.notice, Self.fades(notice), armedFor == notice {
                projection.notice = nil
                noticeHeld = false
                seen(notice)
                if let kind = notice.islandKind { effects.append(.islandEvent(.ignored(kind))) }
            }
        case .noticeDismissed:
            if let notice = projection.notice, Self.fades(notice) {
                projection.notice = nil
                noticeHeld = false
                seen(notice)
                if let kind = notice.islandKind { effects.append(.islandEvent(.closed(kind))) }
            }
        case .pendingTimedOut:
            if projection.kind == .processing(.pending) { projection.kind = restingKind() }
        case .passiveAfterChanged, .passiveExpired: break
        case .voiceIdleExpired:
            // A notice still sounding keeps the warm session: hanging up
            // would cut it mid-sentence (review 16h-2 S1). It tries again.
            if restingWarm {
                effects.append(projection.announcing
                    ? .scheduleVoiceIdleExpiry(Self.voiceIdleTimeout) : .hangUpVoice)
            }
        case .partialTranscript(let text):
            if projection.kind == .listening { projection.partial = text }
        case .dictating(let app):
            if projection.kind == .listening { projection.dictation = app }
        case .dictated(let app, let text):
            guard projection.kind == .processing(.pending) else { return [] }
            projection.holding = false
            projection.dictation = app
            let words = (text?.value ?? "").isEmpty ? nil : text
            projection.dictatedText = words
            projection.kind = .processing(.completed)
            dictationHeld = false
            effects += completedExpiry()
        case .dictationCardHover, .dictationCardCopied:
            return dictationCardEffects(event)
        case .noticeCardHover:
            return noticeCardEffects(event)
        case .dictationHidden:
            guard projection.kind == .processing(.completed), projection.dictatedText != nil
            else { return [] }
            projection.kind = .idle
        case .dictationFailed(let failure):
            // A notice, not a transition: the words are already on their
            // way to Companion and its turn owns the kind.
            let card = Self.card(for: failure)
            projection.notice = card
            projection.cards = [card]
        case .screenRecordingLost:
            guard !screenRecordingCardShown else { return [] }
            screenRecordingCardShown = true
            let card = Self.card(for: TurnFailure.screenRecordingDenied)
            projection.notice = card
            projection.cards = [card]
        case .actionDone(let receipt):
            projection.receipt = receipt
            effects.append(.scheduleReceiptExpiry(id: receipt.id, UndoReceipt.undoWindow))
        case .receiptExpired(let id):
            if projection.receipt?.id == id { projection.receipt = nil }
        case .undoPressed(let id):
            guard let receipt = projection.receipt, receipt.id == id else { return [] }
            projection.receipt = nil
            effects.append(.undo(receipt))
        case .handsLent(let client):
            projection.handsLentTo = client
            if client == nil { projection.handsActing = false; projection.handsTarget = nil }
        case .handsActed:
            projection.handsPulse = (projection.handsPulse + 1) % 1_000
        case .handsWorking(let target):
            // A call in flight when the session closed: nobody holds the hands.
            guard projection.handsLentTo != nil else { break }
            projection.handsActing = true
            projection.handsTarget = target
            effects.append(.scheduleHandsGlowExpiry(Self.handsGlowLinger))
        case .handsGlowExpired:
            projection.handsActing = false
            projection.handsTarget = nil
        case .announcing(let on):
            projection.announcing = on
        case .stopVoice:
            guard voiceBrakeApplies else { return [] }
            effects += silenceVoice(always: false)
            effects += endTurn(denying: .theTurnsOwn)
        case .stopJob(let id):
            effects += stopJob(id)
        case .stop:
            guard totalBrakeApplies else { return [] }
            effects += silenceVoice(always: true)
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
        default:
            projection.dictation = nil
            projection.dictatedText = nil
        }
        if restingWarm, !wasRestingWarm {
            effects.append(.scheduleVoiceIdleExpiry(Self.voiceIdleTimeout))
        }
        effects += settleOnceUnblocked(wasCompleted: before == .processing(.completed), wasBlocked: wasBlocked)
        effects += publishReceipt()
        effects = pausingHeldNotice(effects)
        for card in projection.cards {
            if let kind = card.islandKind { effects.append(.islandEvent(.shown(kind))) }
        }
        if projection.kind != before {
            effects.append(.logTransition(from: before, to: projection.kind))
        }
        return effects
    }

    static func fades(_ notice: SessionCard) -> Bool {
        if case .connectApp = notice { return true }
        if case .signInApp = notice { return true }
        if case .receipt = notice { return true }
        if case .replyCut = notice { return true }
        if case .approvalWithdrawn = notice { return true }
        return notice == .couldntHear || notice == .holdHint
    }

    /// The user's own door into a turn (a press, a sent chat, the voice
    /// listening): a job already running goes behind it.
    mutating func openTurn() {
        begin()
        turnReceipt = nil
        projection.job?.behindTurn = true
    }

    /// Something new started: whatever the resting chrome was showing is
    /// over.
    mutating func begin() {
        projection.interruption = nil
        // At Idle the turn is over: lines held behind a permanent notice belong
        // to it, not to whatever starts now (a job, a bridge step).
        var clearsReceipt = false
        if case .receipt? = projection.notice { clearsReceipt = true }
        // Completed is over only while a notice holds it there: any other
        // Completed still has its receipt to publish when it settles.
        let turnIsOver = projection.kind == .idle
            || (projection.kind == .processing(.completed) && projection.notice != nil)
        if turnIsOver, !clearsReceipt { turnReceipt = nil }
        projection.notice = nil
        noticeHeld = false
        answerOpen = false
        // Whatever receipt was on screen is gone with it; the turn's lines
        // survive and come back at the next rest.
        receiptPublished = false
        projection.partial = nil
        projection.dictation = nil
        projection.dictatedText = nil
    }

    static func status(of snapshot: TurnSnapshot) -> VoiceStatus {
        switch snapshot.state {
        case .idle, .error: .off
        case .connecting: .connecting
        case .listening, .thinking, .speaking: snapshot.muted ? .muted : .live
        }
    }

    static func card(for failure: DictationFailure) -> SessionCard {
        switch failure {
        case .needsAccessibility: .permission(.accessibilityDenied)
        }
    }

    static func card(for failure: TurnFailure) -> SessionCard {
        switch failure {
        case .micDenied, .speechDenied, .accessibilityDenied, .screenRecordingDenied: .permission(failure)
        case .notHeard, .micSilent: .couldntHear
        default: .failure(failure)
        }
    }
}
