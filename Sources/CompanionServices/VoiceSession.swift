import CompanionCore
import Foundation

public actor VoiceSession: VoiceControlling {
    public nonisolated let snapshots: AsyncStream<TurnSnapshot>
    public nonisolated let levels: AsyncStream<VoiceLevels>

    private var machine = TurnMachine()
    private let transport: any VoiceTransport
    private let mic: any MicCapturing
    private let player: any PCMPlaying
    private let transcriber: any Transcriber
    private let synthesizer: any SpeechSynthesizer
    private let secrets: any SecretStore
    private let config: Config
    private let now: @Sendable () -> TimeInterval
    private let readyTimeout: TimeInterval
    private let realtime: RealtimeRuntime
    private let classic: ClassicRuntime
    private let snapBox: AudioStreamBox<TurnSnapshot>
    private let levelBox: AudioStreamBox<VoiceLevels>

    private var eventTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var playerLevelTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private let reachability: any ReachabilityProbing
    private let micSilenceTimeout: TimeInterval
    private var micSilenceTask: Task<Void, Never>?
    private var lastMic = 0.0
    private var lastAgent = 0.0
    private var reconnectAttempted = false

    public init(
        transport: any VoiceTransport,
        mic: any MicCapturing,
        player: any PCMPlaying,
        transcriber: any Transcriber,
        synthesizer: any SpeechSynthesizer,
        chat: any ChatProvider,
        secrets: any SecretStore,
        thread: any ConversationPresenting,
        config: Config,
        reachability: any ReachabilityProbing = NetworkReachability(),
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
        self.config = config
        self.reachability = reachability
        self.micSilenceTimeout = micSilenceTimeout
        self.now = now
        self.readyTimeout = readyTimeout
        self.realtime = RealtimeRuntime(
            transport: transport, player: player, thread: thread)
        self.classic = ClassicRuntime(
            transcriber: transcriber, synthesizer: synthesizer,
            chat: chat, thread: thread)
        let snapBox = AudioStreamBox<TurnSnapshot>()
        let levelBox = AudioStreamBox<VoiceLevels>()
        self.snapBox = snapBox
        self.levelBox = levelBox
        self.snapshots = snapBox.stream
        self.levels = levelBox.stream
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

    private func apply(_ event: TurnEvent) async {
        let before = machine.snapshot.state
        let effects = machine.handle(event, at: now())
        // Voice failures are invisible without a trace of the turn: the log is
        // the only witness of what the server and the audio graph did.
        if machine.snapshot.state != before {
            Log.app("voice: \(before) -> \(machine.snapshot.state)")
        }
        snapBox.yield(machine.snapshot)
        await perform(effects)
    }

    private func perform(_ effects: [TurnEffect]) async {
        for effect in effects {
            switch effect {
            case .openRealtimeSession:
                await openRealtimeSession()
            case .requestClassicListen:
                await classic.requestListen(mic: mic) { event in
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
                await realtime.commitAndRespond()
            case .clearInputAudio:
                await realtime.clearInputAudio()
            case .setMicEnabled(let on):
                realtime.micEnabled = on
            case .beginSpeechStream:
                await synthesizer.begin()
            case .finishSpeechStream:
                await synthesizer.finish()
            case .noteFailure(let reason):
                await classic.thread.appendStatus(ClassicRuntime.status(reason))
            }
        }
    }

    private func openRealtimeSession() async {
        realtime.reset()
        reconnectAttempted = false
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
        realtime.prepareSessionUpdate(
            config: config, history: await classic.thread.historyTurns())
        do {
            try await transport.open(key: key, url: url)
        } catch {
            await failRealtimeStart(error)
            return
        }
        startPumps()
        await realtime.flushPendingUpdate()
        if await waitForReady() {
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

    private func closeRealtime() async {
        micSilenceTask?.cancel()
        micSilenceTask = nil
        eventTask?.cancel()
        eventTask = nil
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

    private func startPumps() {
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
    }

    private func pumpEvents() async {
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

    private func reconnectRealtimeSession() async {
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

    private func pumpFrames() async {
        for await frame in mic.frames {
            if Task.isCancelled { return }
            lastMic = frame.rms
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            switch machine.snapshot.pipeline {
            case .classic:
                await transcriber.append(frame)
            case .realtime:
                let aec = await mic.hasEchoCancellation
                let snap = machine.snapshot
                guard realtime.shouldForward(
                    frame,
                    muted: snap.muted,
                    aec: aec,
                    state: snap.state,
                    echoGuarded: machine.isEchoGuarded(at: now())
                ) else { continue }
                await realtime.append(frame)
            case nil:
                continue
            }
        }
    }

    private func pumpDrained() async {
        for await _ in player.drained {
            if Task.isCancelled { return }
            await apply(.playerDrained)
        }
    }

    private func pumpPlayerLevels() async {
        for await value in player.levels {
            if Task.isCancelled { return }
            lastAgent = value
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
        }
    }

    private func pumpSpeech() async {
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

    private func openAIKey() -> String? {
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
