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
            // A new pump is a new session: a reconnect still in flight from
            // the previous one sees the bump and stands down.
            realtimeGeneration += 1
            reconnectTimes = []
            let generation = realtimeGeneration
            eventTask = Task { [weak self] in await self?.pumpEvents(generation: generation) }
        }
        startFramePump()
        let pipeline = machine.snapshot.pipeline
        if partialTask != nil, partialPipeline != pipeline {
            partialTask?.cancel()
            partialTask = nil
        }
        if partialTask == nil {
            partialPipeline = pipeline
            partialTask = Task { [weak self] in await self?.pumpPartials() }
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

    /// Wave 12c: frames start flowing at the mic, before the socket, so a
    /// hold's first words are not lost to the handshake.
    func startFramePump() {
        if frameTask == nil {
            frameTask = Task { [weak self] in await self?.pumpFrames() }
        }
    }

    /// The mic is open because a hold holds it: the ear's segments and
    /// partials belong to that one turn.
    var holdOpen: Bool {
        let snap = machine.snapshot
        return snap.holdArmed && snap.state == .listening && !snap.muted
    }

    /// Wave 12c: the ear's hypotheses reach the island while the key is
    /// down. Read on the actor so `turnText()` sees a stable `committed`.
    func pumpPartials() async {
        // Classic hold feeds Apple; realtime hold feeds the audit ear.
        // Picking at start matches which `startPumps` caller armed us.
        // The text comes from the same ear as the stream: the audit wraps the
        // realtime ear when the app has one, and on classic that ear hears
        // nothing (seen live 2026-09-25: the island stayed blank).
        let realtime = machine.snapshot.pipeline == .realtime
        let stream = realtime ? audit.partials : transcriber.partials
        for await _ in stream {
            if Task.isCancelled { return }
            guard holdOpen else { continue }
            let text = realtime ? audit.turnText()
                : transcriber.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != lastPartial else { continue }
            lastPartial = text
            if !text.isEmpty { timeline.mark(.firstPartial, at: now()) }
            eventBox.yield(.partialTranscript(text))
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
                guard machine.snapshot.state != .speaking, !machine.snapshot.holdArmed else { continue }
                await apply(.serverSpeechStarted)
            case .finished(let text):
                // In a hold session the key owns the turn, not the server's
                // VAD: a segment closed while the key is down is not the end,
                // and one closed after the release (or a discard) is not a
                // new turn. The release already sent the ear's running text,
                // which includes these words (Wave 12c, code review).
                if machine.snapshot.holdArmed { continue }
                // 9j-6a: on speakers a segment can SPAN the agent's echo and
                // the user's words — the reply's tail leaked into her bubble.
                // Scrub the echoed prefix ALWAYS (not only while speaking):
                // what remains is what the user actually said. Nothing left,
                // or punctuation only, is pure echo — dropped.
                let scrubbed = EchoGuard.scrub(
                    heard: text, agentSaying: realtime.agentSpeech)
                guard !EchoGuard.words(scrubbed).isEmpty else { continue }
                if machine.snapshot.state == .speaking {
                    // Still talking over the agent: a backchannel is under two
                    // words; anything more is the user really breaking in.
                    guard EchoGuard.isRealInterruption(
                        heard: scrubbed, agentSaying: realtime.agentSpeech)
                    else { continue }
                    await apply(.serverSpeechStarted)
                }
                earSegment = scrubbed
                await apply(.serverSpeechStopped)
            }
        }
    }

    func pumpEvents(generation: Int) async {
        var events = transport.events()
        while true {
            for await event in events {
                if Task.isCancelled || generation != realtimeGeneration { return }
                if event == .sessionUpdated, !realtime.didBecomeReady {
                    await apply(.realtimeSessionReady)
                    realtime.didBecomeReady = true
                    // The retry is earned by a connection that got ready;
                    // one that dies first must not be reopened in a loop.
                    reconnectAttempted = false
                }
                let follow = await realtime.handle(
                    event, state: machine.snapshot.state)
                for next in follow { await apply(next) }
            }
            // Stream ended unexpectedly while session was active.
            // Only handle stream end if still in active realtime states (not already failed/idle).
            let state = machine.snapshot.state
            guard isCurrent(generation), state == .listening || state == .speaking else { return }
            let online = await reachability.isOnline
            // A hang-up can land while we ask: failing a closed session would
            // paint an error over the idle one the user just chose.
            guard isCurrent(generation) else { return }
            guard online, !reconnectAttempted, reconnectBudgetLeft() else {
                await apply(.turnFailed(.sessionDropped))
                return
            }
            reconnectAttempted = true
            reconnectTimes.append(now())
            Log.app("voice: reconnect attempt after stream ended")
            // The reconnect runs inside this very task, so startPumps would
            // see eventTask != nil and never start a reader: read the new
            // stream from here.
            guard await reconnectRealtimeSession(generation: generation) else { return }
            events = transport.events()
        }
    }

    /// Whether this pump still belongs to the live session. A closed session
    /// can be reopened (`start()` clears `voiceClosed`), so the generation is
    /// what tells the old pump from the new one.
    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && generation == realtimeGeneration && !voiceClosed
    }

    /// Readiness earns a retry, but a server that accepts and then drops,
    /// over and over, would still loop: this caps reconnects per window.
    private func reconnectBudgetLeft() -> Bool {
        let cutoff = now() - Self.reconnectWindow
        reconnectTimes = reconnectTimes.filter { $0 > cutoff }
        return reconnectTimes.count < Self.reconnectBudget
    }

    /// Reopens the socket as a NEW server session: it starts on the server's
    /// defaults, so the config goes out again before anything else.
    func reconnectRealtimeSession(generation: Int) async -> Bool {
        guard let key = openAIKey(), let url = RealtimeCodec.url() else {
            await apply(.turnFailed(.sessionDropped))
            return false
        }
        // Read before the socket opens: after `open` nothing may suspend
        // until the config is on its way, or a send could beat it.
        let history = await classic.thread.historyTurns()
        guard isCurrent(generation) else { return false }
        do {
            try await transport.open(key: key, url: url)
        } catch {
            guard isCurrent(generation), !(error is CancellationError) else { return false }
            Log.app("voice: reconnect failed")
            await apply(.turnFailed(.sessionDropped))
            return false
        }
        guard isCurrent(generation) else {
            // Nobody is left to use this socket. If a new session took over
            // the transport it owns it; closing would cut that one off.
            if voiceClosed { await transport.close() }
            return false
        }
        // Reset first, then prepare: `prepareSessionUpdate` reads `voiceSent`.
        // Both stay after the open so a send that failed on the dead socket
        // cannot leave the runtime paused for the new one.
        realtime.resetConnection()
        realtime.prepareSessionUpdate(
            config: configProvider.current, history: history,
            canDelegate: jobs != nil)
        await realtime.flushPendingUpdate()
        if realtime.transportDown { Log.app("voice: reconnect config not delivered") }
        await dropPendingMCPApprovals()
        return true
    }

    func pumpFrames() async {
        for await frame in mic.frames {
            if Task.isCancelled { return }
            if timeline.pressed != nil { timeline.mark(.micReady, at: now()) }
            lastMic = frame.rms
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            switch machine.snapshot.pipeline {
            case .classic:
                // 15c-7: the buffer only measures energy; the ear hears
                // what it missed while starting first, then this frame.
                classic.holdAudio.hearLive(frame)
                await classic.flushEarlyAudio()
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
                // Half-duplex without AEC: while the agent speaks on open
                // speakers, the ear is CLOSED — letting it hear and scrubbing
                // the echo by text leaked the agent's whole reply into the
                // user's bubble twice (measured). With AEC or an echo-free
                // output the mic is clean of the agent, so full duplex and
                // barge-in stay. Speaker barge-in needs real AEC (9j-6b).
                let clean = !frame.pcm16le24k.isEmpty && !snap.muted
                    && realtime.micEnabled
                    && (aec || (snap.state != .speaking && !guarded))
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
                // 15d-1: the mic is up before the on-device ear is; what
                // it hears meanwhile is the first word, kept for the ear.
                if machine.snapshot.classicListenPending {
                    classic.holdAudio.hearBeforeEar(frame)
                }
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
                markQuestionSaid()
                await logAnnouncementSaid()
                await apply(.speechFinished)
            case .failed:
                await logAnnouncementSaid()
                await apply(.speechFailed)
            case .level(let value):
                lastAgent = value
                levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            case .mark(let mark):
                // Same guard as `.chunkStarted`: a job announcement's marks,
                // or a later sentence's, are not this hold's first sentence.
                if timeline.released != nil, timeline.firstAudio == nil {
                    timeline.mark(TurnTimeline.Point(mark), at: now())
                }
            case .chunkStarted:
                // 15b-0: the classic path's only audio signal —
                // `.agentAudioStarted` (VoiceSession.apply) exists for
                // realtime alone. Guarded so a stray chunk with no released
                // hold (a job announcement) or a turn already measured never
                // rewrites the line.
                if timeline.released != nil, timeline.firstAudio == nil {
                    timeline.mark(.firstAudio, at: now())
                    flushTimeline()
                }
            }
        }
    }

    func completeHold(hasSpeech: Bool) async {
        switch await destination() {
        case .dictation(let field):
            screen?.cancel()
            let generation = holdGeneration
            // What the mic heard before the ear was up goes to the ear
            // first, as `finalTranscript` does, and leaves no PCM behind.
            await classic.flushEarlyAudio()
            // Through `stopEar()` so a listen started meanwhile waits for it.
            let text = await classic.stopEar().value
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Code review 2026-09-24 (medio): a newer press owns the session
            // now; pasting or discarding for this one would hang it up.
            guard generation == holdGeneration else { return }
            if text.isEmpty {
                // Code review 2026-09-23 (medio): this return never reaches
                // `senseVoice`, so the press-time sense `fanOut` started is
                // never consumed — cancel it here instead of leaking it.
                classic.cancelPressedContext()
                eventBox.yield(.heardNothing)
                await apply(.holdDiscarded)
                return
            }
            if await dictate(text, into: field) {
                // Same gap: dictation succeeded, so this turn never submits
                // and never reads the sense either.
                classic.cancelPressedContext()
                await apply(.holdDiscarded)
                return
            }
            classic.leftoverHeard = text
            await apply(.holdReleased(hasSpeech: true))
        case .agent(let notice):
            if notice == .needsAccessibility {
                eventBox.yield(.dictationFailed(.needsAccessibility))
            }
            // 15b-0: `commitTimeline` used to be `routeThroughDecisionGate`'s
            // own mark (DM1c-2), reached only with a router attached. Every
            // classic hold ends up here, router or not — this is the one
            // place both paths share.
            commitTimeline()
            await apply(.holdReleased(hasSpeech: hasSpeech))
        }
    }

    /// Named on press so 14b can switch the tube without hunting the picker.
    func rememberStack(openAI: Bool) {
        // 15c-7: Cerebras goes first for brain even with OpenAI present, so
        // its presence is checked on every press — OpenRouter still cannot
        // outrank OpenAI, so it stays skipped.
        var present: [SecretKey: Bool] = [
            .openAI: openAI, .cerebras: hasSecret(.cerebras),
            .elevenLabs: hasSecret(.elevenLabs),
        ]
        if !openAI {
            present[.openRouter] = hasSecret(.openRouter)
        }
        lastStack = VoiceStackResolver.resolve(
            secrets: present,
            appleSpeech: true,
            localModel: nil,
            elevenLabsVoiceID: configProvider.current.elevenLabsVoiceID)
        if let lastStack {
            Log.app("voice stack: \(lastStack.logLine)")
        }
    }

    func hasSecret(_ key: SecretKey) -> Bool {
        let value: String?
        do {
            value = try secrets.read(key)
        } catch {
            return false
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return !trimmed.isEmpty
    }
}
