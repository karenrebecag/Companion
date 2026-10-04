import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing
@testable import CompanionUI

// WIN-14: music during the onboarding, Incredible 0.2.36 parity
// (createFirstRunIO-Dv00aAyF.js @35812). The rule is pure, the model owns the
// mute and the window flag, and the machine only hears the changes.

private final class MusicDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Bool] = []

    var calls: [Bool] { lock.withLock { sent } }

    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
    func setMusic(playing: Bool) async { lock.withLock { sent.append(playing) } }
}

/// A machine written before the music port existed: it must keep compiling and stay silent.
private struct SilentDevices: WelcomeDevices {
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

/// A machine whose music call suspends until the test opens the gate: the
/// in-flight call that a cancelled task leaves behind.
private final class GatedDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Bool] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var open = false
    private var entered = 0

    var calls: [Bool] { lock.withLock { sent } }
    var enteredCount: Int { lock.withLock { entered } }
    /// What the speaker would be doing: the last value that finished.
    var deviceState: Bool? { lock.withLock { sent.last } }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = true
            defer { waiting = [] }
            return waiting
        }
        for continuation in pending { continuation.resume() }
    }

    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
    func setMusic(playing: Bool) async {
        lock.withLock { entered += 1 }
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if open { return true }
                waiting.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        lock.withLock { sent.append(playing) }
    }
}

@MainActor private func musicModel(
    _ devices: any WelcomeDevices = MusicDevices(), voiceOver: Bool = false, on step: WelcomeStep = .keys,
    welcomeDone: Bool = false
) -> WelcomeModel {
    let defaults = UserDefaults(suiteName: "welcome-music-\(UUID().uuidString)") ?? .standard
    if welcomeDone { defaults.set(true, forKey: WelcomeModel.doneKey) }
    let model = WelcomeModel(devices: devices, keyReady: { true }, defaults: defaults, voiceOverRunning: { voiceOver })
    model.jump(to: step)
    return model
}

@Test func welcomeMusicPagesAreKeysPermissionsAndHoldKey() {
    let music = WelcomeStep.allCases.filter(\.hasMusic)
    expectEq(music, [.keys, .permissions, .holdKey], "music: only Incredible's signup/permissions/ready pages")
}

@Test func welcomeMusicRuleNeedsEveryConditionToPlay() {
    expect(WelcomeMusic.plays(step: .keys, muted: false, shown: true, finished: false), "music: all clear plays")
    expect(!WelcomeMusic.plays(step: .keys, muted: true, shown: true, finished: false), "music: muted stops it")
    expect(!WelcomeMusic.plays(step: .keys, muted: false, shown: false, finished: false),
           "music: a hidden window stops it")
    expect(!WelcomeMusic.plays(step: .keys, muted: false, shown: true, finished: true),
           "music: a finished welcome stops it")
    for step in WelcomeStep.allCases where !step.hasMusic {
        expect(!WelcomeMusic.plays(step: step, muted: false, shown: true, finished: false),
               "music: \(step) is not a music page")
    }
}

@Test @MainActor func welcomeMusicIsOnByDefaultAndMutedUnderVoiceOver() {
    let plain = musicModel()
    expect(!plain.musicMuted && plain.musicPlaying, "music: on by default like Incredible")
    let reader = musicModel(voiceOver: true)
    expect(reader.musicMuted && !reader.musicPlaying, "music: starts muted when VoiceOver is running (WCAG 1.4.2)")
}

@Test @MainActor func welcomeMusicToggleFlipsTheMute() {
    let model = musicModel()
    model.toggleMusic()
    expect(model.musicMuted && !model.musicPlaying, "music: toggle mutes")
    model.toggleMusic()
    expect(!model.musicMuted && model.musicPlaying, "music: toggle again plays")
}

@Test @MainActor func welcomeMusicMuteResetsWhenTheStepLeavesTheMusicPages() {
    let model = musicModel()
    model.toggleMusic()
    model.jump(to: .permissions)
    expect(model.musicMuted, "music: moving between music pages keeps the mute")
    model.jump(to: .microphone)
    expect(!model.musicMuted, "music: leaving the music pages resets the mute (Incredible's hook)")
    model.jump(to: .holdKey)
    expect(model.musicPlaying, "music: coming back plays again")
}

@Test @MainActor func welcomeMusicResetKeepsTheVoiceOverDefault() {
    let model = musicModel(voiceOver: true)
    model.toggleMusic()
    expect(!model.musicMuted, "music: a VoiceOver user can opt in")
    model.jump(to: .cover)
    expect(model.musicMuted, "music: the reset goes back to muted under VoiceOver")
}

