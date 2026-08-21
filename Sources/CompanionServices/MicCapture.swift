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
public final class MicCapture: MicCapturing, @unchecked Sendable {
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
    private var vetoVoiceProcessing = false
    private var running = false
    private var didReceive = false
    private var tapInstalled = false
    private var watchdogRetryCount = 0

    public var frames: AsyncStream<MicFrame> { frameBox.stream }
    public var hasEchoCancellation: Bool { voiceProcessing }
    public var receivedBuffer: Bool { didReceive }
    /// Player joins this engine when VPIO is live so AEC hears the agent.
    public var playbackEngine: AVAudioEngine? { voiceProcessing ? engine : nil }

    public init(
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
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.echoCancellation = echoCancellation
        self.access = access
        self.vetoStore = vetoStore
        self.vetoVoiceProcessing = vetoStore.isVetoed
        self.watchdogDelay = watchdogDelay
        self.sleep = sleep
    }

    deinit {
        tearDownEngine()
        frameBox.finish()
    }

    public func requestAccess() async -> Bool { await access() }

    public func start() async throws {
        do {
            try startOnce()
        } catch VoiceTransportError.unreachable where voiceProcessing {
            try await retryWithoutVP()
        }
    }

    /// Ported from the prototype's Mic.retryWithoutVP, its most expensive
    /// scar: VPIO tears its aggregate device down ASYNCHRONOUSLY, the HAL
    /// reports 0 Hz meanwhile, and an engine that saw 0 Hz keeps it forever.
    /// Probe with a fresh engine each time, up to ~2 s, before giving up.
    private func retryWithoutVP() async throws {
        Log.app("audio: retrying without echo cancellation (veto persisted)")
        vetoVoiceProcessing = true
        vetoStore.isVetoed = true
        voiceProcessing = false
        muteMixer = nil
        engine = nil
        var waited = 0
        while waited < 20 {
            let probe = AVAudioEngine()
            if probe.inputNode.inputFormat(forBus: 0).sampleRate > 0 { break }
            waited += 1
            try await sleep(0.1)
        }
        Log.app("audio: HAL back after \(waited * 100) ms")
        try startOnce()
    }

    public func stop() async { halt() }

    public func disableVoiceProcessing() async {
        halt()
        vetoVoiceProcessing = true
        vetoStore.isVetoed = true
        voiceProcessing = false
        muteMixer = nil
        engine = nil
    }

    private func startOnce() throws {
        didReceive = false
        prepareEngine()
        guard let engine else { throw VoiceTransportError.unreachable }
        let input = engine.inputNode
        if !voiceProcessing, let unit = input.audioUnit {
            let pinned = AudioDevicePin.pinInput(unit)
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

        // Watchdog for Voice Processing: if no buffers arrive within watchdogDelay,
        // veto VP and retry once. This detects the VPIO bug where the engine starts
        // but the tap never fires.
        if voiceProcessing && watchdogRetryCount < 1 {
            Task { [weak self] in
                await self?.runWatchdog()
            }
        }
    }

    private func runWatchdog() async {
        do {
            try await sleep(watchdogDelay)
        } catch {
            // Cancellation during sleep; watchdog exits.
            return
        }
        let action = MicWatchdog.decide(
            running: running,
            voiceProcessing: voiceProcessing,
            receivedBuffer: didReceive,
            alreadyRetried: watchdogRetryCount > 0)
        guard action == .vetoAndRetry else { return }

        watchdogRetryCount += 1
        Log.app("audio: watchdog triggered, disabling Voice Processing and retrying")
        halt()
        do {
            // Same path as a failed start: vetoing VPIO tears the aggregate
            // device down asynchronously, so the retry must wait for the HAL.
            try await retryWithoutVP()
        } catch {
            Log.app("audio: watchdog retry failed")
        }
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
        if engine == nil { engine = AVAudioEngine() }
        let want = echoCancellation && !vetoVoiceProcessing
        guard want != voiceProcessing else { return }
        rebuildEngine()
        guard want, let engine else { return }
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            // Pin BOTH VPIO buses to the built-in pair before the unit
            // initializes: letting it aggregate the system defaults fails
            // with -10875 when a virtual device (Teams) sits in the chain.
            if let unit = engine.inputNode.audioUnit,
               let pair = AudioDevicePin.builtInPair() {
                let pinned = AudioDevicePin.pin(
                    unit, input: pair.input, output: pair.output)
                Log.app("audio: vpio device pin \(pinned ? "ok" : "FAILED")")
            } else {
                Log.app("audio: vpio device pin unavailable")
            }
            tameVoiceProcessing(engine)
            voiceProcessing = true
        } catch {
            Log.app("audio: voice processing enable failed")
            rebuildEngine()
        }
    }

    private func rebuildEngine() {
        tearDownEngine()
        engine = AVAudioEngine()
        muteMixer = nil
        voiceProcessing = false
    }

    private func halt() {
        running = false
        tearDownEngine()
    }

    private func tearDownEngine() {
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
            return min(sqrt(sum / Double(count)) * 6, 1)
        }
    }
}

private final class EncoderBox: @unchecked Sendable {
    private var encoder = RealtimeEncoder()
    func encode(_ buffer: AVAudioPCMBuffer) -> Data? { encoder.encode(buffer) }
}
