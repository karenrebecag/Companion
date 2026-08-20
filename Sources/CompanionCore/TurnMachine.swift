import Foundation

public enum TurnState: Sendable, Equatable {
    case idle, connecting, listening, thinking, speaking, error
}

public enum VoicePipeline: Sendable, Equatable { case classic, realtime }

public enum TurnFailure: Sendable, Equatable {
    case micDenied, micUnavailable, micSilent, notHeard, speechEngine, noProviders, sessionDropped
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
        classicListenPending: Bool = false
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

public struct TurnMachine: Sendable, Equatable {
    public static let echoGuardDuration: TimeInterval = 0.35
    public private(set) var snapshot: TurnSnapshot

    public init(snapshot: TurnSnapshot = .idle) {
        self.snapshot = snapshot
    }

    public func isEchoGuarded(at now: TimeInterval) -> Bool {
        snapshot.echoGuardUntil > 0 && now < snapshot.echoGuardUntil
    }

    public mutating func handle(_ event: TurnEvent, at now: TimeInterval) -> [TurnEffect] {
        switch event {
        case .startVoice(let preferRealtime): return startVoice(preferRealtime)
        case .advance(let hasSpeech): return advance(hasSpeech)
        case .typedSubmit: return typedSubmit()
        case .hangUp: return hangUp()
        case .toggleMute(let pending): return toggleMute(pending)
        case .classicListenArmed: return classicListenArmed()
        case .realtimeSessionReady: return realtimeSessionReady()
        case .voiceStartFailed(let failure), .turnFailed(let failure):
            return failOrRecover(failure)
        case .endpointFinished: return endpointFinished()
        case .endpointTimedOut(let hasSpeech): return endpointTimedOut(hasSpeech)
        case .utteranceEmpty: return failOrRecover(.notHeard)
        case .heardWhileSpeaking(let heard, let agentSaying):
            return heardWhileSpeaking(heard: heard, agentSaying: agentSaying)
        case .firstSentence: return firstSentence()
        case .speechFinished: return speechFinished()
        case .speechFailed: return fail(.speechEngine)
        case .replyCompleted: return replyCompleted()
        case .delegateAnnounced: return delegateAnnounced()
        case .serverSpeechStarted: return serverSpeechStarted()
        case .serverSpeechStopped: return serverSpeechStopped()
        case .agentAudioStarted: return agentAudioStarted()
        case .agentAudioStopped: return agentAudioStopped()
        case .responseCompleted(let pending):
            return responseCompleted(hasPendingAudio: pending, at: now)
        case .playerDrained: return playerDrained(at: now)
        case .delegateCallStarted: return delegateCallStarted()
        case .functionOutputSent: return functionOutputSent()
        }
    }
}

extension TurnMachine {
    private var isVoiceActive: Bool {
        snapshot.state == .listening || snapshot.state == .thinking
            || snapshot.state == .speaking
    }

    private func teardownEffects() -> [TurnEffect] {
        switch snapshot.pipeline {
        case .realtime: [.closeRealtime]
        case .classic: [.stopClassicIO]
        case nil: []
        }
    }

    private mutating func hangUp() -> [TurnEffect] {
        let effects = teardownEffects()
        snapshot = .idle
        return effects
    }

    private mutating func fail(_ reason: TurnFailure) -> [TurnEffect] {
        var effects: [TurnEffect] = [.noteFailure(reason)]
        effects += teardownEffects()
        snapshot = TurnSnapshot(state: .error)
        return effects
    }

    private mutating func recover(_ reason: TurnFailure) -> [TurnEffect] {
        var effects: [TurnEffect] = [.noteFailure(reason)]
        effects += teardownEffects()
        effects.append(.requestClassicListen)
        let kept = snapshot.inConversation
        snapshot = TurnSnapshot(
            state: .listening, pipeline: .classic, inConversation: kept)
        return effects
    }