@Test @MainActor func welcomeMusicSyncSendsOnlyChanges() async {
    let devices = MusicDevices()
    let model = musicModel(devices)
    await model.syncMusic()
    await model.syncMusic()
    expectEq(devices.calls, [true], "music: keys starts it once")
    model.toggleMusic()
    await model.syncMusic()
    model.toggleMusic()
    await model.syncMusic()
    model.jump(to: .cover)
    await model.syncMusic()
    expectEq(devices.calls, [true, false, true, false], "music: mute, unmute, then the cover stops it")
}

@Test @MainActor func welcomeMusicStopsWhenTheWindowIsNotShown() async {
    let devices = MusicDevices()
    let model = musicModel(devices)
    await model.syncMusic()
    model.setWindowShown(false)
    await model.syncMusic()
    model.setWindowShown(true)
    await model.syncMusic()
    expectEq(devices.calls, [true, false, true], "music: hidden stops it, shown brings it back")
}

@Test @MainActor func welcomeMusicStopsWhenTheWelcomeFinishes() async {
    let devices = MusicDevices()
    let model = musicModel(devices)
    await model.syncMusic()
    model.jump(to: .yourTurn)
    model.observe(.processing(.pending))
    model.next()
    expect(model.done && !model.musicPlaying, "music: a finished welcome is silent")
    await model.syncMusic()
    expectEq(devices.calls, [true, false], "music: finishing stops it")
}

@Test @MainActor func welcomeMusicDefaultPortIsSilent() async {
    let model = musicModel(SilentDevices())
    await model.syncMusic()
    expect(model.musicPlaying, "music: the model still decides; a machine without the capability just stays quiet")
}

@Test @MainActor func welcomeMusicStringsExistInBothLanguages() {
    for key in ["welcome.music", "welcome.music.on", "welcome.music.off"] {
        let es = Localized.string(key, language: .es)
        let en = Localized.string(key, language: .en)
        expect(es != key && en != key, "music: \(key) is in both catalogs")
        expect(es != en, "music: \(key) is translated, not copied")
    }
}

@Test @MainActor func welcomeMusicSendsAreSerializedAndEndOnTheCurrentState() async {
    let devices = GatedDevices()
    let model = musicModel(devices)
    let first = Task { @MainActor in await model.syncMusic() }
    while devices.enteredCount < 1 { await Task.yield() }
    model.toggleMusic()
    let second = Task { @MainActor in await model.syncMusic() }
    first.cancel()
    devices.release()
    await first.value
    await second.value
    await model.musicSendsSettled()
    expectEq(devices.calls, [true, false], "music: sends keep their order")
    expectEq(devices.deviceState, model.musicPlaying, "music: the device ends where the model is, never a stale play")
}

@Test @MainActor func welcomeMusicQueuedSendReconcilesToTheStateAtExecution() async {
    let devices = GatedDevices()
    let model = musicModel(devices)
    let first = Task { @MainActor in await model.syncMusic() }
    while devices.enteredCount < 1 { await Task.yield() }
    model.toggleMusic()
    model.toggleMusic()
    let second = Task { @MainActor in await model.syncMusic() }
    devices.release()
    await first.value
    await second.value
    expectEq(devices.calls, [true], "music: a mute undone before the queued send ran sends nothing extra")
}

@Test @MainActor func welcomeMusicIsNotOfferedOnTheKeysOnlyResume() async {
    let model = musicModel(welcomeDone: true)
    expect(model.done && !model.musicAvailable && !model.musicPlaying,
           "music: the keys-only resume is not onboarding, no toggle and no sound")
    model.reopen()
    model.jump(to: .keys)
    expect(model.musicAvailable && model.musicPlaying, "music: reopening the welcome brings the music back")
}

@Test @MainActor func welcomeMusicAvailabilityFollowsTheStep() {
    let model = musicModel()
    expect(model.musicAvailable, "music: keys offers it")
    model.jump(to: .microphone)
    expect(!model.musicAvailable, "music: the microphone page does not")
}

@Test @MainActor func welcomeMusicVoiceOverFlippedMidWelcomeAppliesOnTheNextVisit() {
    var voiceOver = false
    let defaults = UserDefaults(suiteName: "welcome-music-\(UUID().uuidString)") ?? .standard
    let model = WelcomeModel(devices: MusicDevices(), keyReady: { true }, defaults: defaults,
                             voiceOverRunning: { voiceOver })
    model.jump(to: .keys)
    voiceOver = true
    expect(!model.musicMuted, "music: flipping VoiceOver mid-page leaves the mute alone")
    model.jump(to: .cover)
    expect(model.musicMuted, "music: leaving applies the new default")
    model.jump(to: .keys)
    expect(model.musicMuted && !model.musicPlaying, "music: and the page is muted when it comes back")
}

