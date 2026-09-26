// Vocabulary of the session (Wave 12a): what the chrome can be in, what can
// happen to it, and what the runtime must do about it. The voice keeps its
// own machine (TurnMachine); this one observes it and owns the kind. The rule
// lives in SessionMachine.swift.
import Foundation

public enum SessionKind: Sendable, Equatable {
    case idle, hover, listening
    case processing(SessionPhase)
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
    /// The user answered out loud. The model carries no request id, so the
    /// answer goes to what the sheet shows: the first of the queue. Same
    /// road, same rules as the sheet (security review 2026-09-06).
    case approvalSpoken(approved: Bool)
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
    /// The user: Esc, the Stop button, "stop".
    case stop
}

public enum SessionEffect: Sendable, Equatable {
    case cancelJob
    case resolveApproval(requestId: String, approved: Bool, remember: Bool)
    case scheduleCompletedExpiry(TimeInterval)
    case scheduleNoticeExpiry(TimeInterval)
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
