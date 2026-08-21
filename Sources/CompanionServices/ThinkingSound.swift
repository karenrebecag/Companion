@preconcurrency import AVFoundation
import CompanionCore
import Foundation

/// The prototype's anti-silence: a low chord (C3+C4+G4) with a breathing
/// envelope while the model thinks. Synthesized in memory — no assets — on
/// its OWN engine: the shared mic engine belongs to the echo canceller when
/// AEC is live (ledger, Audio/AEC) and must never be borrowed for this.
public final class ThinkingSound: ThinkingSounding, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    public init() {}

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 44_100, channels: 1),
            let loop = Self.chordLoop(format: format)
        else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Fade-in instead of a click; the prototype ramped 0 -> 0.12 in 0.6 s.
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
        } catch {
            Log.app("ambience: engine failed")
            return
        }
        player.scheduleBuffer(loop, at: nil, options: .loops)
        player.play()
        self.engine = engine
        self.player = player
        ramp(engine, to: 0.12, over: 0.6)
    }

    public func stop() {
        lock.lock()
        let engine = self.engine
        let player = self.player
        self.engine = nil
        self.player = nil
        lock.unlock()
        guard let engine, let player else { return }
        // Short fade-out (0.35 s in the prototype), then tear down off-thread.
        ramp(engine, to: 0, over: 0.35) {
            player.stop()
            engine.stop()
        }
    }

    private func ramp(
        _ engine: AVAudioEngine, to target: Float, over seconds: Double,
        then completion: (@Sendable () -> Void)? = nil
    ) {
        let start = engine.mainMixerNode.outputVolume
        let steps = 12
        Task.detached {
            for step in 1 ... steps {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(seconds / Double(steps) * 1e9))
                } catch {
                    // Cancelled mid-ramp: land on the target and finish the
                    // teardown instead of leaving the engine half-faded.
                    break
                }
                let fraction = Float(step) / Float(steps)
                engine.mainMixerNode.outputVolume = start + (target - start) * fraction
            }
            engine.mainMixerNode.outputVolume = target
            completion?()
        }
    }

    /// Four seconds of the prototype's chord with a slow breathing envelope;
    /// looped seamlessly by the player.
    private static func chordLoop(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds = 4.0
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * seconds)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: frames),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        let tones: [(hz: Double, weight: Float)] = [
            (261.63, 0.55), (392.0, 0.30), (130.81, 0.15),
        ]
        for i in 0 ..< Int(frames) {
            let t = Double(i) / rate
            var sample: Float = 0
            for tone in tones {
                sample += tone.weight * Float(sin(2 * .pi * tone.hz * t))
            }
            // Breathing: one slow cycle per loop keeps the loop point silent.
            let breath = Float(0.5 - 0.5 * cos(2 * .pi * t / seconds))
            channel[i] = sample * breath * 0.5
        }
        return buffer
    }
}
