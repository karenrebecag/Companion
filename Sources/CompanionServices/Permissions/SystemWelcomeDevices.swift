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
    private let music = WelcomeMusicPlayer()

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

    package func setMusic(playing: Bool) async {
        if playing { music.start() } else { music.stop() }
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
        // The meter has to listen to the microphone the app will use: the
        // format below is read from whichever device the unit is pinned to.
        if let unit = input.audioUnit {
            let target = MicChoice.target(
                preference: MicDevices.store.load(), snapshot: AudioDevicePin.inputSnapshot())
            if !AudioDevicePin.pinInput(unit, target: target) {
                Log.app("welcome: meter could not pin the chosen input")
            }
        }
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

/// The welcome's background pad. Incredible ships a produced track
/// (createFirstRunIO-Dv00aAyF.js @35812); this one is synthesized in memory so
/// the repo carries no audio asset and no licence (research brief,
/// onboarding-music D1). Its OWN engine, like ThinkingSound: the shared mic
/// engine belongs to the echo canceller. The system output device, volume and
/// mute govern it; nothing here touches them.
private final class WelcomeMusicPlayer: @unchecked Sendable {
    private static let fadeIn = 1.2
    private static let fadeOut = 0.6

    /// Synthesized once: an 8 s pass over four voices is too slow to repeat
    /// every time the toggle flips.
    private static let loop = WelcomeMusicLoop.samples()

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var fading: Task<Void, Never>?
    private var routeObserver: NSObjectProtocol?
    /// What the welcome last asked for, so a route change restarts the music
    /// only while it is still wanted.
    private var wanted = false

    func start() {
        // Built before taking the lock: the copy must not block a stop.
        guard let loop = Self.buffer() else { return }
        lock.withLock {
            wanted = true
            guard engine == nil else { return }
            launch(loop)
        }
    }

    func stop() {
        let retired = lock.withLock { () -> Retired? in
            wanted = false
            return retire()
        }
        guard let retired else { return }
        // Awaiting the fade-in (cancelled) first makes the fade-out start
        // from the volume it actually reached, so there is no jump.
        Task.detached {
            retired.fading?.cancel()
            await retired.fading?.value
            await Self.ramp(retired.engine, to: 0, over: Self.fadeOut) {
                retired.player.stop()
                retired.engine.stop()
            }.value
        }
    }

    private struct Retired {
        let engine: AVAudioEngine
        let player: AVAudioPlayerNode
        let fading: Task<Void, Never>?
    }

    /// Caller holds the lock.
    private func launch(_ loop: AVAudioPCMBuffer) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: loop.format)
        engine.mainMixerNode.outputVolume = 0
        // Registered before start(): a route change landing during start would
        // otherwise leave a stopped engine that blocks every later start.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in self?.routeChanged(engine) }
        do {
            try engine.start()
        } catch {
            NotificationCenter.default.removeObserver(observer)
            // No output device is not a reason to block the welcome.
            Log.app("welcome: music=start-failed (\(error.localizedDescription))")
            return
        }
        player.scheduleBuffer(loop, at: nil, options: .loops)
        player.play()
        self.engine = engine
        self.player = player
        routeObserver = observer
        fading = Self.ramp(engine, to: 1, over: Self.fadeIn)
    }

    /// A route change (headphones, another output) stops the engine silently;
    /// without this the stale engine would block every later start.
    private func routeChanged(_ changed: AVAudioEngine) {
        // Built before taking the lock, like start().
        let loop = Self.buffer()
        // Retire and relaunch in ONE acquisition: a stop() between the two
        // would otherwise be undone by a relaunch nothing stops. `wanted` is
        // only ever changed by start()/stop().
        lock.withLock {
            let restart = WelcomeMusicRestart.restarts(wanted: wanted, sameEngine: engine === changed)
            guard engine === changed else { return }
            let retired = retire()
            retired?.fading?.cancel()
            retired?.player.stop()
            retired?.engine.stop()
            if restart, let loop { launch(loop) }
        }
    }

    /// Caller holds the lock. Clears the state and the observer.
    private func retire() -> Retired? {
        defer {
            engine = nil
            player = nil
            fading = nil
            if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
            routeObserver = nil
        }
        guard let engine, let player else { return nil }
        return Retired(engine: engine, player: player, fading: fading)
    }

    private static func buffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: WelcomeMusicLoop.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(loop.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(loop.count)
        for (index, sample) in loop.enumerated() { channel[index] = sample }
        return buffer
    }

    /// Linear steps on the mixer, like ThinkingSound: the engine has no
    /// native ramp. A cancelled ramp leaves the volume where it was.
    private static func ramp(
        _ engine: AVAudioEngine, to target: Float, over seconds: Double,
        then completion: (@Sendable () -> Void)? = nil
    ) -> Task<Void, Never> {
        let from = engine.mainMixerNode.outputVolume
        let steps = 24
        return Task.detached {
            for step in 1 ... steps {
                do {
                    try await Task.sleep(nanoseconds: UInt64(seconds / Double(steps) * 1e9))
                } catch {
                    return
                }
                engine.mainMixerNode.outputVolume = from + (target - from) * Float(step) / Float(steps)
            }
            engine.mainMixerNode.outputVolume = target
            completion?()
        }
    }
}

/// Whether a route change relaunches the pad. Pure so the stop-in-between
/// race has a test without a speaker.
package enum WelcomeMusicRestart {
    package static func restarts(wanted: Bool, sameEngine: Bool) -> Bool {
        wanted && sameEngine
    }
}

/// The pad as samples: a soft major-seventh chord (A2, E3, G#3, C#4) whose
/// voices breathe at different slow rates. Every frequency is snapped to a
/// whole number of cycles per loop and every breath divides the loop length,
/// so the last sample flows into the first with no click. Pure, so a test can
/// check the loop without a speaker.
package enum WelcomeMusicLoop {
    package static let sampleRate = 44_100.0
    package static let seconds = 8.0
    /// The mixer is left at full scale and fades 0...1, so this is the one
    /// place the pad's loudness lives: quiet enough to sit under the voice.
    package static let level: Float = 0.08

    private struct Voice {
        let hz: Double
        let weight: Double
        /// Whole breaths per loop.
        let breaths: Double
        let phase: Double
    }

    private static let voices = [
        Voice(hz: 110.0, weight: 0.40, breaths: 1, phase: 0),
        Voice(hz: 164.81, weight: 0.28, breaths: 2, phase: 1.3),
        Voice(hz: 207.65, weight: 0.20, breaths: 1, phase: 3.1),
        Voice(hz: 277.18, weight: 0.12, breaths: 3, phase: 4.4),
    ]

    package static func samples() -> [Float] {
        let frames = Int(sampleRate * seconds)
        var raw = [Double](repeating: 0, count: frames)
        for voice in voices {
            let cycles = (voice.hz * seconds).rounded()
            for index in 0 ..< frames {
                let t = Double(index) / sampleRate
                let breath = 0.7 + 0.3 * sin(2 * .pi * voice.breaths * t / seconds + voice.phase)
                raw[index] += voice.weight * breath * sin(2 * .pi * cycles * t / seconds)
            }
        }
        let peak = raw.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return raw.map { Float($0) } }
        let gain = Double(level) / peak
        return raw.map { Float($0 * gain) }
    }
}
