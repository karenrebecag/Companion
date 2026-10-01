import CompanionCore
import Foundation
import Synchronization

/// Port protocols (Transcriber, SpeechSynthesizer, ChatProvider, ConversationPresenting)
/// may not conform to Sendable. Nothing here is isolated to VoiceSession: its
/// turn task, its notice task and (for three fields) the actor itself all run
/// this object at once, off the actor. What makes that safe is that a turn's
/// own state lives in its `TurnMouth` and never on the runtime, and the three
/// fields that genuinely cross tasks sit behind one `Mutex` (`Crossing`).
/// The rest is wiring, assigned once before the first task exists.
final class ClassicRuntime: @unchecked Sendable {
    let transcriber: any Transcriber
    let synthesizer: any SpeechSynthesizer
    let chat: any ChatProvider
    let thread: any ConversationPresenting
    /// The parent's hands (Wave 10b). Classic has no server loop, so the
    /// runtime loops itself: at most this many rounds per turn.
    var parentTools: (any ParentToolExecuting)?
    /// The session's outward stream (Wave 12a): cards and the parent's hands.
    var events: AudioStreamBox<SessionEvent>?
    var sensor: (any ContextSensing)?
    /// The `open_url` gate (Wave 10c 3D); empty = fail closed.
    var parentGuard = ParentToolGuard()
    /// Wave 14b: the hold's specialist. Nil means do not advertise `delegate`.
    var onDelegate: (@Sendable (Handoff) -> Void)?
    var onStopJob: (@Sendable () async -> Void)?
    var onResolveApproval: (@Sendable (Bool) async -> SpokenApproval)?
    /// 16q-1 review (security M3): the words of the hold this turn answers,
    /// reported before the model runs so a spoken yes is checked against what
    /// she said, not against what the model claims she said. Empty when
    /// nothing was heard.
    var onHeard: (@Sendable (String, TimeInterval?) async -> Void)?
    var screen: (any ScreenSeeing)?
    /// Wave 15b-5: `sensor.sense(...)` started at press (`VoiceSessionFanOut`),
    /// so `senseVoice` reads an already-finished Task at commit instead of
    /// paying the sense delay on the turn the user is waiting on.
    var pressedContext: Task<TurnContext?, Never>? {
        get { crossing.withLock { $0.pressedContext } }
        set { crossing.withLock { $0.pressedContext = newValue } }
    }

    /// The fields the actor and a turn task both touch. A struct under one
    /// lock, so a read-and-clear is a single step with no `await` inside.
    private struct Crossing {
        var steerPending = false
        var leftoverHeard: String?
        var pressedContext: Task<TurnContext?, Never>?
        /// Bumped when a turn gives up waiting on a stuck predecessor: that
        /// predecessor's late `cutTurn` writes no longer belong to anyone.
        var turnGeneration = 0
    }
    private let crossing = Mutex(Crossing())

    /// Code review 2026-09-23 (medio): every place that abandons a hold
    /// instead of letting `senseVoice` consume the scan — a fresh press's
    /// `fanOut` reassigning this, or `completeHold` discarding without ever
    /// submitting — must cancel it here. One place all those callers route
    /// through, so a stray scan never keeps sensing after its hold is gone.
    func cancelPressedContext() {
        takePressedContext()?.cancel()
    }

    private func takePressedContext() -> Task<TurnContext?, Never>? {
        crossing.withLock { state in
            defer { state.pressedContext = nil }
            return state.pressedContext
        }
    }
    /// The generation a turn captures once it owns the thread; see
    /// `supersedeStuckTurn` and ADR 008.
    func currentTurnGeneration() -> Int {
        crossing.withLock { $0.turnGeneration }
    }

    /// The deadline on a stuck predecessor expired and this turn starts
    /// anyway. Structured cancellation cannot stop the predecessor (it sits
    /// in a call that never looks at cancellation), so its late `cutTurn`
    /// is discarded by generation instead (ADR 008).
    func supersedeStuckTurn() {
        crossing.withLock { $0.turnGeneration += 1 }
    }

    private func isCurrentTurn(_ generation: Int) -> Bool {
        crossing.withLock { $0.turnGeneration == generation }
    }