    private mutating func failOrRecover(_ reason: TurnFailure) -> [TurnEffect] {
        snapshot.inConversation ? recover(reason) : fail(reason)
    }

    private mutating func beginUtterance(typed: Bool) -> [TurnEffect] {
        snapshot.state = .thinking
        snapshot.typedTurn = typed
        snapshot.streamingStarted = false
        snapshot.awaitingExecutor = false
        return [.submitUtterance]
    }

    private mutating func startVoice(_ preferRealtime: Bool) -> [TurnEffect] {
        guard snapshot.state == .idle || snapshot.state == .error else { return [] }
        guard preferRealtime else {
            snapshot.classicListenPending = true
            return [.requestClassicListen]
        }
        snapshot.state = .connecting
        snapshot.pipeline = .realtime
        snapshot.muted = false
        snapshot.typedTurn = false
        snapshot.streamingStarted = false
        snapshot.speechOpen = false
        snapshot.awaitingExecutor = false
        snapshot.interruptionPending = false
        snapshot.echoGuardUntil = 0
        return [.openRealtimeSession]
    }

    private mutating func advance(_ hasSpeech: Bool) -> [TurnEffect] {
        switch snapshot.state {
        case .idle, .error, .connecting:
            return []
        case .listening:
            if snapshot.pipeline == .realtime { return hangUp() }
            return hasSpeech ? beginUtterance(typed: false) : hangUp()
        case .thinking:
            return hangUp()
        case .speaking:
            if snapshot.pipeline == .realtime {
                snapshot.state = .listening
                return [.cancelAgentOutput]
            }
            snapshot.interruptionPending = true
            snapshot.state = .listening
            return [.cancelAgentOutput, .requestClassicListen]
        }
    }

    private mutating func typedSubmit() -> [TurnEffect] {
        guard snapshot.state == .idle || snapshot.state == .error else { return [] }
        return beginUtterance(typed: true)
    }

    private mutating func toggleMute(_ hasPendingAudio: Bool) -> [TurnEffect] {
        guard snapshot.pipeline == .realtime, isVoiceActive else { return [] }
        snapshot.muted.toggle()
        if snapshot.muted {
            var effects: [TurnEffect] = [.setMicEnabled(false)]
            if snapshot.speechOpen {
                snapshot.speechOpen = false
                effects.append(.commitAndRespond)
            }
            return effects
        }
        snapshot.speechOpen = false
        if snapshot.state != .listening && !hasPendingAudio {
            snapshot.state = .listening
        }
        return [.setMicEnabled(true), .clearInputAudio]
    }

    private mutating func classicListenArmed() -> [TurnEffect] {
        guard snapshot.classicListenPending || snapshot.pipeline == .classic
        else { return [] }
        snapshot.classicListenPending = false
        snapshot.state = .listening
        snapshot.pipeline = .classic
        snapshot.speechOpen = false
        snapshot.streamingStarted = false
        return []
    }

    private mutating func realtimeSessionReady() -> [TurnEffect] {
        guard snapshot.state == .connecting else { return [] }
        snapshot.state = .listening
        snapshot.pipeline = .realtime
        snapshot.muted = false
        snapshot.speechOpen = false
        return []
    }

    private mutating func endpointFinished() -> [TurnEffect] {
        guard snapshot.state == .listening else { return [] }
        return beginUtterance(typed: false)
    }

    private mutating func endpointTimedOut(_ hasSpeech: Bool) -> [TurnEffect] {
        guard snapshot.state == .listening else { return [] }
        return hasSpeech ? beginUtterance(typed: false) : hangUp()
    }

    private mutating func heardWhileSpeaking(heard: String, agentSaying: String) -> [TurnEffect] {
        guard snapshot.state == .speaking, snapshot.pipeline == .classic else { return [] }
        guard EchoGuard.isRealInterruption(heard: heard, agentSaying: agentSaying)
        else { return [] }
        snapshot.interruptionPending = true
        snapshot.state = .listening
        return [.cancelAgentOutput]
    }

