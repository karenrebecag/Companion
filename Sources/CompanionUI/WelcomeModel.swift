import CompanionCore
import Foundation
import Observation

/// The welcome's state (Wave 16c): the flow, the facts it waits on, and the
/// meter. Reads the machine through `WelcomeDevices`; never a framework.
@Observable
@MainActor
public final class WelcomeModel {
    /// Above the room's hum, below a normal voice at arm's length.
    static let heardLevel = 0.12
    static let doneKey = "companion.welcome.done"

    public private(set) var flow: WelcomeFlow
    public private(set) var facts = WelcomeFacts()
    public private(set) var level = 0.0
    public private(set) var done: Bool

    private let devices: any WelcomeDevices
    private let keyReady: () -> Bool
    private let defaults: UserDefaults
    private var greeted = false

    public init(
        devices: any WelcomeDevices, keyReady: @escaping () -> Bool,
        defaults: UserDefaults = .standard
    ) {
        self.devices = devices
        self.keyReady = keyReady
        self.defaults = defaults
        let seen = defaults.bool(forKey: Self.doneKey)
        self.done = seen
        self.flow = WelcomeFlow.start(welcomeDone: seen)
    }

    public var canContinue: Bool { flow.canContinue(facts) }

    public func refresh() async {
        var granted: Set<WelcomePermission> = []
        for permission in WelcomePermission.allCases where await devices.granted(permission) {
            granted.insert(permission)
        }
        facts.granted = granted
        facts.keyReady = keyReady()
    }

    public func request(_ permission: WelcomePermission) async {
        _ = await devices.request(permission)
        await refresh()
    }

    /// Runs until the stream ends or the task is cancelled (the screen left).
    public func listen() async {
        for await value in devices.micLevels() {
            if Task.isCancelled { break }
            level = value
            if value > Self.heardLevel { facts.micHeard = true }
        }
    }

    /// Only a release that sent words on the last screen counts: a press, a
    /// tap or a hold from another screen is not the lesson.
    public func observe(_ kind: SessionKind) {
        guard flow.step == .yourTurn, kind == .processing(.pending) else { return }
        facts.holdDone = true
    }

    public func greet() async {
        guard !greeted else { return }
        greeted = true
        let name = UserProfile.ownerName.trimmingCharacters(in: .whitespaces)
        let line = name.isEmpty
            ? Localized.string("welcome.greeting")
            : String(format: Localized.string("welcome.greeting.name"), name)
        await devices.greet(line, language: Localized.language())
    }

    public func next() {
        facts.keyReady = keyReady()
        flow.advance(facts)
        if flow.finished { finish() }
    }

    public func back() { flow.back() }

    public func skip() {
        flow.skip()
        if flow.finished { finish() }
    }

    /// From Settings: the whole welcome again, from the cover.
    public func reopen() {
        done = false
        flow = WelcomeFlow()
        facts.holdDone = false
        greeted = false
    }

    /// Seen before, and the key went missing: only the key screen again.
    public func resumeKeys() {
        guard flow.finished else { return }
        flow = WelcomeFlow.start(welcomeDone: true)
    }

    func jump(to step: WelcomeStep) {
        flow = WelcomeFlow(step: step)
    }

    private func finish() {
        done = true
        defaults.set(true, forKey: Self.doneKey)
    }
}
