import CompanionCore
import Foundation

/// The pumps: every stream that feeds the session — server events, mic
/// frames, player drain and levels, synthesizer events. Split out of
/// VoiceSession when it crossed the 400-line gate. What they touch is not
/// `private` any more but still actor-isolated: the actor, not the access
/// level, is what keeps this state single-threaded.
extension VoiceSession {
    func startPumps() {
        if eventTask == nil {
            eventTask = Task { [weak self] in await self?.pumpEvents() }
        }
        if frameTask == nil {
            frameTask = Task { [weak self] in await self?.pumpFrames() }
        }
        if drainTask == nil {
            drainTask = Task { [weak self] in await self?.pumpDrained() }
        }
        if playerLevelTask == nil {
            playerLevelTask = Task { [weak self] in
                await self?.pumpPlayerLevels()
            }
        }
        if speechTask == nil {
            speechTask = Task { [weak self] in await self?.pumpSpeech() }
        }
        if earTurnTask == nil, segmentingEar != nil {
            earTurnTask = Task { [weak self] in await self?.pumpEarTurns() }
        }
    }

    /// 9j-1: the server's VAD owns turn-taking. It opens the turn when the
    /// user starts speaking and hands each finished utterance as final text —
    /// that text IS the turn. Over the agent, the prototype's rule applies:
    /// under two words is a backchannel and is dropped; two or more is a real
    /// interruption — cancel and commit.
    func pumpEarTurns() async {
        guard let segmentingEar else { return }
        for await event in segmentingEar.turnEvents {
            if Task.isCancelled { return }
            switch event {
            case .speechStarted:
                guard machine.snapshot.state != .speaking else { continue }
                await apply(.serverSpeechStarted)
            case .finished(let text):
                let trimmed = text.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if machine.snapshot.state == .speaking {
                    // 9j-6a: on speakers the mic hears the agent, and that
                    // echo transcribes as the agent's OWN words. Overlap with
                    // what the agent is saying = echo; a backchannel is under
                    // two words; anything else is the user really breaking in.
                    guard EchoGuard.isRealInterruption(
                        heard: trimmed, agentSaying: realtime.agentSpeech)
                    else { continue }
                    await apply(.serverSpeechStarted)
                }
                earSegment = trimmed
                await apply(.serverSpeechStopped)
            }
        }
    }

    func pumpEvents() async {
        for await event in transport.events() {
            if Task.isCancelled { return }
            if event == .sessionUpdated, !realtime.didBecomeReady {
                await apply(.realtimeSessionReady)
                realtime.didBecomeReady = true
            }
            let follow = await realtime.handle(
                event, state: machine.snapshot.state)
            for next in follow { await apply(next) }
        }
        // Stream ended unexpectedly while session was active.
        // FIX 2: Detect when stream ends without explicit close.
        // FIX 3: Attempt reconnect once if network available.
        // Only handle stream end if still in active realtime states (not already failed/idle).
        let state = machine.snapshot.state
        if state == .listening || state == .speaking {
            let online = await reachability.isOnline
            if online && !reconnectAttempted {
                reconnectAttempted = true
                Log.app("voice: reconnect attempt after stream ended")
                await reconnectRealtimeSession()
            } else {
                await apply(.turnFailed(.sessionDropped))
            }
        }
    }

    func reconnectRealtimeSession() async {
        guard let key = openAIKey() else {
            await apply(.turnFailed(.sessionDropped))
            return
        }
        guard let url = RealtimeCodec.url() else {
            await apply(.turnFailed(.sessionDropped))
            return
        }
        do {
            try await transport.open(key: key, url: url)
            // Reconnection succeeded: reset flag and resume pumps.
            reconnectAttempted = false
            startPumps()
        } catch {
            // Reconnection failed: degrade to error state.
            Log.app("voice: reconnect failed")
            await apply(.turnFailed(.sessionDropped))
        }
    }