    /// DM1c-2: `VoiceSession.attachDecision` wires the local router here.
    /// Nil (today) or a `.passThrough` outcome: byte-identical to before —
    /// the round loop below never sees this closure ran.
    var decide: (@Sendable (String, Bool) async -> DecisionOutcome)?
    /// Words already taken from the ear (dictation fallback). `stop()` is
    /// one-shot in production; a second call would drop the utterance.
    var leftoverHeard: String? {
        get { crossing.withLock { $0.leftoverHeard } }
        set { crossing.withLock { $0.leftoverHeard = newValue } }
    }

    private func takeLeftoverHeard() -> String? {
        crossing.withLock { state in
            defer { state.leftoverHeard = nil }
            return state.leftoverHeard
        }
    }
    /// 15b-10: set when a press cuts this turn mid-flight, consumed once by
    /// the next turn's `<steer>` note (15b-11) so the model knows it was
    /// interrupted instead of repeating itself.
    var steerPending: Bool {
        get { crossing.withLock { $0.steerPending } }
        set { crossing.withLock { $0.steerPending = newValue } }
    }

    private func takeSteerPending() -> Bool {
        crossing.withLock { state in
            defer { state.steerPending = false }
            return state.steerPending
        }
    }
    /// Wave 15b-9: the turn's own clock, injectable so a test can cross the
    /// idle window without sleeping.
    var now: @Sendable () -> Date = { Date() }
    static let maxParentRounds = ParentToolCopy.maxRounds
    /// Wave 15c-7: the hold's energy, read at release to name a silent hold;
    /// 15e-1: what the mic heard while the ear was still starting, handed to
    /// the ear ahead of the first live frame.
    let holdAudio = ClassicHoldAudio()
    /// 15d-0: the session's timeline, reached the way `RealtimeRuntime`
    /// reaches it — the runtime knows when the ear's final lands, the
    /// session owns the clock.
    var markTimeline: (@Sendable (TurnTimeline.Point) async -> Void)?
    /// 15d-5: the first-cut stall wait, injectable so a test can cross it
    /// without sleeping.
    /// 15d-6: the opt-in transcript file; `turnTranscripts` is it for the
    /// current turn only when `Config.debugTranscripts` was on at its start.
    var transcripts: TranscriptDebugLog?
    var firstCutWait: @Sendable () async -> Void = ClassicRuntime.defaultFirstCutWait
    /// 16h-2: how long a parent tool may run before the turn acknowledges
    /// it; injectable so a test decides when a tool counts as slow. An
    /// injected wait MUST return when its task is cancelled: the round ends
    /// by cancelling it, and a wait that ignores that holds the turn open.
    var slowToolWait: @Sendable () async -> Void = ClassicRuntime.defaultSlowToolWait
    /// How long a turn waits for the cut turn before it; injectable so a
    /// test decides when a predecessor counts as stuck. Unlike
    /// `slowToolWait` it may ignore cancellation: the race below cancels it
    /// only to free the timer early, and a late return is discarded.
    var turnWaitDeadline: @Sendable () async -> Void = ClassicRuntime.defaultTurnWaitDeadline
    /// 15f-2: judges each sentence's language before the mouth says it;
    /// injectable so tests do not depend on the system's model.
    var languageRecognizer: any LanguageRecognizing = NaturalLanguageRecognizer()
    /// Code review 2026-09-24 (alto): the listen that owns the mic and the
    /// ear. A tap's late teardown used to stop the NEXT hold's mic after
    /// its own awaits; it now re-checks ownership after each one. Also the
    /// ear's stop still in flight: the real one waits up to 0.5 s for its
    /// final (`AnalyzerTranscriber.finalizeTimeout`).
    private let ear = ClassicEarOwnership()

    init(
        transcriber: any Transcriber,
        synthesizer: any SpeechSynthesizer,
        chat: any ChatProvider,
        thread: any ConversationPresenting
    ) {
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.chat = chat
        self.thread = thread
    }

