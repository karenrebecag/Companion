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
        didSet {
            saveStep()
            // Incredible's second ask is only for the relaunch onto this step.
            if flow.step != .permissions { reaskArmed = false }
        }
    }
    package private(set) var facts = WelcomeFacts()
    /// False until the first refresh has read the machine: before it,
    /// `facts.granted` is an empty placeholder, not "nothing granted".
    package private(set) var hasRefreshed = false
    package private(set) var level = 0.0
    package private(set) var done: Bool
    package private(set) var soundCheck = SoundCheck.unchecked

    private let devices: any WelcomeDevices
    private let keyReady: () -> Bool
    private let defaults: UserDefaults
    private var greeted = false
    /// Incredible's 1 s poll asks for the verified flag on every tick until
    /// the step is complete; once a capture worked there is nothing to ask.
    @ObservationIgnored private var screenVerified = false
    /// Armed only when the app opened straight onto the saved permissions
    /// step, the relaunch macOS asks for after Screen Recording.
    @ObservationIgnored private var reaskArmed: Bool
    /// Slider moves reach the Mac one after another: a drag sends many, and
    /// the last one written must be the last one moved to.
    @ObservationIgnored private var volumeWrites: Task<Void, Never>?
    /// Bumped by every slider move so a read that started before it cannot
    /// land afterwards and put the old level back.
    @ObservationIgnored private var volumeWriteGeneration = 0

    package init(
        devices: any WelcomeDevices, keyReady: @escaping () -> Bool,
        defaults: UserDefaults = .standard
    ) {
        self.devices = devices
        self.keyReady = keyReady
        self.defaults = defaults
        let seen = defaults.bool(forKey: Self.doneKey)
        self.done = seen
        let flow = seen ? WelcomeFlow.start(welcomeDone: true) : Self.resumed(from: defaults)
        self.flow = flow
        self.reaskArmed = flow.step == .permissions
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

    /// The switch is on and a real capture failed. Kept apart from "not
    /// granted" because Incredible treats it as its own dead end: flipping
    /// the switch again does nothing until the app relaunches.
    package private(set) var screenRecordingUnverified = false

    package func refresh() async {
        var granted: Set<WelcomePermission> = []
        for permission in WelcomePermission.allCases where await devices.granted(permission) {
            granted.insert(permission)
        }
        if granted.contains(.screenRecording) {
            if !screenVerified { screenVerified = await devices.verifyScreenCapture() }
            if !screenVerified { granted.remove(.screenRecording) }
            screenRecordingUnverified = !screenVerified
        } else {
            screenVerified = false
            screenRecordingUnverified = false
        }
        facts.granted = granted
        facts.keyReady = keyReady()
        hasRefreshed = true
        // Incredible's reducer: the step after permissions goes back to them
        // when one is lost, instead of teaching a hold that cannot work.
        let afterPermissions = flow.step == .holdKey || flow.step == .microphone
        if afterPermissions, !granted.isSuperset(of: WelcomePermission.allCases) {
            flow = WelcomeFlow(step: .permissions)
        }
    }

    package func request(_ permission: WelcomePermission) async {
        _ = await devices.request(permission)
        if permission == .screenRecording { screenVerified = false }
        await refresh()
    }

    /// Coming back from System Settings is when a switch flipped there can
    /// be checked, so the probe starts over; and a relaunch onto this step
    /// with the switch on and no capture gets Incredible's one more ask.
    package func refocused() async {
        guard flow.step == .permissions else {
            await refresh()
            return
        }
        screenVerified = false
        await refresh()
        guard reaskArmed, screenRecordingUnverified else { return }
        reaskArmed = false
        await request(.screenRecording)
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

    /// Incredible reads the volume once, before the first spoken line.
    package func checkSound() async {
        guard soundCheck == .unchecked else { return }
        soundCheck = SoundCheck.start(await devices.outputVolume())
    }

    /// Incredible hears the volume keys through an event; a short poll is
    /// the same answer without a CoreAudio listener in the view. False when
    /// the screen was left meanwhile, so the greeting never speaks elsewhere.
    package func holdForSoundCheck(
        poll: Duration = .milliseconds(500),
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async -> Bool {
        await checkSound()
        while soundCheck.holdsGreeting {
            do { try await sleep(poll) } catch { return false }
            await rereadVolume()
        }
        return !Task.isCancelled
    }

    /// The volume keys or the menu bar can raise it while the card is up.
    package func rereadVolume() async {
        guard soundCheck.holdsGreeting else { return }
        let generation = volumeWriteGeneration
        let reading = await devices.outputVolume()
        guard generation == volumeWriteGeneration else { return }
        soundCheck = soundCheck.reading(reading)
    }

    /// Muted is left alone: the slider moves the level, never the mute.
    package func setVolume(_ level: Double) {
        guard case .showing(let current) = soundCheck, !current.muted else { return }
        volumeWriteGeneration += 1
        soundCheck = soundCheck.reading(OutputVolume(level: level, muted: false))
        // Crossing 30 removes the card before the release, so the release
        // never reaches `probe()`: the Pop plays after the write instead.
        let probeAfter = soundCheck == .passed
        let devices = devices
        let previous = volumeWrites
        volumeWrites = Task {
            await previous?.value
            await devices.setOutputVolume(level)
            if probeAfter { await devices.playProbe() }
        }
    }

    func volumeWritesSettled() async {
        await volumeWrites?.value
    }

    /// Letting go of the slider plays a sound at the new level.
    package func probe() async {
        guard case .showing(let current) = soundCheck, !current.muted else { return }
        await volumeWrites?.value
        await devices.playProbe()
    }

    /// "I can hear it" and "Continue anyway" both move on, as in Incredible.
    package func confirmSound() {
        guard soundCheck.holdsGreeting else { return }
        soundCheck = .passed
    }

    package func greet() async {
        guard !greeted, !soundCheck.holdsGreeting else { return }
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
        soundCheck = .unchecked
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
