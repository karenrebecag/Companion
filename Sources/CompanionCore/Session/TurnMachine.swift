// The turn rule: a pure reducer over TurnTypes. No I/O, no frameworks — the
// runtime in Services interprets the effects.
import Foundation

package struct TurnMachine: Sendable, Equatable {
    package static let echoGuardDuration: TimeInterval = 0.35
    package private(set) var snapshot: TurnSnapshot

    package init(snapshot: TurnSnapshot = .idle) {
        self.snapshot = snapshot
    }

    package func isEchoGuarded(at now: TimeInterval) -> Bool {
        snapshot.echoGuardUntil > 0 && now < snapshot.echoGuardUntil
    }

    package mutating func handle(_ event: TurnEvent, at now: TimeInterval) -> [TurnEffect] {
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
        case .holdPressed(let preferRealtime): return holdPressed(preferRealtime)
        case .holdReleased(let hasSpeech): return holdReleased(hasSpeech)
        case .holdDiscarded: return holdDiscarded()
        case .interrupt: return interrupt()
        }
    }
}

// MARK: - Wave 12b: the hold

extension TurnMachine {
    private mutating func holdPressed(_ preferRealtime: Bool) -> [TurnEffect] {
        switch snapshot.state {
        case .idle, .error:
            let effects = startVoice(preferRealtime)
            snapshot.holdArmed = true
            return effects
        case .connecting:
            // A release in between left `muted` set; the key is down again,
            // so the session must come up with the mic open (code review
            // 2026-09-06).
            snapshot.holdArmed = true
            snapshot.muted = false
            return []
        case .listening:
            guard snapshot.pipeline == .realtime, snapshot.muted else { return [] }
            return openMic()
        case .thinking, .speaking:
            guard snapshot.pipeline == .realtime else {
                return cutClassicTurn()
            }
            snapshot.state = .listening
            return [.cancelAgentOutput] + openMic()
        }
    }

    private mutating func holdReleased(_ hasSpeech: Bool) -> [TurnEffect] {
        switch snapshot.state {
        case .idle where snapshot.classicListenPending:
            return abandonPendingListen()
        case .connecting:
            // Released before the session was ready: no turn. The mic stays
            // closed when the session comes up.
            snapshot.holdArmed = false
            snapshot.muted = true
            return []
        case .listening:
            guard snapshot.pipeline == .realtime else { return advance(hasSpeech) }
            return closeMic() + [.commitWithText]
        // The server's own VAD can close the segment and move on to
        // `.thinking`/`.speaking` while the key is still physically down
        // (live 2026-09-22): the key-up must still close the mic and force
        // the endpoint, matching what `release()` promises — sending what
        // the ear heard without asking the server's VAD whether it agrees.
        // Classic has no concurrent VAD racing the key, so it is unaffected.
        case .thinking, .speaking:
            guard snapshot.pipeline == .realtime else { return [] }
            return closeMic() + [.commitWithText]
        case .idle, .error:
            return []
        }
    }

    private mutating func holdDiscarded() -> [TurnEffect] {
        switch snapshot.state {
        case .idle where snapshot.classicListenPending:
            return abandonPendingListen()
        case .connecting:
            snapshot.holdArmed = false
            snapshot.muted = true
            return []
        case .listening:
            guard snapshot.pipeline == .realtime else { return hangUp() }
            guard !snapshot.muted else { return [] }
            return closeMic() + [.clearInputAudio]
        case .idle, .error, .thinking, .speaking:
            return []
        }
    }

    private mutating func interrupt() -> [TurnEffect] {
        switch snapshot.state {
        case .thinking, .speaking:
            // Code review 2026-09-23 (alto): `interrupt` (spoken "para"/the
            // stop button) used to reuse `cutClassicTurn()` — holdPressed's
            // own reopen — and left a hot, unowned mic listening with no
            // endpointer and no key held to ever close it. Unlike a press,
            // nothing is about to hold this mic: it ends the same way a
            // hold now ends idle after its reply, torn down, not relistening.
            guard snapshot.pipeline == .realtime else {
                return [.cancelAgentOutput] + hangUp()
            }
            snapshot.state = .listening
            return [.cancelAgentOutput]
        case .idle, .error, .connecting, .listening:
            return []
        }
    }