    func pumpFrames() async {
        for await frame in mic.frames {
            if Task.isCancelled { return }
            lastMic = frame.rms
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            switch machine.snapshot.pipeline {
            case .classic:
                await transcriber.append(frame)
            case .realtime:
                // Wave 9i: the mic audio never reaches the conversation model;
                // the ear transcribes it and text drives the turn. Hearing and
                // barge-in are SEPARATE decisions: the backchannel gate exists
                // to keep an "ajá" from cutting the agent off, but a real
                // session showed it also deafening the ear mid-over-talk
                // (fwd=20, gated=85 — half a sentence lost). The ear hears
                // every frame that cannot contain the agent's own voice; the
                // gate only decides whether the agent gets interrupted.
                let aec = await mic.hasEchoCancellation || echoFreeOutput
                let snap = machine.snapshot
                let guarded = machine.isEchoGuarded(at: now())
                // With a segmenting ear the acoustic gate relaxes on speakers
                // (9j-6a): the ear hears the agent's echo, yes — but the echo
                // TRANSCRIBES as the agent's own words, and EchoGuard drops
                // those segments by text. Without a segmenting ear, the old
                // acoustic rule stands.
                let clean = !frame.pcm16le24k.isEmpty && !snap.muted
                    && realtime.micEnabled
                    && (segmentingEar != nil
                        ? !guarded
                        : (aec || (snap.state != .speaking && !guarded)))
                let reason: GateReason? = clean ? nil : RealtimeGate.reason(
                    muted: snap.muted, emptyPCM: frame.pcm16le24k.isEmpty,
                    micEnabled: realtime.micEnabled, state: snap.state,
                    echoGuarded: guarded, aec: aec)
                await audit.hear(frame, forwarded: clean, reason: reason)
                if snap.state == .speaking {
                    // Barge-in stays vetted: only sustained speech over the
                    // agent (with a clean mic) cuts it off.
                    if realtime.shouldForward(
                        frame, muted: snap.muted, aec: aec,
                        state: snap.state, echoGuarded: guarded) {
                        await apply(.serverSpeechStarted)
                    }
                } else if clean, segmentingEar == nil {
                    // Only without a segmenting ear: otherwise the server's
                    // VAD owns the turn (9j-1) and two deciders would race.
                    await driveTurn(rms: frame.rms)
                }
            case nil:
                continue
            }
        }
    }

    /// The words themselves drive the turn (Wave 9i): it opens when the ear's
    /// transcript grows past what earlier turns consumed, and closes when the
    /// transcript settles. RMS never opens a turn — this mic's noise floor
    /// sits above any usable threshold (measured 0.12 in "silence"), so
    /// energy cannot be trusted. Barge-in is decided upstream, per frame.
    func driveTurn(rms: Double) async {
        let text = audit.turnText()
        if transcriptEnd == nil {
            guard !text.isEmpty else { return }
            // Tuned to measured RMS on this mic (speech 0.3–0.8, floor 0.12):
            // voiceFloor above the floor so audible speech HOLDS the turn open
            // even when network deltas lag, and maxDelay generous enough that
            // a delta hiccup does not cut a sentence in half.
            var cfg = TranscriptEndpointer.Config()
            cfg.voiceFloor = 0.18
            cfg.minDelay = 0.9
            cfg.maxDelay = 4.0
            transcriptEnd = TranscriptEndpointer(config: cfg, start: now())
            await apply(.serverSpeechStarted)
        }
        switch transcriptEnd?.feed(text: text, level: rms, at: now()) {
        case .finished, .timedOut:
            transcriptEnd = nil
            await apply(.serverSpeechStopped)
        case .listening, .none:
            break
        }
    }

    func pumpDrained() async {
        for await _ in player.drained {
            if Task.isCancelled { return }
            await apply(.playerDrained)
        }
    }

    func pumpPlayerLevels() async {
        for await value in player.levels {
            if Task.isCancelled { return }
            lastAgent = value
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
        }
    }

    func pumpSpeech() async {
        for await event in synthesizer.events {
            if Task.isCancelled { return }
            switch event {
            case .finished:
                await apply(.speechFinished)
            case .failed:
                await apply(.speechFailed)
            case .level(let value):
                lastAgent = value
                levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            case .chunkStarted:
                break
            }
        }
    }
}
