import CompanionCore
import Foundation

/// The turn's own state machine: apply an event, log the transition, act on
/// the effects it produces. Split out of VoiceSession when it crossed the
/// 400-line gate. What they touch is not `private` any more but still
/// actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    func flushAnnouncements() async {
        flushParkedAnnouncement()
        guard machine.snapshot.pipeline == .realtime,
              machine.snapshot.state == .listening,
              !pendingAnnouncements.isEmpty else { return }
        let text = pendingAnnouncements.removeFirst()
        await realtime.send(RealtimeCodec.systemItem(text))
        // An announcement never talks over anyone: it waits its turn.
        await realtime.requestResponse()
    }

    func apply(_ event: TurnEvent) async {
        let before = machine.snapshot.state
        switch event {
        case .realtimeSessionReady: timeline.mark(.sessionReady, at: now())
        case .firstSentence: timeline.mark(.firstToken, at: now())
        case .agentAudioStarted:
            timeline.mark(.firstAudio, at: now())
            flushTimeline()
        default: break
        }
        let effects = machine.handle(event, at: now())
        // Voice failures are invisible without a trace of the turn: the log is
        // the only witness of what the server and the audio graph did.
        if machine.snapshot.state != before {
            Log.app("voice: \(before) -> \(machine.snapshot.state)")
        }
        snapBox.yield(machine.snapshot)
        await perform(effects)
        if machine.snapshot.state == .error, before != .error {
            // A failed voice says nothing more on its own (review 16h-2 M3).
            voiceClosed = true
            await silenceAnnouncements(reason: "error")
        }
        await flushAnnouncements()
    }

    private func perform(_ effects: [TurnEffect]) async {
        for effect in effects {
            switch effect {
            case .openRealtimeSession:
                await openRealtimeSession()
            case .requestClassicListen:
                startPumps()
                await classic.requestListen(
                    mic: mic, language: configProvider.current.language
                ) { event in
                    await self.apply(event)
                }
            case .closeRealtime:
                await closeRealtime()
            case .stopClassicIO:
                // Every stop of ours ends a notice too: a stopped synthesizer
                // never reports `.finished`, and the lock would stay (S1).
                await cutAnnouncement()
                await classic.stopIO(mic: mic)
            case .submitUtterance:
                startClassicTurn(config: configProvider.current)
            case .cancelAgentOutput:
                if machine.snapshot.pipeline == .realtime {
                    await realtime.cancelAgent()
                } else {
                    await cancelClassicTurn()
                }
            case .commitAndRespond:
                // Muting mid-utterance: there is no audio buffer to commit any
                // more — closing the turn from the native transcript IS the
                // commit (Wave 9i).
                await commitTurnFromNative()
            case .commitWithText:
                await commitTurnFromNative()
            case .clearInputAudio:
                await realtime.clearInputAudio()
            case .setMicEnabled(let on):
                realtime.micEnabled = on
            case .beginSpeechStream:
                await synthesizer.begin()
            case .finishSpeechStream:
                await synthesizer.finish()
            case .noteFailure:
                // Deliberately silent. The failure reaches the thread through
                // the view model, which reads the language catalog; Services
                // writing its own wording meant one failure arrived twice, in
                // two different sentences, and the user read it as two bugs.
                break
            }
        }
    }
}
