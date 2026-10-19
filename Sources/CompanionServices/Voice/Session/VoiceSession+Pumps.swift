import CompanionCore
import Foundation

/// The pumps: every stream that feeds the session — ear partials, mic frames,
/// player drain and levels, synthesizer events. Split out of VoiceSession when
/// it crossed the 400-line gate. What they touch is not `private` any more but
/// still actor-isolated: the actor, not the access level, is what keeps this
/// state single-threaded.
extension VoiceSession {
    func startPumps() {
        startFramePump()
        if partialTask == nil {
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
    }

    /// Wave 12c: frames start flowing at the mic, before the ear is up, so a
    /// hold's first words are not lost to the startup.
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
        for await _ in transcriber.partials {
            if Task.isCancelled { return }
            guard holdOpen else { continue }
            let text = transcriber.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text != lastPartial else { continue }
            lastPartial = text
            if !text.isEmpty { timeline.mark(.firstPartial, at: now()) }
            eventBox.yield(.partialTranscript(text))
            notePartialForDecision(text)
        }
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
                // 15b-0: the classic path's only audio signal. Guarded so a
                // stray chunk with no released hold (a job announcement) or a
                // turn already measured never rewrites the line.
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
    func rememberStack() {
        // 15c-7: Cerebras goes first for brain, so its presence is checked on
        // every press; OpenRouter follows it.
        let present: [SecretKey: Bool] = [
            .cerebras: hasSecret(.cerebras),
            .elevenLabs: hasSecret(.elevenLabs),
            .openRouter: hasSecret(.openRouter),
        ]
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
