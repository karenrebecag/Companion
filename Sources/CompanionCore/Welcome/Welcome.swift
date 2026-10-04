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

    /// Incredible plays music on its signup/permissions/ready pages
    /// (createFirstRunIO-Dv00aAyF.js @35812, hook `ds`), which are the key,
    /// permissions and hold-key screens here. Not the cover or the greeting
    /// (the voice speaks there), not the microphone test (it needs a quiet
    /// room), not the last turn (Incredible's has none either).
    package var hasMusic: Bool { self == .keys || self == .permissions || self == .holdKey }

    /// Stored by name, not by raw value, so reordering the cases never sends
    /// a relaunch to the wrong screen.
    package var savedName: String { String(describing: self) }

    package init?(savedName: String) {
        guard let step = Self.allCases.first(where: { $0.savedName == savedName }) else { return nil }
        self = step
    }
}

/// Whether the welcome's background music should be sounding. Pure so the
/// model, the view and the tests all ask the same question.
package enum WelcomeMusic {
    package static func plays(step: WelcomeStep, muted: Bool, shown: Bool, finished: Bool) -> Bool {
        step.hasMusic && !muted && shown && !finished
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
    /// Starts or stops the background music; idempotent. Machines that
    /// cannot play (fakes, previews) keep the default and stay silent.
    func setMusic(playing: Bool) async
}

package extension WelcomeDevices {
    func setMusic(playing: Bool) async {}
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
