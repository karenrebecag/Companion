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
            await AVCaptureDevice.requestAccess(for: .audio)
        },
        watchdogDelay: TimeInterval = 1.5,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    ) {
        self.echoCancellation = echoCancellation
        self.access = access
        self.watchdogDelay = watchdogDelay
        self.sleep = sleep
    }

    deinit {
        tearDownEngine()
        frameBox.finish()
    }

    public func requestAccess() async -> Bool { await access() }

    public func start() async throws {
        try startOnce(allowRetry: true)
    }

    public func stop() async { halt() }

    public func disableVoiceProcessing() async {
        halt()
        vetoVoiceProcessing = true
        voiceProcessing = false
        muteMixer = nil
        engine = nil
    }

    private func startOnce(allowRetry: Bool) throws {
        didReceive = false
        prepareEngine()
        guard let engine else { throw VoiceTransportError.unreachable }
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            if allowRetry && voiceProcessing {
                vetoVoiceProcessing = true
                halt()
                voiceProcessing = false
                muteMixer = nil
                self.engine = nil
                try startOnce(allowRetry: false)
                return
            }
            Log.app("audio: mic input format is 0 Hz")
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
            if allowRetry && voiceProcessing {
                vetoVoiceProcessing = true
                voiceProcessing = false
                muteMixer = nil
                self.engine = nil
                try startOnce(allowRetry: false)
                return
            }
            Log.app("audio: mic engine start failed")
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
        await disableVoiceProcessing()
        do {
            try startOnce(allowRetry: false)
        } catch {
            Log.app("audio: watchdog retry failed")
        }
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
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