    /// Classic `.thinking`/`.speaking` cut short by a press or an interrupt
    /// (15b-10 — `.thinking` used to return `[]`, spec §1-D): the turn
    /// stops and the mic reopens, the same shape whichever state it lands
    /// in, so `ClassicRuntime.submit` never races a fresh hold.
    private mutating func cutClassicTurn() -> [TurnEffect] {
        snapshot.interruptionPending = true
        snapshot.state = .listening
        return [.cancelAgentOutput, .requestClassicListen]
    }

    /// 15d-1: the key came up while the classic mic was still starting
    /// (a tap now lands inside press→mic). Nothing to stop yet: the listen
    /// that arrives next belongs to no hold, and `classicListenArmed` tears
    /// it down instead of listening for nobody.
    private mutating func abandonPendingListen() -> [TurnEffect] {
        snapshot.classicListenPending = false
        snapshot.holdArmed = false
        return []
    }

    private mutating func openMic() -> [TurnEffect] {
        snapshot.muted = false
        snapshot.speechOpen = false
        return [.setMicEnabled(true), .clearInputAudio]
    }

    private mutating func closeMic() -> [TurnEffect] {
        snapshot.muted = true
        snapshot.speechOpen = false
        return [.setMicEnabled(false)]
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
        // A classic listen still starting may already own a running mic.
        case nil: snapshot.classicListenPending ? [.stopClassicIO] : []
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
        snapshot = TurnSnapshot(state: .error, failure: reason)
        return effects
    }

    private mutating func recover(_ reason: TurnFailure) -> [TurnEffect] {
        var effects: [TurnEffect] = [.noteFailure(reason)]
        effects += teardownEffects()
        effects.append(.requestClassicListen)
        let kept = snapshot.inConversation
        snapshot = TurnSnapshot(
            state: .listening, pipeline: .classic, inConversation: kept, failure: reason)
        return effects
    }

    /// Code review 2026-09-24 (alto): a hold never recovers into listening
    /// — no key is down to ever close that mic. Hands-free recovers once;
    /// a recover whose listen never armed (`failure` still set) gives up.
    private mutating func failOrRecover(_ reason: TurnFailure) -> [TurnEffect] {
        let recovering = snapshot.state == .listening && snapshot.failure != nil
        guard snapshot.inConversation, !snapshot.holdArmed, !recovering else {
            return fail(reason)
        }
        return recover(reason)
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
            snapshot.failure = nil
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
        snapshot.failure = nil
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
            return cutClassicTurn()
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
        guard snapshot.classicListenPending || snapshot.pipeline == .classic else {
            // A listen nobody waits for any more (released, discarded or
            // hung up while the mic came up): the mic is on, so stop it.
            // A typed turn in flight is not a resting session: leave it be.
            let resting = snapshot.state == .idle || snapshot.state == .error
            return snapshot.pipeline == nil && resting ? [.stopClassicIO] : []
        }
        snapshot.classicListenPending = false
        snapshot.state = .listening
        snapshot.pipeline = .classic
        snapshot.speechOpen = false
        snapshot.streamingStarted = false
        snapshot.failure = nil
        return []
    }

    private mutating func realtimeSessionReady() -> [TurnEffect] {
        guard snapshot.state == .connecting else { return [] }
        snapshot.state = .listening
        snapshot.pipeline = .realtime
        snapshot.speechOpen = false
        // A hold released while connecting left `muted` set: the session
        // comes up with the mic closed and nothing sent (Wave 12b).
        return snapshot.muted ? [.setMicEnabled(false)] : []
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
        // A HOLD turn ends when its reply is spoken: the user presses again
        // for the next one, unlike hands-free. Relistening here re-armed a
        // mic `submit()` never stopped — MicCapture.startOnce() then
        // installed a second tap on the still-running engine and crashed
        // (live 2026-09-23).
        if snapshot.typedTurn || snapshot.holdArmed {
            let effects = snapshot.holdArmed ? teardownEffects() : []
            snapshot.typedTurn = false
            snapshot.holdArmed = false
            // The conversation this reply belonged to was a hold's: the next
            // failure must not take the hands-free recover path.
            snapshot.inConversation = false
            snapshot.state = .idle
            snapshot.pipeline = nil
            snapshot.speechOpen = false
            snapshot.echoGuardUntil = 0
            return effects
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
        // The server no longer responds from the audio (create_response:false):
        // arm the turn from the native transcript.
        return [.commitWithText]
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
