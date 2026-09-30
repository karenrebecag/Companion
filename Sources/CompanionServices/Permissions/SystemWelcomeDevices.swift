@preconcurrency import AVFoundation
import CompanionCore
import Foundation
@preconcurrency import Speech

/// The welcome's machine (Wave 16c): the four permissions, a level meter
/// that sends nothing anywhere, and the system voice for the greeting.
package struct SystemWelcomeDevices: WelcomeDevices {
    private let accessibility = AccessibilityPermission()
    private let screen = ScreenRecordingPermission()
    private let voice = WelcomeVoice()

    package init() {}

    package func granted(_ permission: WelcomePermission) async -> Bool {
        switch permission {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: accessibility.isTrusted()
        case .screenRecording: screen.isGranted()
        case .speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized
        }
    }

    package func request(_ permission: WelcomePermission) async -> Bool {
        switch permission {
        case .microphone:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            return accessibility.request()
        case .screenRecording:
            return screen.request()
        case .speechRecognition:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    package func micLevels() -> AsyncStream<Double> {
        AsyncStream { continuation in
            let meter = LevelMeter()
            guard meter.start(continuation) else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in meter.stop() }
        }
    }

    package func greet(_ text: String, language: AppLanguage) async {
        await voice.say(text, language: language)
    }
}

/// A private engine with a tap that only measures: no buffer leaves this
/// object, and it stops when the screen stops listening.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    func start(_ continuation: AsyncStream<Double>.Continuation) -> Bool {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Log.app("welcome: meter=no-input")
            return false
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            continuation.yield(Self.level(buffer))
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Log.app("welcome: meter=start-failed (\(error.localizedDescription))")
            return false
        }
        lock.withLock { self.engine = engine }
        return true
    }

    func stop() {
        let engine = lock.withLock { () -> AVAudioEngine? in
            defer { self.engine = nil }
            return self.engine
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
    }

    /// RMS mapped to 0...1 with a gain a speaking voice fills.
    private static func level(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        return min(Double(rms) * 8, 1)
    }
}

/// The system voice, before any key exists. One synthesizer kept alive for
/// the length of the line; a local one would be released mid-sentence.
private final class WelcomeVoice: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var finished: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// One line at a time: a second call cuts the first and resumes its
    /// waiter; leaving the screen (cancellation) stops the voice.
    func say(_ text: String, language: AppLanguage) async {
        let synthesizer = self.synthesizer
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let previous = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    defer { finished = continuation }
                    return finished
                }
                previous?.resume()
                synthesizer.stopSpeaking(at: .immediate)
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: language == .es ? "es-MX" : "en-US")
                synthesizer.speak(utterance)
            }
        } onCancel: {
            synthesizer.stopSpeaking(at: .immediate)
            self.resume()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        resume()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        resume()
    }

    private func resume() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { finished = nil }
            return finished
        }
        continuation?.resume()
    }
}
