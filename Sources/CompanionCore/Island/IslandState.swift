import Foundation

/// What the island paints, decided from the projection in one pure place so
/// the decision is testable without a window. Sizes are roles, not points:
/// the UI maps them to its own tokens.
package struct IslandState: Sendable, Equatable {
    package enum Size: Sendable, Equatable, CaseIterable {
        case hidden, pebble, nudge, bar, card
        /// 16m-6: the update offer's card measures 522, wider than the 492 of
        /// every other card; only that one line asks for it.
        case wideCard
    }
    package enum Meter: Sendable, Equatable { case none, mic, agent }
    package enum Line: Sendable, Equatable {
        case none
        case holdHint
        /// Input Monitoring is missing: FN is not being heard at all (12e).
        case keyBlocked
        case pending
        case thinking
        case acting([String])
        case speaking
        case job(goal: String?, step: String?, steps: Int)
        case completed
        case couldntHear
        case permission(TurnFailure)
        case failure(TurnFailure)
        /// Wave 12e: the hold dictates into this app; the paste; where it landed.
        case dictating(String)
        case pasting
        case dictated(String)
        /// 16m-4: what the hold pasted, offered back as a card (copy / hide).
        case dictationResult(app: String, text: DictatedText)
        /// 16m-4: a newer release exists; the card offers its page.
        case updateAvailable(tag: String)
        /// Spec 15d §5: the hold's words are being written to disk.
        case transcriptsDebug
        /// Spec 16i §2: the user stopped the voice; said once, briefly.
        case cancelled
        /// Spec 16j §8: a task from the window rides along; the next turn
        /// continues it.
        case followUp(String)
        /// Spec 16i §4: a file is being dragged over the notch.
        case dropZones
        /// 16k-3: the turn named an app that is not connected yet.
        case connectApp(slug: String, name: String)
        /// 16m-6: the app is connected but its session expired.
        case signInApp(slug: String, name: String)
        /// 16p-1: a chat-level error (persistence, generic chat) that no turn
        /// failure line covers; the sentence rides along.
        case chatError(String)
        /// 16h-3: what the turn did and could prove.
        case receipt(ActionReceipt)
        /// The network cut the reply mid-sentence; shown only while the voice is live.
        case replyCut
        /// A cut ended the wait on a permission; says why nothing happened.
        case approvalWithdrawn
    }

    /// Incredible's status light: amber = it needs you, green = done.
    package enum Light: Sendable, Equatable { case none, amber, green }

    /// The one way out an error line carries (spec 16c §2: a full sentence
    /// and an exit, never a code). A dropped network has none: the next hold
    /// reconnects, and a button that does nothing would be a lie.
    package enum Action: Sendable, Equatable {
        case openKeys
        case openPermission(TurnFailure)
        /// Wave 17: "Corte" — closes the bridge session from the chip.
        case stopHands
        /// 16k-3: the connect card's way to the Apps page.
        case openApps(slug: String)
        /// 16m-4: the update card's way to the release page.
        case openUpdate
    }

    package var size: Size
    package var meter: Meter
    package var line: Line
    package var showsStop: Bool
    package var approval: ApprovalRequest?
    /// The hold's words so far, under the line (Wave 12c).
    package var partial: String?
    package var light: Light = .none
    package var action: Action?
    /// Wave 17: the bridge's client name while a session is open (spec §3
    /// "Se ve"), independent of `size`/`line` — the chip rides alongside
    /// whatever the chrome is doing.
    package var hands: String?
    /// Wave 20d B: why it can stay silent before acting is that the way back is
    /// here for five seconds.
    package var receipt: UndoReceipt?
    /// P2: a turn the companion runs while the user is away (passive). The island
    /// stays at rest, as in Incredible, and the voice line chip carries the turn.
    package var quietTurn = false
    /// A quiet turn's reply is not on the island: the model must not be told it was seen.
    package var reportsReplyShown: Bool { !quietTurn }
    /// The sheet replaced the field: the panel must hand the keyboard back,
    /// or the next Return meant for the draft answers the sheet (security
    /// review 16, critical).
    package var yieldsKeyboard: Bool { approval != nil }

    package init(
        size: Size, meter: Meter = .none, line: Line = .none,
        showsStop: Bool = false, approval: ApprovalRequest? = nil,
        partial: String? = nil
    ) {
        self.size = size
        self.meter = meter
        self.line = line
        self.showsStop = showsStop
        self.approval = approval
        self.partial = partial
    }

    /// `mainInFront`: the main window is key, so it paints the sheet and
    /// the island must not duplicate it (code review 2026-09-06).
    /// `holdLearned`: a hold has been completed once, so hover stops
    /// teaching it; a tap still asks (Wave 12c).
    /// `keyListening`: the FN tap is installed. Without Input Monitoring it
    /// is not, and teaching a key that cannot answer is a lie (seen live
    /// 2026-09-06: the hint showed, FN did nothing, the pointer did the work).
    package static func from(
        _ p: SessionProjection, pebbleHidden: Bool, mainInFront: Bool = false,
        holdLearned: Bool = false, keyListening: Bool = true, debugTranscripts: Bool = false,
        composing: Bool = false, cancelled: Bool = false, followUp: String? = nil,
        dropping: Bool = false, errorText: String? = nil, update: String? = nil
    ) -> IslandState {
        var state: IslandState
        switch p.kind {
        // A drag offers somewhere to drop only to a notch with nothing to say.
        case .idle where dropping && p.approval == nil && p.notice == nil,
             .hover where dropping && p.approval == nil && p.notice == nil:
            state = IslandState(size: .card, line: .dropZones)
        case .idle where composing:
            // A draft or a focused field outlives the pointer (16e).
            state = IslandState(size: .nudge)
        // A session notice carries its own way out and outranks this one.
        case .idle where !(errorText ?? "").isEmpty && p.notice == nil:
            state = IslandState(size: .card, line: .chatError(errorText ?? ""))
        case .idle where cancelled && p.notice == nil:
            state = IslandState(size: .bar, line: .cancelled)
        case .idle where followUp != nil && p.notice == nil:
            state = IslandState(size: .bar, line: .followUp(followUp ?? ""))
        // Last of the resting cards: an offer, never in front of something
        // that needs the user (a notice, an error, a hold), never on an
        // island the user hid (it would surface it) and never while the
        // main window is in front (it would say it twice).
        case .idle where update != nil && p.notice == nil && p.approval == nil
            && !mainInFront && !(pebbleHidden && p.voice == .off):
            state = IslandState(size: .wideCard, line: .updateAvailable(tag: update ?? ""))
        case .idle:
            state = atRest(p, pebbleHidden: pebbleHidden)
        case .hover:
            state = IslandState(size: .nudge, line: hoverLine(
                holdLearned: holdLearned, keyListening: keyListening,
                debugTranscripts: debugTranscripts))
        case .listening:
            // In a hold the finger is the brake; hands-free needs the button.
            // Incredible's pill says nothing while it listens: the bars and
            // the words heard so far are the whole message.
            state = IslandState(
                size: .bar, meter: .mic,
                line: p.dictation.map { .dictating($0) } ?? .none,
                showsStop: !p.holding, partial: p.partial)
        // P2: away from the user (passive) a turn does not open the island, as in
        // Incredible; a dictation is the user's own and always shows. The sheet,
        // the undo and the hands are applied below, so they still open it.
        case .processing where p.presence == .passive && p.dictation == nil:
            state = atRest(p, pebbleHidden: pebbleHidden)
            state.quietTurn = true
            // Something running is never invisible, even on an island the user hid.
            if state.size == .hidden { state.size = .pebble }
        case .processing(let phase):
            state = processing(phase, p)
        }
        if let approval = p.approval {
            state.size = .card
            state.approval = mainInFront ? nil : approval
        }
        // Wave 17: the chip needs somewhere to live even at rest — but never
        // shrinks a sheet already showing (`size` is `.card` by the time the
        // approval block above runs, so this `hidden`/`pebble` check never
        // fires while one is up).
        if let client = p.handsLentTo {
            state.hands = client
            if state.size == .hidden || state.size == .pebble {
                state.size = .nudge
            }
        }
        // A receipt rides alongside whatever the chrome is doing, like the
        // hands chip: the undo must be findable even while a turn speaks.
        if let receipt = p.receipt {
            state.receipt = receipt
            if state.size == .hidden || state.size == .pebble { state.size = .nudge }
        }
        state.light = light(p)
        state.action = action(state.line)
        return state
    }

    private static func light(_ p: SessionProjection) -> Light {
        if p.approval != nil { return .amber }
        if p.receipt != nil { return .green }
        if p.kind == .processing(.completed), p.dictation == nil { return .green }
        return .none
    }

    private static func action(_ line: Line) -> Action? {
        switch line {
        case .permission(let failure): .openPermission(failure)
        case .failure(.noProviders), .failure(.quotaExceeded): .openKeys
        case .connectApp(let slug, _), .signInApp(let slug, _): .openApps(slug: slug)
        case .updateAvailable: .openUpdate
        default: nil
        }
    }

    /// Whether the whole panel takes the mouse hold: only while a press that
    /// started on the mark is still down. The island grows under the finger;
    /// dropping the gesture then would lose the release and leave the hold
    /// listening forever (seen live 2026-09-06). Since 16e the hover panel
    /// holds a text field, so at rest only the mark starts a hold.
    package static func acceptsPointer(size: Size, pointerDown: Bool) -> Bool {
        size != .hidden && pointerDown
    }

    /// A dead key comes first — nothing else works until it is fixed; then
    /// the words going to disk, which outranks teaching the hold.
    private static func hoverLine(
        holdLearned: Bool, keyListening: Bool, debugTranscripts: Bool
    ) -> Line {
        guard keyListening else { return .keyBlocked }
        if debugTranscripts { return .transcriptsDebug }
        return holdLearned ? .none : .holdHint
    }

    private static func atRest(_ p: SessionProjection, pebbleHidden: Bool) -> IslandState {
        switch p.notice {
        case .holdHint: IslandState(size: .bar, line: .holdHint)
        // A notice with a way out is a card, as Incredible draws it (spec 16i §9).
        case .couldntHear: IslandState(size: .card, line: .couldntHear)
        case .connectApp(let slug, let name):
            IslandState(size: .card, line: .connectApp(slug: slug, name: name))
        case .signInApp(let slug, let name):
            IslandState(size: .card, line: .signInApp(slug: slug, name: name))
        case .permission(let failure): IslandState(size: .card, line: .permission(failure))
        case .failure(let failure): IslandState(size: .card, line: .failure(failure))
        case .receipt(let receipt): IslandState(size: .card, line: .receipt(receipt))
        case .replyCut: IslandState(size: .card, line: .replyCut)
        case .approvalWithdrawn: IslandState(size: .card, line: .approvalWithdrawn)
        // While the voice session lives the microphone is taken: the pebble
        // is the one mark of ours that says so, and it cannot be hidden
        // (security review 2026-09-06).
        default: IslandState(size: pebbleHidden && p.voice == .off ? .hidden : .pebble)
        }
    }

    private static func processing(_ phase: SessionPhase, _ p: SessionProjection) -> IslandState {
        switch phase {
        case .pending:
            return IslandState(
                size: .bar, line: p.dictation == nil ? .pending : .pasting,
                showsStop: true, partial: p.partial)
        case .thinking:
            return IslandState(size: .bar, line: .thinking, showsStop: true)
        case .toolExecuting:
            return IslandState(size: .bar, line: .acting(p.targets), showsStop: true)
        case .speaking:
            return IslandState(size: .bar, meter: .agent, line: .speaking, showsStop: true)
        case .subAgentRunning:
            let job = p.job
            return IslandState(
                size: .card,
                line: .job(goal: job?.goal, step: job?.steps.last?.label, steps: job?.steps.count ?? 0),
                showsStop: true)
        case .completed:
            guard let app = p.dictation else { return IslandState(size: .bar, line: .completed) }
            // The words are the card; without them the bar only says where.
            guard let text = p.dictatedText, !text.value.isEmpty else {
                return IslandState(size: .bar, line: .dictated(app))
            }
            return IslandState(size: .card, line: .dictationResult(app: app, text: text))
        }
    }
}

/// The sheet can appear over any app, under the pointer: a click already
/// on its way must not answer it (security review 2026-09-06).
package struct ApprovalClickGuard: Sendable, Equatable {
    /// Seconds the sheet ignores clicks after appearing.
    package static let dwell: TimeInterval = 0.6
    package let shownAt: TimeInterval

    package init(shownAt: TimeInterval) {
        self.shownAt = shownAt
    }

    package func accepts(at now: TimeInterval) -> Bool {
        now - shownAt >= Self.dwell
    }

    /// A guard never set means not yet safe, never always safe. Content that
    /// is still fading in cannot be seen, so a click on it is never an
    /// answer, whatever the dwell says (security review 2026-10-03).
    package static func accepts(_ guard: ApprovalClickGuard?, at now: TimeInterval,
                                contentVisible: Bool) -> Bool {
        contentVisible && (`guard`?.accepts(at: now) ?? false)
    }
}
