import Foundation

// Wave 16c. Incredible's welcome, one idea per screen, as a pure reducer: the
// view paints the step and asks whether Continue is open; the facts come
// from the devices port. Nothing here knows a window.

public enum WelcomeStep: Int, Sendable, Equatable, CaseIterable {
    case cover, hello, keys, permissions, holdKey, microphone, yourTurn

    /// Only the screens that need hardware can be skipped: a Mac without a
    /// microphone must not be trapped (spec 16c §4).
    public var skippable: Bool { self == .microphone || self == .yourTurn }
}

/// The four rows of the one permissions screen.
public enum WelcomePermission: String, Sendable, Equatable, CaseIterable {
    case microphone, accessibility, screenRecording, speechRecognition
}

public struct WelcomeFacts: Sendable, Equatable {
    /// An OpenAI key is saved and verified, or a local model was accepted.
    public var keyReady: Bool
    public var granted: Set<WelcomePermission>
    /// The level meter moved above the noise floor at least once.
    public var micHeard: Bool
    /// A hold was released with words in it on the last screen.
    public var holdDone: Bool

    public init(
        keyReady: Bool = false, granted: Set<WelcomePermission> = [],
        micHeard: Bool = false, holdDone: Bool = false
    ) {
        self.keyReady = keyReady
        self.granted = granted
        self.micHeard = micHeard
        self.holdDone = holdDone
    }
}

public struct WelcomeFlow: Sendable, Equatable {
    public private(set) var step: WelcomeStep
    public private(set) var finished = false
    /// A returning user who lost the key sees the key screen, not the tour.
    private let onlyKeys: Bool

    public init(step: WelcomeStep = .cover) {
        self.step = step
        self.onlyKeys = false
    }

    private init(onlyKeys: Bool) {
        self.step = onlyKeys ? .keys : .cover
        self.onlyKeys = onlyKeys
    }

    public static func start(welcomeDone: Bool) -> WelcomeFlow {
        WelcomeFlow(onlyKeys: welcomeDone)
    }

    public func canContinue(_ facts: WelcomeFacts) -> Bool {
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
    public mutating func advance(_ facts: WelcomeFacts) -> Bool {
        guard !finished, canContinue(facts) else { return false }
        return moveOn()
    }

    public mutating func skip() {
        guard !finished, step.skippable else { return }
        moveOn()
    }

    public mutating func back() {
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
public protocol WelcomeDevices: Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool
    /// The system prompt where there is one; otherwise false, and the row
    /// opens System Settings instead.
    func request(_ permission: WelcomePermission) async -> Bool
    /// Microphone level, 0...1, until the consumer stops iterating.
    func micLevels() -> AsyncStream<Double>
    /// Says a short line with the system voice: the welcome speaks before
    /// any key exists.
    func greet(_ text: String, language: AppLanguage) async
}

public extension WelcomePermission {
    var settingsLink: URL {
        switch self {
        case .microphone: PermissionSettingsLink.microphone
        case .accessibility: PermissionSettingsLink.accessibility
        case .screenRecording: PermissionSettingsLink.screenRecording
        case .speechRecognition: PermissionSettingsLink.speechRecognition
        }
    }
}
