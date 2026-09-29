// Vocabulary of the session (Wave 12a): what the chrome can be in, what can
// happen to it, and what the runtime must do about it. The voice keeps its
// own machine (TurnMachine); this one observes it and owns the kind. The rule
// lives in SessionMachine.swift.
import Foundation

public enum SessionKind: Sendable, Equatable {
    case idle, hover, listening
    case processing(SessionPhase)

    /// Wave 17 (spec §3 "la voz de Karen gana": "al empezar un hold o
    /// enviar un chat"): only a hold or a sent chat is Karen's own turn.
    /// `.hover` — the pointer resting on the island — is rest, same as
    /// `.idle`: it must not pause the bridge just because the mouse passed
    /// over the notch.
    public var isUsersTurn: Bool {
        switch self {
        case .listening, .processing: true
        case .idle, .hover: false
        }
    }
}

public enum SessionPhase: Sendable, Equatable {
    case pending, thinking, speaking, toolExecuting, subAgentRunning, completed
}

/// Why the session left Processing without finishing. A reason on the way
/// back to Idle, never a kind of its own: a "cancelled" or "error" mode is
/// the state the chrome gets stuck in.
public enum InterruptReason: Sendable, Equatable {
    case userStopped
    case userSteered
    case failure(TurnFailure)
}

/// What the chrome can paint besides the kind. Intent names, ours.
public enum SessionCard: Sendable, Equatable {
    case couldntHear
    /// A refused input permission: the card carries a way to Settings.
    case permission(TurnFailure)
    case failure(TurnFailure)
    /// The sheet's source of truth is `SessionProjection.approval`; the card
    /// is the moment it arrived.
    case approval(ApprovalRequest)
    case approvalAnswered(tool: String, approved: Bool, remembered: Bool)
    /// The existing Card channel (map, gallery), straight from the tool.
    case answer(Card)
    /// Teach the hold: a tap, or the pointer resting on the island.
    case holdHint
    /// 16k-3: the turn named an app that is not connected; the card is the
    /// way to the Apps page (spec §2.5).
    case connectApp(slug: String, name: String)
}

/// The voice port's own status, distinct from the kind: a session can be
/// Idle while the socket is still opening.
public enum VoiceStatus: Sendable, Equatable {
    case off, connecting, live, muted
}

public struct SessionProjection: Sendable, Equatable {
    public var kind: SessionKind = .idle
    public var voice: VoiceStatus = .off
    public var pipeline: VoicePipeline?
    public var job: JobTimeline?
    /// Requests waiting for the sheet, in arrival order. The sheet shows the
    /// first; a voice-born job's and the chat's own gate can overlap.
    public var approvalQueue: [ApprovalRequest] = []
    /// The cards of THIS step only. A view that keeps one copies it.
    public var cards: [SessionCard] = []
    /// What the parent's hands are on right now ("Safari", a URL).
    public var targets: [String] = []
    /// Every app this TURN has touched, in order of first touch (16m-2):
    /// the reel outlives `parentActed`, and a new turn starts it fresh.
    public var touched: [String] = []
    /// Kept until the session leaves Idle again, so a Settings link outlives
    /// the step that produced it.
    public var interruption: InterruptReason?
    /// The card the resting chrome keeps showing (a hint, "could not hear",
    /// a refused permission) until something new starts. Cards are one
    /// step; this one outlives the snapshot that follows a release.
    public var notice: SessionCard?
    /// The key (or the pointer on the island) is down.
    public var holding: Bool = false
    /// What the ear has heard of the hold so far (Wave 12c). Written in
    /// Listening, kept through Pending, gone when the phase moves on.
    public var partial: String?
    /// Wave 12e: the app this hold dictates into, while it lasts (Listening,
    /// Pending, Completed). Nil when the hold talks to Companion.
    public var dictation: String?
    /// Wave 17: the bridge's client name while a session is open, nil once
    /// it closes. Independent of `kind` — the chip lives alongside whatever
    /// the chrome is doing, not instead of it.
    public var handsLentTo: String?
    /// Wave 17: bumped on every successful write action, wrapping at 1000,
    /// so the island can key a one-shot pulse animation off a value that
    /// keeps changing instead of a bare "it happened" flag.
    public var handsPulse: Int = 0
    /// Wave 20b: an executed bridge call happened within the linger. Drives
    /// the screen aura; `handsLentTo` (the chip) is the permission, this is
    /// the activity.
    public var handsActing: Bool = false
    /// Where the last call acted, in Accessibility's global top-left space.
    /// Nil when the target app exposed no window; the aura then follows the cursor.
    public var handsTarget: CGRect?

