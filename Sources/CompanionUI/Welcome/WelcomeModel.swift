import CompanionCore
import Foundation
import Observation

/// The welcome's state (Wave 16c): the flow, the facts it waits on, and the
/// meter. Reads the machine through `WelcomeDevices`; never a framework.
@Observable
@MainActor
package final class WelcomeModel {
    /// Above the room's hum, below a normal voice at arm's length.
    static let heardLevel = 0.12
    static let doneKey = "companion.welcome.done"
    static let stepKey = "companion.welcome.step"

    package private(set) var flow: WelcomeFlow {
        didSet { saveStep() }
    }
    package private(set) var facts = WelcomeFacts()
    package private(set) var level = 0.0
    package private(set) var done: Bool

    private let devices: any WelcomeDevices
    private let keyReady: () -> Bool
    private let defaults: UserDefaults
    private var greeted = false

    package init(
        devices: any WelcomeDevices, keyReady: @escaping () -> Bool,
        defaults: UserDefaults = .standard
    ) {
        self.devices = devices
        self.keyReady = keyReady
        self.defaults = defaults
        let seen = defaults.bool(forKey: Self.doneKey)
        self.done = seen
        self.flow = seen ? WelcomeFlow.start(welcomeDone: true) : Self.resumed(from: defaults)
    }

    /// The page the last run reached, so the relaunch macOS asks for after
    /// Screen Recording lands back on it.
    private static func resumed(from defaults: UserDefaults) -> WelcomeFlow {
        guard let name = defaults.string(forKey: stepKey),
              let step = WelcomeStep(savedName: name), step.resumable else { return WelcomeFlow() }
        return WelcomeFlow(step: step)
    }

    /// Like Incredible, only a move into a resumable page writes; going back
    /// to the intro leaves the last page reached in place.
    private func saveStep() {
        guard !done, !flow.finished, flow.step.resumable else { return }
        defaults.set(flow.step.savedName, forKey: Self.stepKey)
    }

    package var canContinue: Bool { flow.canContinue(facts) }

    package func refresh() async {
        var granted: Set<WelcomePermission> = []
        for permission in WelcomePermission.allCases where await devices.granted(permission) {
            granted.insert(permission)
        }
        facts.granted = granted
        facts.keyReady = keyReady()
    }

    package func request(_ permission: WelcomePermission) async {
        _ = await devices.request(permission)
        await refresh()
    }

    /// Runs until the stream ends or the task is cancelled (the screen left).
    package func listen() async {
        for await value in devices.micLevels() {
            if Task.isCancelled { break }
            level = value
            if value > Self.heardLevel { facts.micHeard = true }
        }
    }

    /// Only a release that sent words on the last screen counts: a press, a
    /// tap or a hold from another screen is not the lesson.
    package func observe(_ kind: SessionKind) {
        guard flow.step == .yourTurn, kind == .processing(.pending) else { return }
        facts.holdDone = true
    }

    package func greet() async {
        guard !greeted else { return }
        greeted = true
        let name = UserProfile.ownerName.trimmingCharacters(in: .whitespaces)
        let line = name.isEmpty
            ? Localized.string("welcome.greeting")
            : String(format: Localized.string("welcome.greeting.name"), name)
        await devices.greet(line, language: Localized.language())
    }

    package func next() {
        facts.keyReady = keyReady()
        flow.advance(facts)
        if flow.finished { finish() }
    }

    package func back() { flow.back() }

    package func skip() {
        flow.skip()
        if flow.finished { finish() }
    }

    /// From Settings: the whole welcome again, from the cover.
    package func reopen() {
        done = false
        defaults.removeObject(forKey: Self.stepKey)
        flow = WelcomeFlow()
        facts.holdDone = false
        greeted = false
    }

    /// Seen before, and the key went missing: only the key screen again.
    package func resumeKeys() {
        guard flow.finished else { return }
        flow = WelcomeFlow.start(welcomeDone: true)
    }

    func jump(to step: WelcomeStep) {
        flow = WelcomeFlow(step: step)
    }

    private func finish() {
        done = true
        defaults.set(true, forKey: Self.doneKey)
        defaults.removeObject(forKey: Self.stepKey)
    }
}
