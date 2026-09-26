import CompanionCore
import Foundation

public actor VoiceSession: VoiceControlling {
    public nonisolated let snapshots: AsyncStream<TurnSnapshot>
    public nonisolated let levels: AsyncStream<VoiceLevels>
    /// Everything the session reports outward (Wave 12a): the specialist's
    /// events, the parent's hands, a permission settled by voice. One stream
    /// where there were six closures; the session reducer reads it.
    public nonisolated let events: AsyncStream<SessionEvent>

    var machine = TurnMachine()
    let transport: any VoiceTransport
    let mic: any MicCapturing
    let player: any PCMPlaying
    let transcriber: any Transcriber
    let synthesizer: any SpeechSynthesizer
    let secrets: any SecretStore
    let configProvider: any ConfigProviding
    let now: @Sendable () -> TimeInterval
    private let readyTimeout: TimeInterval
    let realtime: RealtimeRuntime
    let classic: ClassicRuntime
    /// Diagnostic microscope over the realtime path. Reuses the injected
    /// transcriber (idle in realtime mode) as native ground truth.
    let audit: VoiceAudit
    private let snapBox: AudioStreamBox<TurnSnapshot>
    let levelBox: AudioStreamBox<VoiceLevels>
    let eventBox: AudioStreamBox<SessionEvent>

    var eventTask: Task<Void, Never>?
    var frameTask: Task<Void, Never>?
    var drainTask: Task<Void, Never>?
    var playerLevelTask: Task<Void, Never>?
    var speechTask: Task<Void, Never>?
    /// 15b-10: `classic.submit`, detached so a press mid-turn can cancel it.
    var classicTurnTask: Task<Void, Never>?
    /// HIGH-B (code review 2026-09-25): a job's end, said as a classic turn;
    /// `said=` waits until its audio ends or a press cuts it.
    var announceTask: Task<Void, Never>?
    var announcementUnlogged = false
    private let jobs: (any JobSubmitter)?
    private let sensor: (any ContextSensing)?
    private let echoFreeProbe: @Sendable () -> Bool
    let reachability: any ReachabilityProbing
    private let micSilenceTimeout: TimeInterval
    /// 15d-2: how long the mic keeps feeding the ears after the key comes
    /// up — the last syllable rides the tail (Incredible: 300 ms).
    let releaseTail: TimeInterval
    private var micSilenceTask: Task<Void, Never>?
    /// Sampled once per session open; swapping outputs mid-session keeps the
    /// conservative value until the next turn.
    var echoFreeOutput = false
    /// Job outcomes waiting for a listening gap; the voice must never be
    /// talked over by its own announcement.
    var pendingAnnouncements: [String] = []
    private var pendingApproval: ApprovalRequest?
    /// A remote MCP tool waiting for the user's spoken yes (9j-3). Answered
    /// over the websocket, not through the job runner.
    private var pendingMCPApproval: ApprovalRequest?
    var lastMic = 0.0
    var lastAgent = 0.0
    var reconnectAttempted = false
    /// Wave 9i: the local voice-activity endpointer. OpenAI no longer listens,
    /// so the client decides when a user turn starts and ends, from the mic.
    /// Wave 9i: the user's turn, driven by the native transcript. Created when
    /// the transcript starts growing; the turn closes when it settles — robust
    /// to a noisy mic whose RMS never drops to true silence. Only runs when
    /// the ear does not segment turns itself (9j-1).
    var transcriptEnd: TranscriptEndpointer?
    /// The ear that detects turn boundaries itself, when there is one: the
    /// server's VAD knows when an idea ended; the local heuristics never did.
    let segmentingEar: (any SegmentingTranscriber)?
    /// The finished segment waiting to be committed as the turn's text.
    var earSegment: String?
    var earTurnTask: Task<Void, Never>?
    private let memoryStore: (any MemoryStore)?
    private let approvals: (any ApprovalsProvider)?
    /// Thread length at session open: the summary covers THIS session's
    /// exchanges, not the whole run.
    private var sessionStartTurns = 0
    /// The next `.commitWithText` closes a hold (Wave 12b): an empty ear
    /// then means "nothing to send", said out loud to the session, instead
    /// of the silent nothing a paused conversation gets.
    private var commitClosesHold = false
    /// Bumped by every press; a release compares it after its suspension.
    /// Not private: VoiceSessionTimeline reads and bumps it (Pumps precedent).
    var holdGeneration = 0
    /// 15d-2: a release is riding its tail; a press now resumes that hold.
    var releaseTailing = false
    /// FN is down but under the tap threshold: what leaves the machine
    /// (screen upload, context fan-out) is owed here until `confirmHold`.
    var owedHoldWork: OwedHoldWork?
    /// A press under the threshold that would have cut a reply, resumed a
    /// release tail or touched a socket: nothing happened yet, and a tap
    /// drops it.
    var deferredHold: DeferredHold?
    /// The hold whose commit a parent-tool answer belongs to (Wave DM0): a
    /// mark whose generation has since moved on is a stranger's, dropped.
    var toolGeneration = 0
    /// Wave 12c: the hold's clock, and the last one that finished.
    var timeline = TurnTimeline()
    /// Setter module-wide: VoiceSessionTimeline writes it on flush (DM0 split).
    public internal(set) var lastTimeline: TurnTimeline?
    /// Wave 14a: product roles for this hold. Named here; the tube still
    /// follows the OpenAI key until 14b. Setter is module-wide so the
    /// pumps extension can write it (private(set) is file-private).
    public internal(set) var lastStack: VoiceStack?
    var lastPartial = ""
    var partialTask: Task<Void, Never>?
    /// Which ear the running partial pump reads; it picks once, so a hold
    /// on the other pipeline needs a new pump (code review 16j-2).
    var partialPipeline: VoicePipeline?
    var earTask: Task<Void, Never>?
    /// Wave 12e: the field this hold dictates into, decided at press; and
    /// why it could not, when the words go to Companion instead.
    let fieldProbe: (any FocusedFieldProbing)?
    private let injector: (any TextInjecting)?
    /// Decided from the field focused at press, but off the press path: the
    /// Accessibility round trip is a call into the app in front, which may
    /// be busy, and the microphone must never wait for it. The release is
    /// where the answer is needed, and it awaits this.
    var dictationTask: Task<DictationDestination, Never>?
    /// Wave 13a: screenshot + vision sidecar, started on press.
    let screen: (any ScreenSeeing)?

    public init(
        transport: any VoiceTransport,
        mic: any MicCapturing,
        player: any PCMPlaying,
        transcriber: any Transcriber,
        synthesizer: any SpeechSynthesizer,
        chat: any ChatProvider,
        secrets: any SecretStore,
        thread: any ConversationPresenting,
        configProvider: any ConfigProviding,
        jobs: (any JobSubmitter)? = nil,
        // The realtime pipeline's ear, when it differs from the classic one:
        // OpenAI's live transcription hears mixed-language speech that Apple
        // es-MX garbles, but classic must keep the on-device ear — it exists
        // precisely for the no-key, no-network user.
        realtimeEar: (any Transcriber)? = nil,
        // 9j-2: where session summaries land at close. The write path is
        // async and mechanical — it never blocks audio or teardown.
        memoryStore: (any MemoryStore)? = nil,
        // Wave 10b: the parent's hands, on both pipelines.
        parentTools: (any ParentToolExecuting)? = nil,
        // Wave 10a: what the app perceives around each spoken turn.
        sensor: (any ContextSensing)? = nil,
        // Wave 10c 3D: where `open_url` waits for the sheet. The same actor
        // the job runner resolves, so one "yes" reaches either.
        approvals: (any ApprovalsProvider)? = nil,
        // Wave 12e: the app in front's focused field, and the hands that type
        // into it. Nil on either side means every hold talks to Companion.
        fieldProbe: (any FocusedFieldProbing)? = nil,
        injector: (any TextInjecting)? = nil,
        screen: (any ScreenSeeing)? = nil,
        reachability: any ReachabilityProbing = NetworkReachability(),
        // Injectable: a unit test must not depend on which output device the
        // machine happens to have plugged in (found out the hard way when the
        // echo-guard suite turned red just by wearing AirPods).
        echoFreeProbe: (@Sendable () -> Bool)? = nil,
        micSilenceTimeout: TimeInterval = 2.5,
        releaseTail: TimeInterval = 0.3,
        now: @escaping @Sendable () -> TimeInterval = {
            Date().timeIntervalSince1970
        },
        readyTimeout: TimeInterval = 6
    ) {
        self.transport = transport
        self.mic = mic
        self.player = player
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.secrets = secrets
        self.configProvider = configProvider
        self.jobs = jobs
        self.memoryStore = memoryStore
        self.fieldProbe = fieldProbe
        self.injector = injector
        self.screen = screen
        self.reachability = reachability
        self.echoFreeProbe = echoFreeProbe
            ?? { AudioDevicePin.outputIsEchoFree() }
        self.micSilenceTimeout = micSilenceTimeout
        self.releaseTail = releaseTail
        self.now = now
        self.readyTimeout = readyTimeout
        self.realtime = RealtimeRuntime(
            transport: transport, player: player, thread: thread)
        self.classic = ClassicRuntime(
            transcriber: transcriber, synthesizer: synthesizer,
            chat: chat, thread: thread)
        self.realtime.parentTools = parentTools
        self.classic.parentTools = parentTools
        self.classic.screen = screen
        self.approvals = approvals
        self.sensor = sensor
        self.classic.sensor = sensor
        // A parent's map, and its hands, travel the same stream as a
        // specialist's events.
        // HACK: unbounded buffer. One consumer, awaited per event; bound it
        // if a second consumer or a slow one ever appears.
        let eventBox = AudioStreamBox<SessionEvent>()
        self.eventBox = eventBox
        self.events = eventBox.stream
        self.realtime.events = eventBox
        self.classic.events = eventBox
        let audit = VoiceAudit(native: realtimeEar ?? transcriber)
        self.audit = audit
        self.realtime.audit = audit
        self.segmentingEar = realtimeEar as? any SegmentingTranscriber
        let snapBox = AudioStreamBox<TurnSnapshot>()
        let levelBox = AudioStreamBox<VoiceLevels>()
        self.snapBox = snapBox
        self.levelBox = levelBox
        self.snapshots = snapBox.stream
        self.levels = levelBox.stream
        // At the end of init on purpose: the closure captures self (for the
        // announce path), which is only legal once every property is set.
        realtime.markTimeline = { [weak self] point in await self?.markTool(point) }
        classic.markTimeline = realtime.markTimeline
        if let jobs {
            let presenter = thread
            // Same runner the button reaches. Someone talking to their Mac is
            // not looking at it, so the brake has to be sayable.
            realtime.onStopJob = { await jobs.cancel() }
            classic.onStopJob = realtime.onStopJob
            realtime.onDelegate = { [weak self] handoff in
                Task {
                    await VoiceJobBridge.run(
                        handoff, jobs: jobs, thread: presenter,
                        // The session listens in on the same seam that feeds
                        // the sheet: a permission asked while the user has
                        // their hands full has to reach the ear too.
                        onEvent: { [weak self] event in
                            eventBox.yield(event)
                            guard case .job(.approvalRequested(let request)) = event
                            else { return }
                            Task { [weak self] in
                                await self?.noteApproval(request)
                            }
                        },
                        announce: { [weak self] announcement in
                            await self?.jobAnnounce(announcement)
                        },
                        language: configProvider.current.language)
                }
            }
            classic.onDelegate = realtime.onDelegate
            realtime.onResolveApproval = { [weak self] approved in
                await self?.answerPendingApproval(approved) ?? false
            }
            classic.onResolveApproval = realtime.onResolveApproval
        }
        realtime.onMCPApproval = { [weak self] request in
            Task { [weak self] in await self?.noteMCPApproval(request) }
        }
        // The parent's `open_url` gate reaches the sheet through the job
        // seam and is parked for the spoken "yes", like a job's request.
        let presenter = thread
        let parentGuard = ParentToolGuard(
            approvals: approvals,
            onRequest: { [weak self] request in
                eventBox.yield(.job(.approvalRequested(request)))
                Task { [weak self] in await self?.noteApproval(request) }
            },
            onRemembered: { name, approved in
                await presenter.appendStatus(ParentToolCopy.remembered(
                    name, approved: approved, configProvider.current.language))
            })
        realtime.parentGuard = parentGuard
        classic.parentGuard = parentGuard
    }

    func noteMCPApproval(_ request: ApprovalRequest) async {
        pendingMCPApproval = request
    }

    /// The permission the specialist is blocked on. One at a time: the job
    /// queue is serial, so a new request means the previous one is settled.
    ///
    /// Deliberately silent: a job is assistive UI and does not interrupt to
    /// ask. The sheet shows the request; `resolve_approval` stays declared so
    /// a spoken "yes" still lands, but nobody is told out loud. The price,
    /// chosen: a request nobody looks at dies in the 120 s auto-deny.
    func noteApproval(_ request: ApprovalRequest) async {
        pendingApproval = request
    }

    /// The model turned the user's spoken answer into a decision. Nothing
    /// pending means the sheet already answered it (or the model invented the
    /// call): resolving anyway would grant a permission nobody asked about.
    func answerPendingApproval(_ approved: Bool) async -> Bool {
        // An MCP approval outranks a job approval: it arrived through the
        // live session the user is answering into.
        if let mcp = pendingMCPApproval {
            pendingMCPApproval = nil
            await realtime.send(RealtimeCodec.mcpApprovalResponse(
                requestId: mcp.requestId, approve: approved))
            await realtime.requestResponse()
            return true
        }
        guard pendingApproval != nil else {
            Log.app("voice: approval answered with nothing pending")
            return false
        }
        pendingApproval = nil
        // Not resolved here: the answer goes to the session reducer, which
        // resolves what the sheet shows (the first of its queue) with the
        // sheet's rules. Two notions of "pending" let a spoken yes grant a
        // request nobody was looking at (security review 2026-09-06).
        eventBox.yield(.approvalSpoken(approved: approved))
        return true
    }

    func flushAnnouncements() async {
        guard machine.snapshot.pipeline == .realtime,
              machine.snapshot.state == .listening,
              !pendingAnnouncements.isEmpty else { return }
        let text = pendingAnnouncements.removeFirst()
        await realtime.send(RealtimeCodec.systemItem(text))
        // An announcement never talks over anyone: it waits its turn.
        await realtime.requestResponse()
    }

    public func setSpeed(_ speed: Double) async {
        // Only a live realtime session has anywhere to send this; otherwise the
        // next session picks the persisted value up through the provider.
        guard machine.snapshot.pipeline == .realtime,
              machine.snapshot.state != .idle, machine.snapshot.state != .error
        else { return }
        await realtime.send(RealtimeCodec.speedUpdate(speed))
    }

    public func setVolume(_ volume: Double) async {
        await player.setVolume(volume)
    }

    public func start() async {
        await apply(.startVoice(preferRealtime: openAIKey() != nil))
    }

    public func advance() async {
        await apply(.advance(hasSpeech: await mic.receivedBuffer))
    }

    public func hangUp() async {
        screen?.cancel()
        await apply(.hangUp)
    }

    public func toggleMute() async {
        await apply(.toggleMute(hasPendingAudio: await player.hasPending))
        // A muted mic is the most invisible way to "not be heard": trace it.
        Log.app("voice: mic \(machine.snapshot.muted ? "muted" : "unmuted")")
    }

    public func interrupt() async {
        await apply(.interrupt)
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

    private func openRealtimeSession() async {
        realtime.reset()
        reconnectAttempted = false
        echoFreeOutput = echoFreeProbe()
        if echoFreeOutput { Log.app("audio: echo-free output detected") }
        guard let key = openAIKey() else {
            await failRealtimeStart()
            return
        }
        let granted = await mic.requestAccess()
        if !granted {
            await apply(.voiceStartFailed(.micDenied))
            return
        }
        do {
            try await mic.start()
        } catch {
            await apply(.voiceStartFailed(.micUnavailable))
            return
        }
        let aec = await mic.hasEchoCancellation
        do {
            try await player.start(sharedEngine: aec)
        } catch {
            await failRealtimeStart()
            return
        }
        guard let url = RealtimeCodec.url() else {
            await failRealtimeStart()
            return
        }
        // Read config from provider at session open time, allowing preferences
        // to apply without session reconstruction.
        let config = configProvider.current
        // Wave 12c: the user is already talking. The frames queue from here
        // and the ear comes up alongside the socket, not after it; the
        // first word of a hold used to fall in that gap.
        startFramePump()
        let locale = config.language.speechLocaleIdentifier
        earTask = Task { [weak self] in await self?.beginEar(locale: locale) }
        realtime.prepareSessionUpdate(
            config: config, history: await classic.thread.historyTurns(),
            canDelegate: jobs != nil)
        sessionStartTurns = await classic.thread.memoryTurns().count
        do {
            try await transport.open(key: key, url: url)
        } catch {
            await failRealtimeStart(error)
            return
        }
        startPumps()
        await realtime.flushPendingUpdate()
        if await waitForReady() {
            await earTask?.value
            earTask = nil
            armMicSilenceWatchdog()
            return
        }
        if machine.snapshot.state == .connecting {
            // Handshake never completed: unreachable from the user's side.
            await failRealtimeStart(VoiceTransportError.timeout)
        }
    }

    /// The ear, started on the actor while the socket opens. A session that
    /// died meanwhile (offline, refused) takes the ear down with it.
    private func beginEar(locale: String) async {
        await audit.begin(locale: locale)
        let state = machine.snapshot.state
        guard state == .connecting || state == .listening else {
            await audit.end()
            return
        }
        if audit.isLive { timeline.mark(.earReady, at: now()) }
    }

    private func failRealtimeStart(_ error: Error? = nil) async {
        // Offline is not the same as "the realtime server did not answer":
        // classic still works in the second case, but with no network it would
        // trade a readable error for a mic listening in silence.
        let online = await reachability.isOnline
        let failure = online
            ? VoiceFailureMapping.failure(for: error)
            : .networkUnavailable
        await apply(.voiceStartFailed(failure))
        guard online else { return }
        if machine.snapshot.state == .error {
            await apply(.startVoice(preferRealtime: false))
        }
    }

    /// The prototype armed this at the wiring layer: an engine can start
    /// clean and still never deliver a buffer (poisoned HAL, VPIO leftovers).
    /// Waits past MicCapture's own retry window, then fails LOUD instead of
    /// leaving a mic that listens to nothing forever.
    private func armMicSilenceWatchdog() {
        micSilenceTask?.cancel()
        micSilenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(micSilenceTimeout))
            } catch { return }
            await self.checkMicSilence()
        }
    }

    private func checkMicSilence() async {
        let snap = machine.snapshot
        guard snap.pipeline == .realtime,
              snap.state == .listening || snap.state == .connecting,
              await !mic.receivedBuffer else { return }
        Log.app("audio: no mic buffer after \(micSilenceTimeout)s — failing loud")
        await apply(.turnFailed(.micSilent))
    }

    /// End of a user turn. A segmenting ear (9j-1) hands the turn's final
    /// text directly; otherwise it is read from the ear's running transcript.
    private func commitTurnFromNative() async {
        let closesHold = commitClosesHold
        commitClosesHold = false
        // The server segmented the turn: its text is final, commit at once.
        if let segment = earSegment {
            earSegment = nil
            audit.consume()
            commitTimeline()
            await realtime.commitWithText(segment, context: await senseVoice())
            return
        }
        // Let the last native partial settle before reading it. A cancel here
        // means the session is tearing down — drop the turn, don't commit.
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            screen?.cancel()
            return
        }
        // v1 is hybrid-only: Apple is the ear. Without it (Speech denied) there
        // is no input path — say so once, don't spin responding to nothing.
        guard audit.isLive else {
            Log.app("voice: no native ear (Speech Recognition not authorized) "
                + "— enable it in System Settings › Privacy › Speech Recognition")
            if closesHold { eventBox.yield(.heardNothing) }
            screen?.cancel()
            return
        }
        let text = audit.turnText()
        var target: FocusedField?
        var notice: DictationNotice?
        switch await destination() {
        case .dictation(let field): target = field
        case .agent(let why): notice = why
        }
        // Dictated words are the user's document, not ours: they never
        // reach the log (corpus spec 11).
        if target == nil { audit.logTurn() }
        // Mark everything recognized so far as this turn's — the recognizer
        // keeps running (a restart re-enters its ~12 s cold start).
        audit.consume()
        guard !text.isEmpty else {
            if closesHold { eventBox.yield(.heardNothing) }
            screen?.cancel()
            return
        }
        if target != nil { screen?.cancel() }
        if let target, await dictate(text, into: target) { return }
        commitTimeline()
        await realtime.commitWithText(text, context: await senseVoice())
        if notice == .needsAccessibility {
            eventBox.yield(.dictationFailed(.needsAccessibility))
        }
    }

    /// True when the words landed in the field. On any failure they go to
    /// Companion instead: nothing the user said is lost, and never pasted
    /// anywhere but the field probed at press.
    func dictate(_ text: String, into field: FocusedField) async -> Bool {
        guard let injector else { return false }
        switch await injector.inject(text, into: field) {
        case .injected(let count, let route):
            commitTimeline()
            Log.app("dictation: pasted \(count) chars into \(field.app) via \(route.rawValue)")
            eventBox.yield(.dictated(app: field.app))
            return true
        case .failed(let reason):
            Log.app("dictation: \(reason) in \(field.app); the words go to Companion")
            if reason == .needsAccessibility {
                eventBox.yield(.dictationFailed(.needsAccessibility))
            }
            return false
        }
    }

    /// Sensed per spoken turn, within the budget; the source is voice.
    private func senseVoice() async -> TurnContext? {
        guard let sensor else { return nil }
        let config = configProvider.current
        var ctx = await sensor.sense(config.contextChannels, budget: config.contextBudget)
        ctx.source = .voice
        if config.contextChannels.contains(.screen), let screen {
            let brief = await screen.finish(wait: .seconds(2))
            ctx.screenSummary = brief.summary
            ctx.screenSnippets = brief.snippets
            ctx.screenPending = brief.pending
            ctx.pointed = brief.pointed
        }
        return ctx
    }

    private func closeRealtime() async {
        screen?.cancel()
        pendingAnnouncements.removeAll()
        micSilenceTask?.cancel()
        micSilenceTask = nil
        eventTask?.cancel()
        eventTask = nil
        earTurnTask?.cancel()
        earTurnTask = nil
        partialTask?.cancel()
        partialTask = nil
        await earTask?.value
        earTask = nil
        earSegment = nil
        dictationTask?.cancel()
        dictationTask = nil
        flushTimeline()
        await audit.end()
        await realtime.close(mic: mic)
        await writeSessionMemory()
    }

    /// 9j-2 write path: distill what THIS session asked into a short note.
    /// Mechanical (no model call) and best-effort — a failed write is logged,
    /// never surfaced as a session error.
    private func writeSessionMemory() async {
        guard let memoryStore else { return }
        // The memory reads the words, not the model's history: the compact
        // context line ("[voice · 1Password]") must never reach a file.
        let turns = await classic.thread.memoryTurns()
        guard turns.count > sessionStartTurns else { return }
        let fresh = Array(turns.dropFirst(sessionStartTurns))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        guard let summary = MemorySummary.distill(
            turns: fresh, date: formatter.string(from: Date())) else { return }
        do {
            try memoryStore.appendSession(summary)
            Log.app("memory: session summary saved")
        } catch {
            Log.app("memory: summary write failed (\(error))")
        }
    }

    private func waitForReady() async -> Bool {
        if readyTimeout <= 0 { return realtime.didBecomeReady }
        let deadline = ContinuousClock.now + .seconds(readyTimeout)
        while ContinuousClock.now < deadline {
            if realtime.didBecomeReady { return true }
            if machine.snapshot.state != .connecting { return false }
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                return realtime.didBecomeReady
            }
        }
        return realtime.didBecomeReady
    }

    func openAIKey() -> String? {
        let value: String?
        do {
            value = try secrets.read(.openAI)
        } catch {
            Log.app("voice: OpenAI key unread")
            return nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