    public var approval: ApprovalRequest? { approvalQueue.first }

    public init() {}
}

public enum SessionEvent: Sendable, Equatable {
    /// The voice machine moved.
    case voice(TurnSnapshot)
    case typedSubmitted
    case typedReplyStreaming
    case typedReplyFinished
    /// The parent's hands, one round.
    case parentActing(targets: [String])
    case parentActed
    case job(JobEvent)
    case jobFinished(ok: Bool)
    /// The sheet answered.
    case approvalAnswered(requestId: String, approved: Bool, remember: Bool)
    /// The user answered out loud, for the request the voice session noted.
    /// It resolves only if that request is the one the sheet shows: a
    /// blind "first of the queue" let a yes noted for one request grant
    /// another (Wave 20c D1). Same road, same rules as the sheet.
    case approvalSpoken(requestId: String, approved: Bool)
    /// Answered somewhere else (the spoken "yes", the actor returning): out
    /// of the queue, nothing to resolve.
    case approvalSettled(requestId: String)
    /// Abandoned with its turn (a conversation switch): denied, but not a
    /// refusal of the job's first action.
    case approvalDropped(requestId: String)
    case hoverEntered
    case hoverLeft
    case completedTimerExpired
    /// A fading notice's six seconds are up (16e).
    case noticeExpired
    /// 16k-3: the turn named an app that is not connected (AppMention).
    case connectAppSuggested(slug: String, name: String)
    /// The hold key went down (or the pointer pressed the island).
    case pressed
    case pressedProvisionally
    case holdConfirmed
    /// The key came up after a real hold: send what was heard.
    case released
    /// The key came up before the threshold: no turn, teach the hold.
    case tapped
    /// 15d-1: the key came up as a tap (or chorded) after the mic had
    /// already opened on the way down: close it, send nothing, teach nothing.
    case holdCancelled
    /// A hold ended with nothing to send.
    case heardNothing
    /// Pending waited too long for the voice to answer.
    case pendingTimedOut
    /// The warm session rested with the mic taken for too long.
    case voiceIdleExpired
    /// The ear's running hypothesis for the hold (Wave 12c).
    case partialTranscript(String)
    /// Wave 12e: the hold will dictate into this app (decided at press).
    case dictating(app: String)
    /// The words landed in the field; nothing else happens.
    case dictated(app: String)
    /// The hold wanted to dictate and could not; the words went to Companion.
    case dictationFailed(DictationFailure)
    /// Wave 17: the bridge's session opened (or closed, `nil`) for this
    /// client. Independent of the turn machinery — a bridge session can sit
    /// open across many idle moments.
    case handsLent(client: String?)
    /// Wave 17: a write action executed through the bridge.
    case handsActed
    /// Wave 20b: any executed bridge call, reads included; the frame is
    /// where the target app's window is right now.
    case handsWorking(target: CGRect?)
    case handsGlowExpired
    /// The user: Esc, the Stop button, "stop".
    case stop
}

public enum SessionEffect: Sendable, Equatable {
    case cancelJob
    case resolveApproval(requestId: String, approved: Bool, remember: Bool)
    case scheduleCompletedExpiry(TimeInterval)
    case scheduleNoticeExpiry(TimeInterval)
    case scheduleHandsGlowExpiry(TimeInterval)
    case schedulePendingExpiry(TimeInterval)
    /// Open the session if there is none and open the mic.
    case startListening
    case startProvisionalListening
    case confirmListening
    /// Close the mic; `commit` sends what the ear heard (ForceEndpoint).
    case stopListening(commit: Bool)
    /// Cut what the voice is thinking or saying.
    case cancelVoiceOutput
    /// A hold session rests with the mic closed but the hardware taken:
    /// after this long, hang up (security review 2026-09-06).
    case scheduleVoiceIdleExpiry(TimeInterval)
    /// Close the voice session whole: socket, player and the microphone.
    case hangUpVoice
    case logTransition(from: SessionKind, to: SessionKind)
}
