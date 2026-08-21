@preconcurrency import AVFoundation
import CompanionCore
import Foundation

public actor RealtimePlayer: PCMPlaying {
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false)!

    private let makeEngine: () -> AVAudioEngine
    private let sharedEngine: () -> AVAudioEngine?
    private let startsEngine: Bool
    private let volume: Float
    private let drainBox: AudioStreamBox<Void>
    private let levelBox: AudioStreamBox<Double>

    public nonisolated let drained: AsyncStream<Void>
    public nonisolated let levels: AsyncStream<Double>

    private let graph = PlayerGraph()
    private var started = false
    private var pending = 0
    private var epoch = 0

    public init(
        makeEngine: @escaping () -> AVAudioEngine = { AVAudioEngine() },
        sharedEngine: @escaping () -> AVAudioEngine? = { nil },
        startsEngine: Bool = true,
        volume: Double = 1
    ) {
        self.makeEngine = makeEngine
        self.sharedEngine = sharedEngine
        self.startsEngine = startsEngine
        self.volume = Float(min(max(volume, 0), 1))
        let drainBox = AudioStreamBox<Void>()
        let levelBox = AudioStreamBox<Double>()
        self.drainBox = drainBox
        self.levelBox = levelBox
        self.drained = drainBox.stream
        self.levels = levelBox.stream
    }

    /// Composition-root entry point: keeps AVAudioEngine inside Services, so
    /// the app layer never handles a non-Sendable audio type.
    public init(sharedWith mic: MicCapture, volume: Double) {
        self.init(
            sharedEngine: { [weak mic] in mic?.playbackEngine },
            volume: volume)
    }

    deinit {
        drainBox.finish()
        levelBox.finish()
    }

    public var hasPending: Bool { pending > 0 }

    public func start(sharedEngine: Bool) async throws {
        epoch += 1
        pending = 0
        started = false
        graph.node?.stop()
        if graph.ownsEngine {
            graph.engine?.stop()
        } else {
            graph.detachNode()
        }
        graph.node = nil
        graph.engine = nil

        let engine: AVAudioEngine
        if sharedEngine {
            guard let shared = self.sharedEngine(), shared.isRunning else {
                Log.app("audio: player shared engine not running")
                throw VoiceTransportError.unreachable
            }
            engine = shared
            graph.engine = shared
            graph.ownsEngine = false
        } else {
            guard startsEngine else { return }
            engine = makeEngine()
            graph.engine = engine
            graph.ownsEngine = true
        }

        // Wire the graph BEFORE starting. Starting an engine with no
        // connections makes AVFoundation build its default I/O graph, which
        // touches the input device the mic engine already owns and raises an
        // ObjC exception Swift cannot catch — the process just dies. Also no
        // prepare(): it throws that same uncatchable exception, while start()
        // reports failure as a plain Swift error we can degrade from.
        let node = AVAudioPlayerNode()
        graph.node = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.format)

        if graph.ownsEngine {
            do {
                try engine.start()
            } catch {
                Log.app("audio: player engine start failed")
                graph.node = nil
                graph.engine = nil
                throw VoiceTransportError.unreachable
            }
        }
        node.volume = volume
        node.play()
        started = true
    }

    public func play(_ pcm16le24k: Data) async {
        guard started, let node = graph.node else { return }
        let frames = pcm16le24k.count / 2
        guard frames > 0,
              let buf = AVAudioPCMBuffer(
                pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        var sum: Float = 0
        pcm16le24k.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            guard let dst = buf.floatChannelData?[0] else { return }
            let count = min(frames, src.count)
            for i in 0..<count {
                let v = Float(src[i]) / 32768
                dst[i] = v
                sum += v * v
            }
        }
        let rms = min(sqrt(sum / Float(frames)) * 4, 1)
        pending += 1
        levelBox.yield(Double(rms))
        let captured = epoch
        node.scheduleBuffer(buf, completionHandler: {
            Task { await self.bufferDidFinish(epoch: captured) }
        })
    }

    public func flush() async {
        guard started, let node = graph.node else { return }
        epoch += 1
        pending = 0
        node.stop()
        node.play()
        levelBox.yield(0)
        drainBox.yield(())
    }

    public func stop() async {
        epoch += 1
        pending = 0
        started = false
        graph.node?.stop()
        graph.detachNode()
        graph.node = nil
        if graph.ownsEngine {
            graph.engine?.stop()
        }
        graph.engine = nil
    }

    private func bufferDidFinish(epoch: Int) {
        guard epoch == self.epoch else { return }
        pending -= 1
        if pending <= 0 {
            pending = 0
            levelBox.yield(0)
            drainBox.yield(())
        }
    }
}

/// HAL objects are not Sendable; the actor keeps pending, this box owns the graph.
private final class PlayerGraph: @unchecked Sendable {
    var engine: AVAudioEngine?
    var node: AVAudioPlayerNode?
    var ownsEngine = true

    deinit {
        node?.stop()
        if ownsEngine { engine?.stop() }
    }

    func detachNode() {
        guard let engine, let node, !ownsEngine else { return }
        if engine.attachedNodes.contains(node) {
            engine.detach(node)
        }
    }
}
