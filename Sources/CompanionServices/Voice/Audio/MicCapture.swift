@preconcurrency import AVFoundation
import CompanionCore
import Foundation

/// AsyncStream and its Continuation are not Sendable; this box isolates them
/// from concurrent access via manual synchronization in MicCapture.
final class AudioStreamBox<T: Sendable>: @unchecked Sendable {
    let stream: AsyncStream<T>
    private let continuation: AsyncStream<T>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: T.self)
    }

    func yield(_ value: T) { continuation.yield(value) }
    func finish() { continuation.finish() }
}

/// AVAudioEngine and AVAudioMixerNode are not Sendable; this class isolates them
/// and protects access with guard checks and Task synchronization.
package final class MicCapture: MicCapturing, @unchecked Sendable {
    private let access: @Sendable () async -> Bool
    private let echoCancellation: Bool
    private let vetoStore: AECVetoStoring
    private let watchdogDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let frameBox = AudioStreamBox<MicFrame>()
    private let encoderBox = EncoderBox()
    private var engine: AVAudioEngine?
    private var muteMixer: AVAudioMixerNode?
    private var voiceProcessing = false
    /// What the last start attempt used. `voiceProcessing` is cleared by the
    /// teardown a failed start runs, so the retry decision cannot read it.
    private var attemptedVoiceProcessing = false
    private var vetoVoiceProcessing = false
    private var running = false
    private var didReceive = false
    private var tapInstalled = false
    private var watchdogRetryCount = 0
    /// What the live engine was built and pinned for. Nil once it is torn
    /// down: the pin does not survive that, so the next start pins again.
    private var built: MicEngineBuild?
    /// Voice processing could not pin the chosen input. Lasts until the next
    /// start from outside: unlike a failed init it says nothing lasting about
    /// the machine, so it is never written to the veto store.
    private var voiceProcessingOffThisSession = false
    private let routing: MicRouting
    private var follower: MicRouteFollower?
    private var configObserver: (any NSObjectProtocol)?
    /// Every mutable field above is written on this queue, but `handleTap`
    /// still reads `running` and `didReceive` from the engine's audio thread
    /// without it; making those atomics is a follow-up. Route triggers arrive
    /// on the CoreAudio main queue and on the engine's own thread; they only
    /// enqueue here, so a stop, a restart and the watchdog never interleave.
    private let queue = DispatchQueue(label: "companion.mic-capture")
    /// Its own lock: a trigger stamps its ticket from a foreign thread without
    /// waiting on `queue`, which may be inside `engine.stop()`.
    private let gateLock = NSLock()
    private var gate = MicRestartGate()
    private let restartFeed = RestartFeed()

    package var frames: AsyncStream<MicFrame> { frameBox.stream }
    package func subscribeRestarts() -> AsyncStream<MicRestart> { restartFeed.open() }
    // The getters below block on `queue`, which can be inside `engine.stop()`:
    // never read them from the MainActor.
    package var hasEchoCancellation: Bool { queue.sync { voiceProcessing } }
    package var receivedBuffer: Bool { queue.sync { didReceive } }
    /// Player joins this engine when VPIO is live so AEC hears the agent.
    package var playbackEngine: AVAudioEngine? { queue.sync { voiceProcessing ? engine : nil } }

    package init(
        echoCancellation: Bool = false,
        access: @escaping @Sendable () async -> Bool = {
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            Log.app("audio: mic permission \(ok ? "granted" : "DENIED")")
            return ok
        },
        // The prototype persisted this veto on purpose: on a machine where
        // VPIO cannot init (kAUInitialize -10875, e.g. aggregate inputs),
        // retrying it on every session only poisons the HAL for the plain
        // engine that follows. One failed attempt disables AEC until the
        // store is cleared (Settings toggle, Wave 5).
        vetoStore: AECVetoStoring = UserDefaultsAECVeto(),
        watchdogDelay: TimeInterval = 1.5,
        routing: MicRouting = .live,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.echoCancellation = echoCancellation
        self.access = access
        self.vetoStore = vetoStore
        self.vetoVoiceProcessing = vetoStore.isVetoed
        self.watchdogDelay = watchdogDelay
        self.routing = routing
        self.sleep = sleep
    }

    deinit {
        tearDownEngine()
        frameBox.finish()
        restartFeed.finish()
    }

    package func requestAccess() async -> Bool { await access() }

    package func start() async throws {
        // One critical section for the attempt, the decision and the ticket:
        // the session actor is reentrant across this call, so a stop can land
        // between any two of them.
        let retry = try queue.sync { () -> (persistVeto: Bool, ticket: Int)? in
            // An outside start supersedes any retry still in flight: its ticket
            // must not outlive the engine this start is about to own.
            gateLock.withLock { gate.invalidate() }
            voiceProcessingOffThisSession = false
            do {
                try startOnce()
                return nil
            } catch VoiceTransportError.unreachable {
                let plan = plainRetry()
                guard plan.retry else { throw VoiceTransportError.unreachable }
                return (plan.persistVeto, currentTicket())
            }
        }
        guard let retry else { return }
        try await retryWithoutVP(persistVeto: retry.persistVeto, ticket: retry.ticket)
    }

    /// Read on the queue: the flags it decides on belong to it.
    private func plainRetry() -> MicPlainRetry {
        MicEnginePlan.plainRetry(
            attemptedVoiceProcessing: attemptedVoiceProcessing,
            offThisSession: voiceProcessingOffThisSession)
    }

    private func currentTicket() -> Int { gateLock.withLock { gate.ticket } }

    /// Ported from the prototype's Mic.retryWithoutVP, its most expensive
    /// scar: VPIO tears its aggregate device down ASYNCHRONOUSLY, the HAL
    /// reports 0 Hz meanwhile, and an engine that saw 0 Hz keeps it forever.
    /// Probe with a fresh engine each time, up to ~2 s, before giving up.
    ///
    /// `ticket` was stamped in the critical section that decided to retry,
    /// after its halt. It is checked again in both blocks: a stop between the
    /// decision and either of them must not veto, rebuild or reopen anything.
    private func retryWithoutVP(persistVeto: Bool, ticket: Int) async throws {
        Log.app("audio: retrying without echo cancellation (veto persisted: \(persistVeto))")
        try queue.sync {
            // `running` too: a fresh outside start that already owns a live
            // engine must not have it discarded under its tap.
            guard !running, gateLock.withLock({ gate.stillCurrent(ticket) }) else {
                throw VoiceTransportError.closed
            }
            switch MicEnginePlan.vetoScope(persistVeto: persistVeto) {
            case .lasting:
                vetoVoiceProcessing = true
                vetoStore.isVetoed = true
            case .thisSession:
                voiceProcessingOffThisSession = true
            }
            discardEngine()
        }
        try await waitForHAL()
        try queue.sync {
            guard gateLock.withLock({ gate.stillCurrent(ticket) }) else {
                throw VoiceTransportError.closed
            }
            try startOnce()
        }
    }

    private func waitForHAL() async throws {
        var waited = 0
        while waited < 20 {
            let probe = AVAudioEngine()
            if probe.inputNode.inputFormat(forBus: 0).sampleRate > 0 { break }
            waited += 1
            try await sleep(0.1)
        }
        Log.app("audio: HAL back after \(waited * 100) ms")
    }

    package func stop() async { queue.sync { halt() } }

    /// Wave 12c: build the engine and enable voice processing at boot so
    /// the first hold does not pay for it. Only with the mic already
    /// granted: a permission prompt at launch is not a warm-up. Never
    /// `engine.prepare()` here: on a graph with no tap installed it raises
    /// an Objective-C exception and took the whole app down (seen live
    /// 2026-09-06); `start()` prepares once the tap exists.
    package func prewarm() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            Log.app("prewarm: mic not granted yet, engine left cold")
            return
        }
        queue.sync {
            guard !running else { return }
            prepareEngine()
        }
    }

    package func disableVoiceProcessing() async {
        queue.sync {
            halt()
            vetoVoiceProcessing = true
            vetoStore.isVetoed = true
            discardEngine()
        }
    }

    private func startOnce() throws {
        guard MicStartPlan.decide(running: running, tapInstalled: tapInstalled) == .start else {
            Log.app("audio: mic start ignored — already running with a tap installed")
            return
        }
        didReceive = false
        prepareEngine()
        attemptedVoiceProcessing = voiceProcessing
        guard let engine else { throw VoiceTransportError.unreachable }
        let input = engine.inputNode
        if !voiceProcessing, let unit = input.audioUnit {
            // The device prepareEngine resolved, so both paths read the same one.
            let pinned = built?.input.map { AudioDevicePin.pinInput(unit, device: $0) } ?? false
            Log.app("audio: plain input pin \(pinned ? "ok" : "FAILED")")
        }
        let format = input.inputFormat(forBus: 0)
        Log.app("audio: mic start vp=\(voiceProcessing) "
                + "format=\(Int(format.sampleRate))Hz ch=\(format.channelCount)")
        guard format.sampleRate > 0 else {
            Log.app("audio: mic input format is 0 Hz — graph unusable")
            throw VoiceTransportError.unreachable
        }

        // VPIO is duplex: without an output path the tap never fires.
        if voiceProcessing && muteMixer == nil {
            let mute = AVAudioMixerNode()
            engine.attach(mute)
            engine.connect(input, to: mute, format: format)
            mute.outputVolume = 0
            engine.connect(mute, to: engine.mainMixerNode, format: format)
            muteMixer = mute
        }

        // Never install a second tap over a live one: installTap on a bus
        // that already has one raises an ObjC exception, uncatchable in
        // Swift (live crash 2026-09-23). tearDownEngine keeps this false in
        // the normal path; this is the belt for whatever rebuilds the graph
        // without going through it.
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            halt()
            Log.app("audio: mic engine start failed: \(error)")
            throw VoiceTransportError.unreachable
        }
        running = true
        followRoute(engine)

        // Watchdog for Voice Processing: if no buffers arrive within watchdogDelay,
        // veto VP and retry once. This detects the VPIO bug where the engine starts
        // but the tap never fires.
        if voiceProcessing && watchdogRetryCount < 1 {
            // This engine's own ticket: a stop or a restart since retires it.
            let ticket = currentTicket()
            Task { [weak self] in
                await self?.runWatchdog(ticket: ticket)
            }
        }
    }

    private func runWatchdog(ticket watched: Int) async {
        do {
            try await sleep(watchdogDelay)
        } catch {
            // Cancellation during sleep; watchdog exits.
            return
        }
        let retryTicket = queue.sync { () -> Int? in
            // Raw equality, not admit: the watchdog must not spend the ticket
            // a route change may still need.
            guard gateLock.withLock({ gate.stillCurrent(watched) }) else { return nil }
            let action = MicWatchdog.decide(
                running: running,
                voiceProcessing: voiceProcessing,
                receivedBuffer: didReceive,
                alreadyRetried: watchdogRetryCount > 0)
            guard action == .vetoAndRetry else { return nil }
            watchdogRetryCount += 1
            halt()
            return currentTicket()
        }
        guard let retryTicket else { return }
        Log.app("audio: watchdog triggered, disabling Voice Processing and retrying")
        // Same path as a failed start: vetoing VPIO tears the aggregate
        // device down asynchronously, so the retry must wait for the HAL. It
        // also publishes the outcome, which a player on the halted VP engine
        // needs to re-attach or the session to fail.
        await restartWithoutVP(persistVeto: true, ticket: retryTicket)
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        if !didReceive {
            Log.app("audio: first mic buffer (\(buffer.frameLength) frames)")
        }
        didReceive = true
        guard running else { return }
        guard let pcm = encoderBox.encode(buffer) else { return }
        frameBox.yield(MicFrame(pcm16le24k: pcm, rms: Self.rms(pcm)))
    }

    private func prepareEngine() {
        let input = routing.inputDevice(routing.target())
        let want = echoCancellation && !vetoVoiceProcessing && !voiceProcessingOffThisSession
        let action = MicEnginePlan.decide(
            built: engine == nil ? nil : built, wantedInput: input, wantVoiceProcessing: want)
        guard action == .rebuild else { return }
        rebuildEngine()
        if want, let engine { enableVoiceProcessing(on: engine, input: input) }
        built = MicEngineBuild(input: input, voiceProcessing: voiceProcessing)
    }

    private func enableVoiceProcessing(on engine: AVAudioEngine, input: UInt32?) {
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            // Pin BOTH buses before the unit initializes: letting it aggregate
            // the system defaults fails with -10875 when a virtual device
            // (Teams) sits in the chain. The input is the chosen device; the
            // output stays the built-in speaker when there is one.
            guard let unit = engine.inputNode.audioUnit, let input,
                  let output = AudioDevicePin.captureOutput(),
                  AudioDevicePin.pin(unit, input: input, output: output)
            else {
                Log.app("audio: vpio device pin failed, plain input for this session")
                // The teardown only undoes VPIO once `voiceProcessing` is set,
                // which is not yet: switch it off here or the aggregate device
                // outlives the engine and the plain one reads 0 Hz.
                do {
                    try engine.inputNode.setVoiceProcessingEnabled(false)
                } catch {
                    Log.app("audio: voice processing disable failed")
                }
                voiceProcessingOffThisSession = true
                rebuildEngine()
                return
            }
            Log.app("audio: vpio device pin ok")
            tameVoiceProcessing(engine)
            voiceProcessing = true
        } catch {
            Log.app("audio: voice processing enable failed")
            // Same as a failed pin: the plain start that follows may see the
            // HAL at 0 Hz while VPIO's aggregate tears down.
            voiceProcessingOffThisSession = true
            rebuildEngine()
        }
    }

    /// While the mic is open, a device that appears or goes away moves capture
    /// instead of leaving it on a dead input. The engine stopping by itself
    /// (its device vanished) is the same event seen from the other side.
    private func followRoute(_ engine: AVAudioEngine) {
        follower?.end()
        follower = routing.port().map { port in
            MicRouteFollower(port: port, preference: routing.preference) { [weak self] _ in
                self?.routeChanged(onlyIfEngineStopped: false)
            }
        }
        follower?.begin()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.routeChanged(onlyIfEngineStopped: true)
        }
    }

    /// Any thread. The ticket is taken here, at trigger time, so the second
    /// trigger of one unplug carries the same one and is dropped by the gate.
    private func routeChanged(onlyIfEngineStopped: Bool) {
        let ticket = gateLock.withLock { gate.ticket }
        queue.async { [weak self] in
            guard let self else { return }
            if onlyIfEngineStopped {
                let stopped = MicRouteFollower.shouldRestartAfterConfigurationChange(
                    running: running, engineRunning: engine?.isRunning ?? false)
                guard stopped else { return }
            }
            restartIfNeeded(ticket: ticket)
        }
    }

    private func restartIfNeeded(ticket: Int) {
        let admitted = gateLock.withLock { gate.admit(ticket: ticket, running: running) }
        guard admitted else { return }
        Log.app("audio: input changed while open, restarting capture")
        halt()
        do {
            try startOnce()
            restartFeed.yield(.restarted(echoCancellation: voiceProcessing))
        } catch {
            Log.app("audio: restart on the new input failed: \(error)")
            let plan = plainRetry()
            guard plan.retry else { return restartFeed.yield(.failed) }
            // Stamped here, in the block that decided: a hop to a Task first
            // would let a stop land before the ticket is read.
            let ticket = currentTicket()
            Task { [weak self] in
                await self?.restartWithoutVP(persistVeto: plan.persistVeto, ticket: ticket)
            }
        }
    }

    private func restartWithoutVP(persistVeto: Bool, ticket: Int) async {
        do {
            try await retryWithoutVP(persistVeto: persistVeto, ticket: ticket)
            restartFeed.yield(.restarted(echoCancellation: queue.sync { voiceProcessing }))
        } catch VoiceTransportError.closed {
            // A stop retired the retry: the session closed the mic on purpose.
            Log.app("audio: restart without echo cancellation cancelled by a stop")
        } catch {
            Log.app("audio: restart without echo cancellation failed: \(error)")
            restartFeed.yield(.failed)
        }
    }

    private func rebuildEngine() {
        tearDownEngine()
        engine = AVAudioEngine()
        muteMixer = nil
        voiceProcessing = false
        built = nil
    }

    private func discardEngine() {
        // Dropping a live engine leaves its tap firing and `running` true.
        // VP is deliberately not disabled here: the callers veto it themselves.
        if let engine {
            if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        muteMixer = nil
        voiceProcessing = false
        built = nil
    }

    private func halt() {
        running = false
        // Queued restarts were raised against a mic that is no longer open.
        gateLock.withLock { gate.invalidate() }
        tearDownEngine()
    }

    private func tearDownEngine() {
        follower?.end()
        follower = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        guard let engine else { return }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        if voiceProcessing {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(false)
            } catch {
                Log.app("audio: voice processing disable failed")
            }
        }
        // VPIO is off now and its pin went with it. Leaving these set made the
        // next start reuse an engine that no longer matched them.
        voiceProcessing = false
        muteMixer = nil
        built = nil
    }

    private func tameVoiceProcessing(_ engine: AVAudioEngine) {
        engine.inputNode.isVoiceProcessingAGCEnabled = false
        engine.inputNode.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false, duckingLevel: .min)
    }

    private static func rms(_ pcm16: Data) -> Double {
        let n = pcm16.count / 2
        guard n > 0 else { return 0 }
        return pcm16.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            var sum: Double = 0
            let count = min(n, src.count)
            for i in 0..<count {
                let v = Double(src[i]) / 32768
                sum += v * v
            }
            return min(sqrt(sum / Double(count)) * WaveformHistory.micMeterGain, 1)
        }
    }
}

private final class EncoderBox: @unchecked Sendable {
    private var encoder = RealtimeEncoder()
    func encode(_ buffer: AVAudioPCMBuffer) -> Data? { encoder.encode(buffer) }
}

/// Hands each session a fresh stream: one consumer at a time, and a cancelled
/// one must not leave the next session listening to a finished stream.
private final class RestartFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<MicRestart>.Continuation?

    func open() -> AsyncStream<MicRestart> {
        let (stream, next) = AsyncStream.makeStream(of: MicRestart.self)
        let previous = lock.withLock { () -> AsyncStream<MicRestart>.Continuation? in
            defer { continuation = next }
            return continuation
        }
        previous?.finish()
        return stream
    }

    func yield(_ event: MicRestart) { lock.withLock { continuation }?.yield(event) }
    func finish() { lock.withLock { continuation }?.finish() }
}
