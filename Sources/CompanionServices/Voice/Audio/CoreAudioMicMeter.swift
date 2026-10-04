@preconcurrency import AVFoundation
import CompanionCore
import Foundation

/// Counts probe starts so a start that was overtaken knows it was. Only the
/// latest start may keep an engine; `invalidate` retires them all.
package final class ProbeGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    package init() {}

    package func begin() -> Int {
        lock.withLock {
            current += 1
            return current
        }
    }

    package func invalidate() { _ = begin() }

    package func isCurrent(_ generation: Int) -> Bool {
        lock.withLock { current == generation }
    }
}

/// A second, plain engine for the settings probe. It never enables voice
/// processing and it installs the tap before start: `prepare()` on a graph
/// with no tap raises an Objective-C exception. Starts are serialized by a
/// generation: the permission await in `start` is a gap in which a later
/// start or a stop can overtake it.
package final class CoreAudioMicMeter: MicMeter, @unchecked Sendable {
    private let lock = NSLock()
    private let generation = ProbeGeneration()
    private var engine: AVAudioEngine?
    private var handler: (@Sendable (Double) -> Void)?

    package init() {}

    package var microphoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    package func onLevel(_ handler: @escaping @Sendable (Double) -> Void) {
        lock.withLock { self.handler = handler }
    }

    package func stop() {
        generation.invalidate()
        Self.shutDown(lock.withLock { takeEngine() })
    }

    package func start(target: MicTarget) async -> MicProbeFault? {
        let mine = generation.begin()
        Self.shutDown(lock.withLock { takeEngine() })
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation.isCurrent(mine) else { return nil }
        guard allowed else { return .blocked }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let unit = input.audioUnit,
           !AudioDevicePin.pinInput(unit, target: target), target.deviceID != nil {
            return .failed
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return .noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.emit(Self.level(buffer), generation: mine)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.app("audio: mic probe failed: \(error)")
            return .failed
        }
        let kept = lock.withLock { () -> Bool in
            guard generation.isCurrent(mine) else { return false }
            self.engine = engine
            return true
        }
        if !kept { Self.shutDown(engine) }
        return nil
    }

    /// Caller holds `lock`.
    private func takeEngine() -> AVAudioEngine? {
        defer { engine = nil }
        return engine
    }

    private static func shutDown(_ engine: AVAudioEngine?) {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
    }

    private func emit(_ level: Double, generation mine: Int) {
        guard generation.isCurrent(mine) else { return }
        let handler = lock.withLock { self.handler }
        handler?(level)
    }

    /// Same 0–1 scale as the voice meter, so the silence line matches a level
    /// the rest of the app already treats as audible.
    private static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        if let channels = buffer.floatChannelData {
            return rms(frames) { Double(channels[0][$0]) }
        }
        if let channels = buffer.int16ChannelData {
            return rms(frames) { Double(channels[0][$0]) / 32768 }
        }
        return 0
    }

    private static func rms(_ frames: Int, _ sample: (Int) -> Double) -> Double {
        var sum = 0.0
        for index in 0..<frames {
            let value = sample(index)
            sum += value * value
        }
        return min(sqrt(sum / Double(frames)) * WaveformHistory.micMeterGain, 1)
    }
}
