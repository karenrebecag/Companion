import AVFoundation
import CompanionCore
import Foundation

/// Short confirmation/alert tones in memory. Own engine: never the mic's.
public final class SynthesizedUISound: InterfaceSounding, @unchecked Sendable {
    private let isEnabled: @Sendable () -> Bool

    public init(isEnabled: @escaping @Sendable () -> Bool) {
        self.isEnabled = isEnabled
    }

    public func play(_ cue: SoundCue) {
        guard isEnabled() else { return }
        let frequency: Double = cue == .alert ? 660 : 880
        let gain: Float = cue == .alert ? 0.28 : 0.16
        Task.detached {
            await Self.beep(frequency: frequency, seconds: 0.12, gain: gain)
        }
    }

    private static func beep(frequency: Double, seconds: Double, gain: Float) async {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 44_100, channels: 1)
        else { return }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            Log.app("ui sound: engine failed")
            return
        }
        guard let buffer = sine(
            frequency: frequency, seconds: seconds, format: format, gain: gain)
        else {
            engine.stop()
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(buffer) { cont.resume() }
            player.play()
        }
        engine.stop()
    }

    private static func sine(
        frequency: Double, seconds: Double, format: AVAudioFormat, gain: Float
    ) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(seconds * rate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let twoPi = 2 * Double.pi
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let env = envelope(t, duration: seconds)
            samples[i] = Float(sin(twoPi * frequency * t)) * gain * env
        }
        return buffer
    }

    private static func envelope(_ t: Double, duration: Double) -> Float {
        let attack = 0.01
        let release = 0.03
        if t < attack { return Float(t / attack) }
        if t > duration - release {
            return Float(max(0, (duration - t) / release))
        }
        return 1
    }
}
