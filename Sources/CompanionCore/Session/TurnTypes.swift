// Vocabulary of the turn: what the machine can be in, what can happen to it,
// and what the runtime must do about it. The rule lives in TurnMachine.swift.
import Foundation

package enum TurnState: Sendable, Equatable {
    case idle, connecting, listening, thinking, speaking, error
}

package enum VoicePipeline: Sendable, Equatable { case classic, realtime }

package enum TurnFailure: Sendable, Equatable {
    case micDenied, micUnavailable, micSilent, notHeard, speechEngine, noProviders, sessionDropped, networkUnavailable
    /// The key works; the account has no credit left. Must not read as "no
    /// network" or the user debugs the wrong thing (seen live 2026-09-06).
    case quotaExceeded
    /// Speech recognition refused: an INPUT permission, not a broken
    /// synthesiser. Separate case because the two are fixed in different
    /// places and telling them apart is the whole value of the message.
    case speechDenied
    /// Wave 12e: dictation could not type into the field. A permission,
    /// fixed in System Settings, not a broken voice.
    case accessibilityDenied
    /// Gap 1c: Screen Recording worked and stopped (revoked, or broken until
    /// a relaunch). Without it the sight would just go quiet.
    case screenRecordingDenied
}

package struct TurnSnapshot: Sendable, Equatable {
    package var state: TurnState
    package var pipeline: VoicePipeline?
    package var muted: Bool
    package var inConversation: Bool
    package var typedTurn: Bool
    package var streamingStarted: Bool
    package var speechOpen: Bool
    package var awaitingExecutor: Bool
    package var interruptionPending: Bool
    package var echoGuardUntil: TimeInterval
    /// Classic start stays idle until the mic is granted; hang-up must
    /// cancel that pending arm (no generation counter).
    package var classicListenPending: Bool
    /// The reason for entering the error state. Cleared when leaving error
    /// or starting a new voice session.
    package var failure: TurnFailure?
    /// A hold opened this session and is still down (Wave 12b). Only the
    /// connecting → ready race reads it: a release before ready leaves the
    /// mic closed and sends nothing.
    package var holdArmed: Bool
    /// A classic hold turn rests while its parent tool waits on the sheet,
    /// so the question can be said and the next press answers it instead of
    /// cutting. It lives as long as that turn task does: hang-ups and
    /// failures keep it, and only a cut, a new turn or the resume clear it.
    package var sheetParked: Bool

    package init(
        state: TurnState = .idle,
        pipeline: VoicePipeline? = nil,
        muted: Bool = false,
        inConversation: Bool = false,
        typedTurn: Bool = false,
        streamingStarted: Bool = false,
        speechOpen: Bool = false,
        awaitingExecutor: Bool = false,
        interruptionPending: Bool = false,
        echoGuardUntil: TimeInterval = 0,
        classicListenPending: Bool = false,
        failure: TurnFailure? = nil,
        holdArmed: Bool = false,
        sheetParked: Bool = false
    ) {
        self.state = state
        self.pipeline = pipeline
        self.muted = muted
        self.inConversation = inConversation
        self.typedTurn = typedTurn
        self.streamingStarted = streamingStarted
        self.speechOpen = speechOpen
        self.awaitingExecutor = awaitingExecutor
        self.interruptionPending = interruptionPending
        self.echoGuardUntil = echoGuardUntil
        self.classicListenPending = classicListenPending
        self.failure = failure
        self.holdArmed = holdArmed
        self.sheetParked = sheetParked
    }

    package static let idle = TurnSnapshot()
}

package enum TurnEvent: Sendable, Equatable {
    case startVoice(preferRealtime: Bool)
    case advance(hasSpeech: Bool)
    case typedSubmit
    case hangUp
    case toggleMute(hasPendingAudio: Bool)
    case classicListenArmed
    case realtimeSessionReady
    case voiceStartFailed(TurnFailure)
    case endpointFinished
    case endpointTimedOut(hasSpeech: Bool)
    case utteranceEmpty
    case heardWhileSpeaking(heard: String, agentSaying: String)
    case firstSentence
    case speechFinished
    case speechFailed
    case replyCompleted
    case delegateAnnounced
    case serverSpeechStarted
    case serverSpeechStopped
    case agentAudioStarted
    case agentAudioStopped
    case responseCompleted(hasPendingAudio: Bool)
    case playerDrained
    case delegateCallStarted
    case functionOutputSent
    case turnFailed(TurnFailure)
    /// Wave 12b: the hold. Press opens the session or the mic (and cuts the
    /// agent if it was talking); release closes the mic and sends what the
    /// ear heard; discard closes it and sends nothing; interrupt cuts the
    /// agent and leaves the mic as it was.
    case holdPressed(preferRealtime: Bool)
    case holdReleased(hasSpeech: Bool)
    case holdDiscarded
    case interrupt
    /// The turn's parent tool waits on the sheet, and the round it belongs
    /// to is over waiting.
    case sheetParked
    case sheetResumed
}

package enum TurnEffect: Sendable, Equatable {
    case openRealtimeSession
    case requestClassicListen
    case closeRealtime
    case stopClassicIO
    case submitUtterance
    /// `steer`: whether the cut is a change of course (press, barge-in) that
    /// leaves the next classic turn a note, or a stop that leaves none (R3).
    case cancelAgentOutput(steer: Bool)
    case commitAndRespond
    /// Wave 9i: arm the turn from the native (Apple) transcript instead of the
    /// audio OpenAI would guess from. The session reads the native text and
    /// either sends it as the user turn or, with nothing heard, degrades to
    /// committing the audio.
    case commitWithText
    case clearInputAudio
    case setMicEnabled(Bool)
    case beginSpeechStream
    case finishSpeechStream
    case noteFailure(TurnFailure)
}