@Test @MainActor func welcomeMusicMuteResetsWalkingBackFromTheMicrophone() {
    let model = musicModel()
    model.toggleMusic()
    model.jump(to: .permissions)
    model.jump(to: .holdKey)
    expect(model.musicMuted, "music: still muted across the music pages")
    model.jump(to: .microphone)
    model.back()
    expect(model.flow.step == .holdKey && !model.musicMuted && model.musicPlaying,
           "music: back onto the hold-key page starts from the default")
}

@Test @MainActor func welcomeMusicFinishingWhileMutedSendsNothing() async {
    let devices = MusicDevices()
    let model = musicModel(devices)
    model.toggleMusic()
    await model.syncMusic()
    model.jump(to: .yourTurn)
    model.observe(.processing(.pending))
    model.next()
    await model.syncMusic()
    expectEq(devices.calls, [], "music: nothing was playing, nothing is stopped")
}

@Test @MainActor func welcomeMusicSkippingTheWelcomeStops() async {
    let devices = MusicDevices()
    let model = musicModel(devices)
    await model.syncMusic()
    model.jump(to: .yourTurn)
    model.skip()
    expect(model.done, "music: skip finished the welcome")
    await model.syncMusic()
    expectEq(devices.calls, [true, false], "music: skipping stops it")
}

@Test @MainActor func welcomeMusicHidingTheWindowOnANonMusicPageSendsNothing() async {
    let devices = MusicDevices()
    let model = musicModel(devices, on: .cover)
    await model.syncMusic()
    model.setWindowShown(false)
    await model.syncMusic()
    model.setWindowShown(true)
    await model.syncMusic()
    expectEq(devices.calls, [], "music: no music page, no calls")
}

@Test func welcomeWindowShowsOnlyWhenVisibleUnminiaturizedAndNotOccluded() {
    typealias Reader = WindowVisibilityReader
    expect(Reader.windowShows(isVisible: true, miniaturized: false, occludedVisible: true), "window: all clear shows")
    expect(!Reader.windowShows(isVisible: false, miniaturized: false, occludedVisible: true), "window: ordered out")
    expect(!Reader.windowShows(isVisible: true, miniaturized: true, occludedVisible: true), "window: minimized")
    expect(!Reader.windowShows(isVisible: true, miniaturized: false, occludedVisible: false), "window: occluded")
}

@Test @MainActor func welcomeMusicToggleAccessibilityAndIconsFollowTheState() {
    expectEq(WelcomeMusicToggle.accessibilityValueKey(playing: true), "welcome.music.on", "toggle: on key")
    expectEq(WelcomeMusicToggle.accessibilityValueKey(playing: false), "welcome.music.off", "toggle: off key")
    expect(WelcomeMusicToggle.iconName(playing: true) != WelcomeMusicToggle.iconName(playing: false),
           "toggle: the two states draw different icons")
    expectEq(WelcomeMusicToggle.iconName(playing: true), "speaker.wave.2", "toggle: playing icon")
    expectEq(WelcomeMusicToggle.iconName(playing: false), "speaker.slash", "toggle: muted icon")
    for language in [AppLanguage.es, .en] {
        let on = Localized.string(WelcomeMusicToggle.accessibilityValueKey(playing: true), language: language)
        let off = Localized.string(WelcomeMusicToggle.accessibilityValueKey(playing: false), language: language)
        expect(on != off, "toggle: on and off read differently in \(language)")
    }
    for playing in [true, false] {
        let key = WelcomeMusicToggle.accessibilityValueKey(playing: playing)
        expect(Localized.string(key, language: .es) != Localized.string(key, language: .en),
               "toggle: \(key) differs per language")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "gallery: only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func musicSnapshots() async throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for playing in [true, false] {
        for scheme in [ColorScheme.light, .dark] {
            let model = musicModel(SilentDevices())
            if !playing { model.toggleMusic() }
            await model.refresh()
            let name = "welcome-music-\(playing ? "on" : "off")-\(scheme == .dark ? "dark" : "light")"
            try renderWelcome(model, scheme: scheme, to: out, name)
        }
    }
}

@MainActor private func renderWelcome(_ model: WelcomeModel, scheme: ColorScheme, to dir: URL, _ name: String) throws {
    let size = CGSize(width: 1120, height: 700)
    let view = WelcomeView(welcome: model, chat: chat())
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    let png = try #require(rep.representation(using: .png, properties: [:]))
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
