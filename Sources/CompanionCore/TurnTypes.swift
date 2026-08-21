// Vocabulary of the turn: what the machine can be in, what can happen to it,
// and what the runtime must do about it. The rule lives in TurnMachine.swift.
import Foundation

public enum TurnState: Sendable, Equatable {
    case idle, connecting, listening, thinking, speaking, error
}

public enum VoicePipeline: Sendable, Equatable { case classic, realtime }

public enum TurnFailure: Sendable, Equatable {
    case micDenied, micUnavailable, micSilent, notHeard, speechEngine, noProviders, sessionDropped, networkUnavailable
}

public struct TurnSnapshot: Sendable, Equatable {
    public var state: TurnState
    public var pipeline: VoicePipeline?
    public var muted: Bool
    public var inConversation: Bool
    public var typedTurn: Bool
    public var streamingStarted: Bool
    public var speechOpen: Bool
    public var awaitingExecutor: Bool
    public var interruptionPending: Bool
    public var echoGuardUntil: TimeInterval
    /// Classic start stays idle until the mic is granted; hang-up must
    /// cancel that pending arm (no generation counter).
    public var classicListenPending: Bool
    /// The reason for entering the error state. Cleared when leaving error
    /// or starting a new voice session.
    public var failure: TurnFailure?

    public init(
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
        failure: TurnFailure? = nil
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
    }

    public static let idle = TurnSnapshot()
}

public enum TurnEvent: Sendable, Equatable {
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
}

public enum TurnEffect: Sendable, Equatable {
    case openRealtimeSession
    case requestClassicListen
    case closeRealtime
    case stopClassicIO
    case submitUtterance
    case cancelAgentOutput
    case commitAndRespond
    case clearInputAudio
    case setMicEnabled(Bool)
    case beginSpeechStream
    case finishSpeechStream
    case noteFailure(TurnFailure)
}