    func requestListen(
        mic: any MicCapturing,
        language: AppLanguage,
        apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async {
        // Every hold starts with its audio at zero, same rule as the native
        // transcript (VoiceSession.hold, security review 2026-09-06): late
        // frames from a previous hold must never ride the next one.
        holdAudio.reset()
        let owner = ear.claim()
        let granted = await mic.requestAccess()
        if !granted {
            return await failListen(.micDenied, apply: apply)
        }
        let speech = await transcriber.requestAuthorization()
        if !speech {
            return await failListen(.speechDenied, apply: apply)
        }
        do {
            try await mic.start()
        } catch {
            return await failListen(.micUnavailable, apply: apply)
        }
        // Started while an earlier stop is still waiting, this ear would be
        // halted by it the moment its final lands.
        if let stopping = ear.pendingStop { _ = await stopping.value }
        guard owner == ear.current else { return }
        do {
            try await transcriber.start(
                localeIdentifier: language.speechLocaleIdentifier)
        } catch {
            return await failListen(.speechEngine, apply: apply)
        }
        await apply(.classicListenArmed)
    }

    /// Code review 2026-09-24 (bajo): a listen that never arms never
    /// flushes; up to 10 s of what the mic heard meanwhile must not stay
    /// in memory.
    private func failListen(
        _ failure: TurnFailure, apply: @Sendable (TurnEvent) async -> Void
    ) async {
        holdAudio.reset()
        await apply(.voiceStartFailed(failure))
    }

    func stopIO(mic: any MicCapturing) async {
        holdAudio.reset()
        let owner = ear.current
        _ = await stopEar().value
        guard owner == ear.current else { return }
        await synthesizer.stop()
        guard owner == ear.current else { return }
        await mic.stop()
    }

    /// Every stop of the ear goes through here, so a listen that starts
    /// meanwhile can wait for it instead of being halted by it. A stop
    /// queues behind the one already in flight.
    func stopEar() -> Task<String, Never> {
        ear.queueStop { [transcriber] in await transcriber.stop() }
    }

    /// Hands the ear what it missed while starting, at most once.
    func flushEarlyAudio() async {
        let pcm = holdAudio.takeEarly()
        guard !pcm.isEmpty else { return }
        await transcriber.append(MicFrame(pcm16le24k: pcm, rms: 0))
    }

    /// Wave 15e-1: one ear, Apple's on-device analyzer. Whether the hold
    /// heard anything is the ear's own final (spec §2); 15c-7's energy gate
    /// stays to tell a silent hold from one the ear came back empty on.
    private func finalTranscript() async -> String {
        let hasSpeech = holdAudio.takeSpeech()
        await flushEarlyAudio()
        let text = await stopEar().value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Log.app("ear=apple-analyzer")
        } else if hasSpeech {
            Log.app("ear=apple-analyzer reason=empty")
        } else {
            Log.app("ear=none reason=silence")
        }
        return text
    }

