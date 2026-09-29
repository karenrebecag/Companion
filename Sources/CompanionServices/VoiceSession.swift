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
    /// Read by VoiceSessionRealtimeOpen's `waitForReady`.
    let readyTimeout: TimeInterval
    let realtime: RealtimeRuntime
    let classic: ClassicRuntime
    /// Diagnostic microscope over the realtime path. Reuses the injected
    /// transcriber (idle in realtime mode) as native ground truth.
    let audit: VoiceAudit
    /// Written by VoiceSessionTurnLoop's `apply`.
    let snapBox: AudioStreamBox<TurnSnapshot>
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
    /// Read by VoiceSessionRealtimeOpen's `openRealtimeSession`.
    let jobs: (any JobSubmitter)?
    /// Read by VoiceSessionCommit's `senseVoice`.
    let sensor: (any ContextSensing)?
    /// Read by VoiceSessionRealtimeOpen's `openRealtimeSession`.
    let echoFreeProbe: @Sendable () -> Bool
    let reachability: any ReachabilityProbing
    /// Read by VoiceSessionRealtimeOpen's watchdog.
    let micSilenceTimeout: TimeInterval
    /// 15d-2: how long the mic keeps feeding the ears after the key comes
    /// up — the last syllable rides the tail (Incredible: 300 ms).
    let releaseTail: TimeInterval
    /// Written by VoiceSessionRealtimeOpen's watchdog.
    var micSilenceTask: Task<Void, Never>?
    /// Sampled once per session open; swapping outputs mid-session keeps the
    /// conservative value until the next turn.
    var echoFreeOutput = false
    /// Job outcomes waiting for a listening gap; the voice must never be
    /// talked over by its own announcement.
    var pendingAnnouncements: [String] = []
    /// Written by VoiceSessionApprovals.
    var pendingApproval: ApprovalRequest?
    /// Remote MCP tools whose sheet is open, by request id. Answered over the
    /// websocket with the sheet's click, never by `resolve_approval` (20c D2).
    /// Written by VoiceSessionApprovals.
    var pendingMCPApprovals: [String: ApprovalRequest] = [:]
    /// One auto-deny per open MCP sheet: these requests never enter
    /// `Approvals`, whose timer is what denies every other permission.
    var mcpApprovalTimers: [String: Task<Void, Never>] = [:]
    let mcpApprovalTimeout: TimeInterval
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
    /// Read by VoiceSessionTeardown's `writeSessionMemory`.
    let memoryStore: (any MemoryStore)?
    private let approvals: (any ApprovalsProvider)?
    /// Thread length at session open: the summary covers THIS session's
    /// exchanges, not the whole run. Written by VoiceSessionRealtimeOpen,
    /// read by VoiceSessionTeardown.
    var sessionStartTurns = 0
    /// The next `.commitWithText` closes a hold (Wave 12b): an empty ear
    /// then means "nothing to send", said out loud to the session, instead
    /// of the silent nothing a paused conversation gets. Written by
    /// VoiceSessionCommit.
    var commitClosesHold = false
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
    /// Read by VoiceSessionCommit's `dictate`.
    let injector: (any TextInjecting)?
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
        readyTimeout: TimeInterval = 6,
        mcpApprovalTimeout: TimeInterval = ApprovalTiming.autoDeny
    ) {
        self.mcpApprovalTimeout = mcpApprovalTimeout
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
}
