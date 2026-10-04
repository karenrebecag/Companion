import AppKit
@preconcurrency import AVFoundation
import AudioToolbox
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

    package func verifyScreenCapture() async -> Bool {
        await screen.verify()
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

    package func outputVolume() async -> OutputVolume? {
        SystemOutput.read()
    }

    package func setOutputVolume(_ level: Double) async {
        SystemOutput.write(level)
    }

    /// A macOS system sound: Companion ships no audio of its own for this.
    package func playProbe() async {
        await MainActor.run {
            guard let sound = NSSound(named: NSSound.Name(SystemOutput.probeName)) else {
                Log.app("welcome: probe=missing")
                return
            }
            // A Pop still playing from the last release would drop this play.
            sound.stop()
            sound.play()
        }
    }
}

/// The default output device's volume and mute, as the menu bar's slider
/// reads and moves them. A device without a main volume (some HDMI and
/// aggregate outputs) reads as nil, and the welcome skips the check.
private enum SystemOutput {
    static let probeName = "Pop"

    static func read() -> OutputVolume? {
        guard let device = defaultDevice() else { return nil }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level)
        guard status == noErr else {
            Log.app("welcome: volume=read-failed (\(status))")
            return nil
        }
        return OutputVolume(level: min(max(Double(level), 0), 1), muted: muted(device))
    }

    static func write(_ level: Double) {
        guard level.isFinite else {
            Log.app("welcome: volume=not-finite")
            return
        }
        guard let device = defaultDevice() else { return }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            Log.app("welcome: volume=not-settable")
            return
        }
        var value = Float32(min(max(level, 0), 1))
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        if status != noErr { Log.app("welcome: volume=write-failed (\(status))") }
    }

    /// A device with no mute control is never muted.
    private static func muted(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var mute = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute)
        guard status == noErr else {
            Log.app("welcome: mute=read-failed (\(status))")
            return false
        }
        return mute != 0
    }

    private static func defaultDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            Log.app("welcome: output=none (\(status))")
            return nil
        }
        return device
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
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