    func submit(
        config: Config,
        endsHold: Bool = false,
        pressed: TimeInterval? = nil,
        after previous: Task<Void, Never>? = nil,
        apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async {
        let language = config.language
        let heard: String
        if let leftover = takeLeftoverHeard() {
            heard = leftover.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            heard = await finalTranscript()
        }
        // Code review 2026-09-24 (medio): a press cut this turn while its ear
        // was finishing. The listen running now is the next hold's; "heard
        // nothing" and the hang-up below would tear it down.
        // The session still hears nothing, so words kept from an older hold
        // cannot answer for this one.
        if heard.isEmpty, Task.isCancelled {
            await onHeard?("", pressed)
            return
        }
        await markTimeline?(.earFinal)
        // Held by this turn alone: a cut turn and its successor each write
        // to the log they started with.
        let transcript = config.debugTranscripts ? transcripts : nil
        transcript?.heard(heard)
        // A cancelled hold's words belong to no one: a new press cut it.
        await onHeard?(Task.isCancelled ? "" : heard, pressed)
        if heard.isEmpty {
            screen?.cancel()
            events?.yield(.heardNothing)
            // 15d-4: a hold with nothing heard rests with the mic off, as
            // Incredible does; relistening left a hot mic no key held.
            if endsHold { return await apply(.hangUp) }
            await apply(.classicListenArmed)
            do {
                try await transcriber.start(
                    localeIdentifier: language.speechLocaleIdentifier)
            } catch {
                Log.app("voice: classic ear restart failed")
            }
            return
        }
        // The cut turn before this one settles first, so its partial reply
        // and its steer note land before this turn reads them.
        if let previous, await waitForPrevious(previous) {
            Log.app("voice: classic turn wait expired, starting anyway")
            supersedeStuckTurn()
        }
        // A cut turn whose words never reached the model leaves no trace:
        // it must not thread them, leave a note, or take the `pressedContext`
        // the press that cut it just created for the next hold.
        if Task.isCancelled { return }
        let generation = currentTurnGeneration()
        // 15b-11: consumed exactly once by whichever turn comes next —
        // cleared here even when the router below ends up handling it and
        // never renders a `<context>` block to carry the note at all.
        let interrupted = takeSteerPending()
        if let decide {
            let outcome = await decide(heard, onDelegate != nil)
            if case .passThrough = outcome {
                // The router abstained (disabled, ignored, no executor…):
                // today's model-in-the-loop path takes the turn, unchanged.
            } else {
                await respond(
                    to: outcome, heard: heard, language: language, transcript: transcript,
                    generation: generation, apply: apply)
                return
            }
        }
        var context = await senseVoice(config, utterance: heard)
        context?.interrupted = interrupted
        await thread.appendUser(heard, context: context)
        var history = await thread.historyTurns()
        // The full block rides the current turn only (Wave 10a); so does the
        // 15d-7 language instruction, which the thread (and the bubble) never
        // see — only the request does. It sits right before the words, after
        // the block: screen text in another language must not come between.
        let block = context.map { ContextBlock.render($0, language: language) } ?? ""
        // The facts are in the prompt now: only here are they spent.
        if let context { sensor?.acknowledgeIslandEvents(through: context.islandEventsThrough) }
        if let last = history.indices.last, history[last].role == .user {
            let spoken = ContextBlock.languageInstruction(language) + "\n\n" + heard
            history[last].content = ContextBlock.wrap(spoken, with: block)
        }
        // 16k-3: the words decide which connected app's tools travel this
        // turn, before the list below is assembled.
        parentTools?.noteTurn(heard)
        var tools = parentTools?.specs(language) ?? []
        if onDelegate != nil {
            tools.append(.delegate(language))
            tools.append(.stopJob(language))
            tools.append(.resolveApproval(language))
        }
        // 15g-5: the context is in hand and the first chat request leaves
        // next — `commit→context` is the fan-out's share of the wait.
        await markTimeline?(.contextReady)
        var mouth = TurnMouth(language: language, recognizer: languageRecognizer, heard: heard)
        for round in 1 ... Self.maxParentRounds {
            var text = ""
            var calls: [ToolCallRef] = []
            var handoff: Handoff?
            var fromContent: ContentHandoff?
            var failed = false
            let (events, armFirstCut) = mouthEvents(chat.stream(history, tools: tools))
            do {
                for try await event in events {
                    if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
                    guard case .delta(let delta) = event else {
                        if let early = mouth.buffer.takeStalled() { await say(early, &mouth) }
                        continue
                    }
                    switch delta {
                    case .text(let raw):
                        let (piece, found) = guardJSON(mouth.json.feed(raw))
                        if fromContent == nil { fromContent = found }
                        guard await take(piece, round: &text, &mouth, apply: apply) else {
                            return await cutTurn(transcript, generation: generation)
                        }
                        if mouth.buffer.awaitsFirstCut { armFirstCut() }
                    case .toolCalls(let roundCalls):
                        for call in roundCalls {
                            await handleJobTool(call, language: language, &mouth)
                            if parentTools?.handles(call.name) == true {
                                calls.append(call)
                            }
                        }
                    case .handoff(let next):
                        if onDelegate != nil { handoff = next }
                    }
                }
            } catch {
                Log.app("voice: classic chat failed \(error)")
                if !mouth.started {
                    await apply(.turnFailed(VoiceFailureMapping.failure(for: error)))
                    return
                }
                failed = true
            }
            // An object still open when the stream ends was cut off: dropped,
            // never spoken; a lone brace was prose.
            let (tail, _) = guardJSON(mouth.json.finish())
            guard await take(tail, round: &text, &mouth, apply: apply) else {
                return await cutTurn(transcript, generation: generation)
            }
            if failed { break }
            if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
            if handoff == nil, let found = fromContent {
                if let fragment = mouth.buffer.drain() { await say(fragment, &mouth) }
                if !calls.isEmpty, let parentTools {
                    history += await actAcknowledging(
                        calls, said: mouth.saidPart(of: text), heard: heard, using: parentTools,
                        language: language, &mouth, apply: apply)
                }
                if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
                // Tool results are perceived input too: a page `web_fetch`
                // read can carry the goal object as well as the clipboard.
                let perceived = HandoffProposal.echoSources(context) + [block]
                    + history.filter { $0.role == .tool }.map(\.content)
                guard await propose(found, perceived: perceived, round: &text, &mouth,
                                    language: language, apply: apply)
                else { return await cutTurn(transcript, generation: generation) }
                break
            }
            if let handoff {
                if let fragment = mouth.buffer.drain() { await say(fragment, &mouth) }
                if !calls.isEmpty, let parentTools {
                    history += await actAcknowledging(
                        calls, said: mouth.saidPart(of: text), heard: heard, using: parentTools,
                        language: language, &mouth, apply: apply)
                }
                // A cut here still leaves the handoff undelivered: nothing
                // was promised to the user yet, so no errand starts on their
                // behalf without them hearing it (spec 15b-10 §3-D).
                if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
                // 16h-2: the user hears the line before the job exists, so a
                // slow specialist never decides when the turn first sounds;
                // a press over the line still keeps the errand from starting.
                await acknowledge(Acknowledgement.delegating(language), &mouth, apply: apply)
                if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
                onDelegate?(handoff)
                break
            }
            guard !calls.isEmpty, let parentTools else { break }
            // What was said before acting is said whole, not glued to the
            // next round's first word.
            if let fragment = mouth.buffer.drain() { await say(fragment, &mouth) }
            history += await actAcknowledging(
                calls, said: mouth.saidPart(of: text), heard: heard, using: parentTools,
                language: language, &mouth, apply: apply)
            // Code review 2026-09-23 (bajo): the only checkpoint this loop
            // was missing — a press landing mid-`act()` (a non-handoff tool
            // round) used to fall through into the next round's
            // `chat.stream` anyway.
            if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
            if round == Self.maxParentRounds {
                Log.app("voice: classic parent-tool round cap reached")
            }
        }
        if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
        if let rest = mouth.buffer.drain() {
            if !mouth.started {
                mouth.started = true
                await apply(.firstSentence)
            }
            await say(rest, &mouth)
        }
        await flushHeld(&mouth)
        await sayMissingEffects(&mouth, apply: apply)
        for line in mouth.owedLines { await sayOwn(line, &mouth, apply: apply) }
        if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
        if !mouth.spoken.isEmpty {
            let said = mouth.said
            transcript?.said(said)
            await thread.appendAssistant(said)
            await thread.finishStream()
        }
        if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
        await apply(.replyCompleted)
    }

    /// The turn was cut mid-flight (15b-10): what the voice already SAID
    /// (never the fuller text still mid-generation) threads as the
    /// assistant's partial reply, and the next turn gets a one-shot note
    /// that it happened — nothing here enqueues, appends twice or delegates.
    private func cutTurn(_ transcript: TranscriptDebugLog?, generation: Int) async {
        // A successor that gave up waiting owns the synthesizer and the
        // thread now: reading `spokenSoFar` would return ITS words.
        guard isCurrentTurn(generation) else { return }
        let partial = await synthesizer.spokenSoFar()
        // HACK: check and thread write are two steps, so a bump landing
        // between them still threads this partial. Close it with a
        // per-turn thread handle if the log ever shows an out-of-order one.
        guard isCurrentTurn(generation) else { return }
        if let partial {
            transcript?.said(partial)
            await thread.appendAssistant(partial)
            await thread.finishStream()
        }
        crossing.withLock { state in
            if state.turnGeneration == generation { state.steerPending = true }
        }
    }

    /// DM1c-2: the router already acted (or asked) instead of the strong
    /// model — say so through the exact speech/thread sequence a normal
    /// reply uses (one pipeline, not a second one) and stop: `chat.stream`
    /// never runs this turn.
    private func respond(
        to outcome: DecisionOutcome, heard: String, language: AppLanguage,
        transcript: TranscriptDebugLog?, generation: Int,
        apply: @escaping @Sendable (TurnEvent) async -> Void
    ) async {
        screen?.cancel()
        // No context block: the router's own turn, not the model's.
        await thread.appendUser(heard)
        let spoken: String
        let threaded: String
        switch outcome {
        case .passThrough:
            return
        case .acted(let result, let call):
            threaded = DecisionCopy.acted(result, tool: call.name, language)
            // 15b-3: the router's own reply must sound inside the 1.5s
            // budget — from disk if it is there, "Listo."/"Done." if not,
            // with the specific text warmed in the background for next time.
            let cached = await synthesizer.isCached(threaded)
            let choice = AckPolicy.choose(
                specific: threaded, specificCached: cached, language: language)
            spoken = choice.speak
            if let warm = choice.warm { await synthesizer.prewarm([warm]) }
        case .confirm(let question):
            spoken = question
            threaded = question
        case .declined:
            spoken = DecisionCopy.declined(language)
            threaded = spoken
        case .delegate:
            spoken = Acknowledgement.delegating(language)
            threaded = spoken
        }
        await apply(.firstSentence)
        // 16h-2: the line is queued before the job starts, same order as
        // the model path, and measured as the turn's acknowledgement.
        if case .delegate = outcome { await markTimeline?(.acknowledged) }
        // A press cut the router's turn (code review L2): nothing more is
        // said, and no errand starts behind the new hold.
        if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
        await synthesizer.enqueue(spoken)
        if Task.isCancelled { return await cutTurn(transcript, generation: generation) }
        if case .delegate(let handoff) = outcome { onDelegate?(handoff) }
        transcript?.said(spoken)
        await thread.appendAssistant(threaded)
        await thread.finishStream()
        await apply(.replyCompleted)
    }

    private func senseVoice(_ config: Config, utterance: String) async -> TurnContext? {
        var ctx: TurnContext
        if let pressed = takePressedContext() {
            guard let sensed = await pressed.value else { return nil }
            ctx = sensed
        } else {
            guard let sensor else { return nil }
            ctx = await sensor.sense(config.contextChannels, budget: config.contextBudget)
        }
        ctx.source = .voice
        if config.contextChannels.contains(.screen), let screen {
            // AX text (15b-6) arrives THROUGH `finish`, harvested at press.
            // Whether it landed no longer changes the wait (15g-5), so it is
            // not awaited here (review 2026-09-25).
            let wait = ScreenNeed.wait(utterance: utterance)
            let brief = await screen.finish(wait: wait)
            ctx.screenSummary = brief.summary
            ctx.screenSnippets = brief.snippets
            ctx.screenPending = brief.pending
            ctx.screenStale = brief.stale
            ctx.pointed = brief.pointed
        }
        // 15b-9: the thread's own clock, read now — before `submit` below
        // calls `appendUser` and moves it to this turn's own timestamp —
        // always wins over whatever a sensor guessed from its own last call,
        // nil included.
        let previous = await thread.lastInteraction()
        ctx.sinceLastTurn = previous.map { now().timeIntervalSince($0) }
        return ctx
    }

    private func handleJobTool(
        _ call: ToolCallRef, language: AppLanguage, _ mouth: inout TurnMouth
    ) async {
        switch call.name {
        case "stop_job":
            await onStopJob?()
        case "resolve_approval":
            if let approved = Self.approved(from: call.arguments),
               await onResolveApproval?(approved) == .needsClick {
                mouth.owedLines.append(Escalation.approvalNeedsClickSpoken(language))
            }
        default:
            break
        }
    }

    private static func approved(from json: String) -> Bool? {
        guard let data = json.data(using: .utf8) else { return nil }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
        return (obj as? [String: Any])?["approved"] as? Bool
    }
}