    private mutating func firstSentence() -> [TurnEffect] {
        guard snapshot.state == .thinking, !snapshot.streamingStarted else { return [] }
        snapshot.streamingStarted = true
        snapshot.state = .speaking
        return [.beginSpeechStream]
    }

    private mutating func speechFinished() -> [TurnEffect] {
        guard snapshot.state == .speaking, snapshot.pipeline != .realtime else { return [] }
        snapshot.streamingStarted = false
        if snapshot.typedTurn {
            snapshot.typedTurn = false
            snapshot.state = .idle
            snapshot.pipeline = nil
            snapshot.speechOpen = false
            snapshot.echoGuardUntil = 0
            return []
        }
        snapshot.state = .listening
        snapshot.pipeline = .classic
        return [.requestClassicListen]
    }

    private mutating func replyCompleted() -> [TurnEffect] {
        guard snapshot.state == .thinking || snapshot.state == .speaking else { return [] }
        snapshot.inConversation = true
        if snapshot.streamingStarted { return [.finishSpeechStream] }
        snapshot.state = .speaking
        return []
    }

    private mutating func delegateAnnounced() -> [TurnEffect] {
        guard snapshot.state == .thinking || snapshot.state == .speaking else { return [] }
        snapshot.inConversation = true
        if snapshot.typedTurn {
            var effects: [TurnEffect] = []
            if snapshot.streamingStarted { effects.append(.finishSpeechStream) }
            snapshot.typedTurn = false
            snapshot.streamingStarted = false
            snapshot.state = .idle
            snapshot.pipeline = nil
            return effects
        }
        if snapshot.streamingStarted { return [.finishSpeechStream] }
        snapshot.state = .speaking
        return []
    }

    private mutating func serverSpeechStarted() -> [TurnEffect] {
        guard snapshot.pipeline == .realtime, isVoiceActive else { return [] }
        snapshot.speechOpen = true
        let cancel = snapshot.state == .speaking
        snapshot.state = .listening
        return cancel ? [.cancelAgentOutput] : []
    }

    private mutating func serverSpeechStopped() -> [TurnEffect] {
        guard snapshot.pipeline == .realtime, isVoiceActive else { return [] }
        snapshot.speechOpen = false
        snapshot.state = .thinking
        return []
    }

    private mutating func agentAudioStarted() -> [TurnEffect] {
        guard snapshot.pipeline == .realtime, isVoiceActive else { return [] }
        snapshot.state = .speaking
        return []
    }

    private mutating func agentAudioStopped() -> [TurnEffect] {
        guard snapshot.pipeline == .realtime, snapshot.state == .speaking else { return [] }
        snapshot.state = .listening
        return []
    }

    private mutating func responseCompleted(hasPendingAudio: Bool, at now: TimeInterval) -> [TurnEffect] {
        if snapshot.awaitingExecutor { return [] }
        if snapshot.state == .thinking {
            snapshot.state = .listening
            return []
        }
        if snapshot.state == .speaking, !hasPendingAudio {
            snapshot.echoGuardUntil = now + Self.echoGuardDuration
            snapshot.state = .listening
        }
        return []
    }

    private mutating func playerDrained(at now: TimeInterval) -> [TurnEffect] {
        guard snapshot.state == .speaking else { return [] }
        snapshot.echoGuardUntil = now + Self.echoGuardDuration
        snapshot.state = .listening
        return []
    }

    private mutating func delegateCallStarted() -> [TurnEffect] {
        guard isVoiceActive else { return [] }
        snapshot.awaitingExecutor = true
        snapshot.state = .thinking
        return []
    }

    private mutating func functionOutputSent() -> [TurnEffect] {
        guard snapshot.state != .idle, snapshot.state != .error else { return [] }
        snapshot.awaitingExecutor = false
        snapshot.state = .thinking
        return []
    }
}
