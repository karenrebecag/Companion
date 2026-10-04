import Foundation

// Wave 16c. Incredible's welcome, one idea per screen, as a pure reducer: the
// view paints the step and asks whether Continue is open; the facts come
// from the devices port. Nothing here knows a window.

package enum WelcomeStep: Int, Sendable, Equatable, CaseIterable {
    case cover, hello, keys, permissions, holdKey, microphone, yourTurn

    /// Only the screens that need hardware can be skipped: a Mac without a
    /// microphone must not be trapped (spec 16c §4).
    package var skippable: Bool { self == .microphone || self == .yourTurn }

    /// Incredible saves the page reached and reopens there, except its intro:
    /// the cover and the greeting play again from the start.
    package var resumable: Bool { self != .cover && self != .hello }

    /// Stored by name, not by raw value, so reordering the cases never sends
    /// a relaunch to the wrong screen.
    package var savedName: String { String(describing: self) }

    package init?(savedName: String) {
        guard let step = Self.allCases.first(where: { $0.savedName == savedName }) else { return nil }
        self = step
    }
}

/// The four rows of the one permissions screen.
package enum WelcomePermission: String, Sendable, Equatable, CaseIterable {
    case microphone, accessibility, screenRecording, speechRecognition
}

package struct WelcomeFacts: Sendable, Equatable {
    /// An OpenAI key is saved and verified, or a local model was accepted.
    package var keyReady: Bool
    package var granted: Set<WelcomePermission>
    /// The level meter moved above the noise floor at least once.
    package var micHeard: Bool
    /// A hold was released with words in it on the last screen.
    package var holdDone: Bool

    package init(
        keyReady: Bool = false, granted: Set<WelcomePermission> = [],
        micHeard: Bool = false, holdDone: Bool = false
    ) {
        self.keyReady = keyReady
        self.granted = granted
        self.micHeard = micHeard
        self.holdDone = holdDone
    }
}

package struct WelcomeFlow: Sendable, Equatable {
    package private(set) var step: WelcomeStep
    package private(set) var finished = false
    /// A returning user who lost the key sees the key screen, not the tour.
    private let onlyKeys: Bool

    package init(step: WelcomeStep = .cover) {
        self.step = step
        self.onlyKeys = false
    }

    private init(onlyKeys: Bool) {
        self.step = onlyKeys ? .keys : .cover
        self.onlyKeys = onlyKeys
    }

    package static func start(welcomeDone: Bool) -> WelcomeFlow {
        WelcomeFlow(onlyKeys: welcomeDone)
    }

    package func canContinue(_ facts: WelcomeFacts) -> Bool {
        switch step {
        case .cover, .hello, .holdKey: true
        case .keys: facts.keyReady
        case .permissions: facts.granted.isSuperset(of: WelcomePermission.allCases)
        case .microphone: facts.micHeard
        case .yourTurn: facts.holdDone
        }
    }

    /// Moves on when the screen's condition holds. False when it did not
    /// move to another screen (blocked, or the flow just finished).
    @discardableResult
    package mutating func advance(_ facts: WelcomeFacts) -> Bool {
        guard !finished, canContinue(facts) else { return false }
        return moveOn()
    }

    package mutating func skip() {
        guard !finished, step.skippable else { return }
        moveOn()
    }

    package mutating func back() {
        guard !finished, !onlyKeys, let previous = WelcomeStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    @discardableResult
    private mutating func moveOn() -> Bool {
        guard !onlyKeys, let next = WelcomeStep(rawValue: step.rawValue + 1) else {
            finished = true
            return false
        }
        step = next
        return true
    }
}

/// The Mac's output as the menu bar's volume reads it, 0...1.
package struct OutputVolume: Sendable, Equatable {
    package let level: Double
    package let muted: Bool

    package init(level: Double, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}

/// Incredible's first-run sound check (WIN-8): before the first spoken line
/// a Mac too quiet to hear it gets a card that asks to turn it up.
package enum SoundCheck: Sendable, Equatable {
    case unchecked
    case showing(OutputVolume)
    case passed

    /// Incredible's QC (15 of 100): below it the card shows.
    package static let showBelow = 0.15
    /// Incredible's GC (30 of 100): a reading this loud clears the card,
    /// higher than the bar to show it so a level hovering at 15 doesn't flicker.
    package static let clearsAt = 0.30

    /// The first reading. A Mac with no output to read is never kept behind
    /// the card, as Incredible skips it when the volume is unknown.
    package static func start(_ volume: OutputVolume?) -> SoundCheck {
        guard let volume, volume.muted || volume.level < showBelow else { return .passed }
        return .showing(volume)
    }

    /// A later reading while the card is up; muted never clears it, since
    /// nothing is heard whatever the level.
    package func reading(_ volume: OutputVolume?) -> SoundCheck {
        guard case .showing = self, let volume else { return self }
        return !volume.muted && volume.level >= Self.clearsAt ? .passed : .showing(volume)
    }

    /// Before the first read resolves the screen is empty: showing the hello
    /// then would flash it and offer Continue past a card about to appear.
    package var showsHello: Bool { self == .passed }

    package var holdsGreeting: Bool {
        if case .showing = self { true } else { false }
    }
}

/// What the welcome needs from the machine. One port so the view never
/// touches AVFoundation, and a fake can drive every screen in tests.
package protocol WelcomeDevices: Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool
    /// The system prompt where there is one; otherwise false, and the row
    /// opens System Settings instead.
    func request(_ permission: WelcomePermission) async -> Bool
    /// A real capture probe: the Screen Recording switch can be on with
    /// captures failing (Incredible's "on with verified: false" dead end).
    /// Never asks for the permission.
    func verifyScreenCapture() async -> Bool
    /// Microphone level, 0...1, until the consumer stops iterating.
    func micLevels() -> AsyncStream<Double>
    /// Says a short line with the system voice: the welcome speaks before
    /// any key exists.
    func greet(_ text: String, language: AppLanguage) async
    /// The output volume, or nil when there is no output device to ask.
    func outputVolume() async -> OutputVolume?
    /// Moves the system volume; never touches mute.
    func setOutputVolume(_ level: Double) async
    /// A short sound through the system output, so a moved slider is heard.
    func playProbe() async
}

package extension WelcomeDevices {
    /// A machine that can't read its output skips the sound check.
    func outputVolume() async -> OutputVolume? { nil }
    func setOutputVolume(_ level: Double) async {}
    func playProbe() async {}
}

package extension WelcomePermission {
    var settingsLink: URL {
        switch self {
        case .microphone: PermissionSettingsLink.microphone
        case .accessibility: PermissionSettingsLink.accessibility
        case .screenRecording: PermissionSettingsLink.screenRecording
        case .speechRecognition: PermissionSettingsLink.speechRecognition
        }
    }
}
