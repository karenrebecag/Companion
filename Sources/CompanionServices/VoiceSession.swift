import CompanionCore
import Foundation

public actor VoiceSession: VoiceControlling {
    public nonisolated let snapshots: AsyncStream<TurnSnapshot>
    public nonisolated let levels: AsyncStream<VoiceLevels>

    var machine = TurnMachine()
    let transport: any VoiceTransport
    let mic: any MicCapturing
    let player: any PCMPlaying
    let transcriber: any Transcriber
    let synthesizer: any SpeechSynthesizer
    private let secrets: any SecretStore
    private let configProvider: any ConfigProviding
    let now: @Sendable () -> TimeInterval
    private let readyTimeout: TimeInterval
    let realtime: RealtimeRuntime
    private let classic: ClassicRuntime
    /// Diagnostic microscope over the realtime path. Reuses the injected
    /// transcriber (idle in realtime mode) as native ground truth.
    let audit: VoiceAudit
    private let snapBox: AudioStreamBox<TurnSnapshot>
    let levelBox: AudioStreamBox<VoiceLevels>

    var eventTask: Task<Void, Never>?
    var frameTask: Task<Void, Never>?
    var drainTask: Task<Void, Never>?
    var playerLevelTask: Task<Void, Never>?
    var speechTask: Task<Void, Never>?
    private let jobs: (any JobSubmitter)?
    private let echoFreeProbe: @Sendable () -> Bool
    let reachability: any ReachabilityProbing
    private let micSilenceTimeout: TimeInterval
    private var micSilenceTask: Task<Void, Never>?
    /// Sampled once per session open; swapping outputs mid-session keeps the
    /// conservative value until the next turn.
    var echoFreeOutput = false
    private let onJobEvent: (@Sendable (JobEvent) -> Void)?
    /// Job outcomes waiting for a listening gap; the voice must never be
    /// talked over by its own announcement.
    private var pendingAnnouncements: [String] = []
    private var pendingApproval: ApprovalRequest?
    var lastMic = 0.0
    var lastAgent = 0.0
    var reconnectAttempted = false
    /// Wave 9i: the local voice-activity endpointer. OpenAI no longer listens,
    /// so the client decides when a user turn starts and ends, from the mic.
    /// Wave 9i: the user's turn, driven by the native transcript. Created when
    /// the transcript starts growing; the turn closes when it settles — robust
    /// to a noisy mic whose RMS never drops to true silence.
    var transcriptEnd: TranscriptEndpointer?

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
        onJobEvent: (@Sendable (JobEvent) -> Void)? = nil,
        // The realtime pipeline's ear, when it differs from the classic one:
        // OpenAI's live transcription hears mixed-language speech that Apple
        // es-MX garbles, but classic must keep the on-device ear — it exists
        // precisely for the no-key, no-network user.
        realtimeEar: (any Transcriber)? = nil,
        reachability: any ReachabilityProbing = NetworkReachability(),
        // Injectable: a unit test must not depend on which output device the
        // machine happens to have plugged in (found out the hard way when the
        // echo-guard suite turned red just by wearing AirPods).
        echoFreeProbe: (@Sendable () -> Bool)? = nil,
        micSilenceTimeout: TimeInterval = 2.5,
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
        self.onJobEvent = onJobEvent
        self.reachability = reachability
        self.echoFreeProbe = echoFreeProbe
            ?? { AudioDevicePin.outputIsEchoFree() }
        self.micSilenceTimeout = micSilenceTimeout
        self.now = now
        self.readyTimeout = readyTimeout
        self.realtime = RealtimeRuntime(
            transport: transport, player: player, thread: thread)
        self.classic = ClassicRuntime(
            transcriber: transcriber, synthesizer: synthesizer,
            chat: chat, thread: thread)
        let audit = VoiceAudit(native: realtimeEar ?? transcriber)
        self.audit = audit
        self.realtime.audit = audit
        let snapBox = AudioStreamBox<TurnSnapshot>()
        let levelBox = AudioStreamBox<VoiceLevels>()
        self.snapBox = snapBox
        self.levelBox = levelBox
        self.snapshots = snapBox.stream
        self.levels = levelBox.stream
        // At the end of init on purpose: the closure captures self (for the
        // announce path), which is only legal once every property is set.
        if let jobs {
            let presenter = thread
            // Same runner the button reaches. Someone talking to their Mac is
            // not looking at it, so the brake has to be sayable.
            realtime.onStopJob = { await jobs.cancel() }
            realtime.onDelegate = { [weak self] handoff in
                Task {
                    await VoiceJobBridge.run(
                        handoff, jobs: jobs, thread: presenter,
                        // The session listens in on the same seam that feeds
                        // the sheet: a permission asked while the user has
                        // their hands full has to reach the ear too.
                        onEvent: { [weak self] event in
                            onJobEvent?(event)
                            guard case .approvalRequested(let request) = event
                            else { return }
                            Task { [weak self] in
                                await self?.noteApproval(request)
                            }
                        },
                        announce: { [weak self] text in
                            await self?.jobAnnounce(text)
                        },
                        language: configProvider.current.language)
                }
            }
            realtime.onResolveApproval = { [weak self] approved in
                await self?.answerPendingApproval(approved) ?? false
            }
        }
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
        guard let request = pendingApproval else {
            Log.app("voice: approval answered with nothing pending")
            return false
        }
        pendingApproval = nil
        await jobs?.resolveApproval(
            requestId: request.requestId, approved: approved)
        return true
    }

    /// Outcome of a delegated job, spoken by the model. Queued while the
    /// agent talks or thinks; flushed on every return to listening. With no
    /// live realtime session it is dropped — the thread already shows it.
    func jobAnnounce(_ text: String) async {
        let snap = machine.snapshot
        guard snap.pipeline == .realtime,
              snap.state != .idle, snap.state != .error else { return }
        pendingAnnouncements.append(text)
        await flushAnnouncements()
    }

    private func flushAnnouncements() async {
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
        await apply(.hangUp)
    }

    public func toggleMute() async {
        await apply(.toggleMute(hasPendingAudio: await player.hasPending))
    }

    func apply(_ event: TurnEvent) async {
        let before = machine.snapshot.state
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
                await classic.submit { event in
                    await self.apply(event)
                }
            case .cancelAgentOutput:
                if machine.snapshot.pipeline == .realtime {
                    await realtime.cancelAgent()
                } else {
                    await synthesizer.stop()
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
        realtime.prepareSessionUpdate(
            config: config, history: await classic.thread.historyTurns(),
            canDelegate: jobs != nil)
        do {
            try await transport.open(key: key, url: url)
        } catch {
            await failRealtimeStart(error)
            return
        }
        startPumps()
        await realtime.flushPendingUpdate()
        if await waitForReady() {
            // Only once the session is truly ready: arming the native recognizer
            // for a turn that never opened (offline dies before here) would look
            // exactly like the classic path coming up with no network.
            await audit.begin(locale: config.language.speechLocaleIdentifier)
            armMicSilenceWatchdog()
            return
        }
        if machine.snapshot.state == .connecting {
            // Handshake never completed: unreachable from the user's side.
            await failRealtimeStart(VoiceTransportError.timeout)
        }
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

    /// Wave 9i: end of a user turn. Drive it from Apple's transcript; with
    /// nothing reliably heard, degrade to the audio OpenAI would have used.
    private func commitTurnFromNative() async {
        // Let the last native partial settle before reading it. A cancel here
        // means the session is tearing down — drop the turn, don't commit.
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            return
        }
        // v1 is hybrid-only: Apple is the ear. Without it (Speech denied) there
        // is no input path — say so once, don't spin responding to nothing.
        guard audit.isLive else {
            Log.app("voice: no native ear (Speech Recognition not authorized) "
                + "— enable it in System Settings › Privacy › Speech Recognition")
            return
        }
        let text = audit.turnText()
        audit.logTurn()
        // Mark everything recognized so far as this turn's — the recognizer
        // keeps running (a restart re-enters its ~12 s cold start).
        audit.consume()
        guard !text.isEmpty else { return }
        await realtime.commitWithText(text)
    }

    private func closeRealtime() async {
        pendingAnnouncements.removeAll()
        micSilenceTask?.cancel()
        micSilenceTask = nil
        eventTask?.cancel()
        eventTask = nil
        await audit.end()
        await realtime.close(mic: mic)
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
