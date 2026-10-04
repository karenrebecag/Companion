import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// WIN-8: Incredible's first-run sound check. Before the first spoken line it
// reads the Mac's output volume; under 15 of 100 a card asks to turn it up,
// it clears on its own at 30, and either button moves on
// (firstRun-CdIWn2zA.js @200380 QC=15/GC=30, @201432 sound_confirmed and
// volume_changed; TurnStage-D5KoWNfv.js @679 the card; styles-CTdsYdwA.css
// @3301-5984 the .fr-sound-* rules).

private func volume(_ level: Double, muted: Bool = false) -> OutputVolume {
    OutputVolume(level: level, muted: muted)
}

@Test func theCardShowsOnlyUnderFifteen() {
    expectEq(SoundCheck.start(volume(0.14)), .showing(volume(0.14)), "14 of 100: the card")
    expectEq(SoundCheck.start(volume(0.15)), .passed, "15 of 100: loud enough")
    expectEq(SoundCheck.start(volume(0.8, muted: true)), .showing(volume(0.8, muted: true)),
             "muted: nothing is heard whatever the level")
    expectEq(SoundCheck.start(nil), .passed, "no output to read: never trapped behind the card")
}

@Test func aReadingAtThirtyClearsTheCard() {
    let showing = SoundCheck.start(volume(0.05))
    expectEq(showing.reading(volume(0.29)), .showing(volume(0.29)), "29: still showing, with the new level")
    expectEq(showing.reading(volume(0.30)), .passed, "30: clears on its own")
    expectEq(showing.reading(volume(0.9, muted: true)), .showing(volume(0.9, muted: true)),
             "muted at 90: still silent, still showing")
    expectEq(showing.reading(nil), showing, "a failed read changes nothing")
    expectEq(SoundCheck.passed.reading(volume(0.01)), .passed, "once passed it never comes back")
    expectEq(SoundCheck.unchecked.reading(volume(0.01)), .unchecked, "a reading is not the first check")
}

@Test func onlyTheShowingCardHoldsTheGreeting() {
    expect(SoundCheck.start(volume(0.01)).holdsGreeting, "showing: the greeting waits")
    expect(!SoundCheck.passed.holdsGreeting, "passed: the greeting speaks")
    expect(!SoundCheck.unchecked.holdsGreeting, "unchecked: nothing to wait on")
}

@Test @MainActor func aQuietMacHoldsTheGreetingUntilConfirmed() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    welcome.jump(to: .hello)
    await welcome.checkSound()
    expectEq(welcome.soundCheck, .showing(volume(0.05)), "a quiet Mac: the card")
    await welcome.greet()
    expect(devices.greetings.isEmpty, "the greeting never talks over the card")
    welcome.confirmSound()
    expectEq(welcome.soundCheck, .passed, "either button moves on")
    await welcome.greet()
    expectEq(devices.greetings.count, 1, "after the card: the greeting")
}

@Test @MainActor func aLoudMacGreetsStraightAway() async {
    let devices = VolumeDevices(volume(0.6))
    let welcome = welcomeModel(devices)
    welcome.jump(to: .hello)
    await welcome.checkSound()
    expectEq(welcome.soundCheck, .passed, "loud enough: no card")
    await welcome.greet()
    expectEq(devices.greetings.count, 1, "the greeting speaks")
}

@Test @MainActor func theSliderSetsTheMacVolumeInOrderAndClearsAtThirty() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    welcome.setVolume(0.1)
    welcome.setVolume(0.2)
    expectEq(welcome.soundCheck, .showing(volume(0.2)), "the card follows the slider")
    welcome.setVolume(0.3)
    expectEq(welcome.soundCheck, .passed, "30 from the slider clears it too")
    await welcome.volumeWritesSettled()
    expectEq(devices.writes, [0.1, 0.2, 0.3], "every move reaches the Mac, in order")
}

@Test func onlyThePassedCheckShowsTheHello() {
    expect(SoundCheck.passed.showsHello, "passed: the hello is on screen")
    expect(!SoundCheck.start(volume(0.01)).showsHello, "showing: the card owns the screen")
    expect(!SoundCheck.unchecked.showsHello, "unchecked: nothing flashes before the read resolves")
}

@Test @MainActor func aSliderMoveDuringAReadIsNotUndoneByIt() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    let gate = Gate()
    devices.holdReads(on: gate)
    let reread = Task { await welcome.rereadVolume() }
    await gate.untilArrived()
    welcome.setVolume(0.2)
    gate.release()
    await reread.value
    expectEq(welcome.soundCheck, .showing(volume(0.2)), "the stale 0.05 read is dropped")
    await welcome.volumeWritesSettled()
}

@Test @MainActor func sliderWritesWaitForTheOneBeforeThem() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    let gate = Gate()
    devices.holdFirstWrite(on: gate)
    welcome.setVolume(0.1)
    await gate.untilArrived()
    welcome.setVolume(0.2)
    for _ in 0..<20 { await Task.yield() }
    expect(devices.writes.isEmpty, "0.2 does not overtake the held 0.1 write: \(devices.writes)")
    gate.release()
    await welcome.volumeWritesSettled()
    expectEq(devices.writes, [0.1, 0.2], "released: both land, in order")
}

@Test @MainActor func holdingForTheCheckGreetsOnceTheVolumeRises() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    welcome.jump(to: .hello)
    var sleeps = 0
    let proceeded = await welcome.holdForSoundCheck(poll: .milliseconds(1), sleep: { _ in
        sleeps += 1
        devices.current = volume(0.4)
    })
    expect(proceeded, "the volume rose: the greeting may go ahead")
    expectEq(sleeps, 1, "one poll was enough")
    await welcome.greet()
    expectEq(devices.greetings.count, 1, "and it speaks once")
}

@Test @MainActor func leavingTheScreenWhileHoldingDoesNotGreet() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    welcome.jump(to: .hello)
    let proceeded = await welcome.holdForSoundCheck(sleep: { _ in throw CancellationError() })
    expect(!proceeded, "a cancelled sleep ends the hold without proceeding")
    expect(devices.greetings.isEmpty, "nothing was said")
}

@Test @MainActor func aLoudMacProceedsWithoutPolling() async {
    let welcome = welcomeModel(VolumeDevices(volume(0.6)))
    var sleeps = 0
    let proceeded = await welcome.holdForSoundCheck(sleep: { _ in sleeps += 1 })
    expect(proceeded, "no card: straight on")
    expectEq(sleeps, 0, "no polling without a card")
}

@Test @MainActor func unmutingToALoudLevelClearsTheCard() async {
    let devices = VolumeDevices(volume(0.5, muted: true))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    devices.current = volume(0.5)
    await welcome.rereadVolume()
    expectEq(welcome.soundCheck, .passed, "unmuted at 50: heard, so it clears")
}

@Test @MainActor func unmutingToAQuietLevelUnlocksTheSlider() async {
    let devices = VolumeDevices(volume(0.5, muted: true))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    devices.current = volume(0.05)
    await welcome.rereadVolume()
    expectEq(welcome.soundCheck, .showing(volume(0.05)), "unmuted but quiet: the card stays, unmuted")
    welcome.setVolume(0.1)
    await welcome.volumeWritesSettled()
    expectEq(devices.writes, [0.1], "the slider writes again once unmuted")
}

@Test @MainActor func crossingThirtyStillPlaysTheProbe() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    welcome.setVolume(0.3)
    await welcome.volumeWritesSettled()
    expectEq(devices.probes, 1, "the card left before the release, so the write chain plays the Pop")
}

@Test func theSoundCardAnimatesUnlessMotionIsReduced() {
    expect(WelcomeView.soundCardTiming(reduceMotion: true) == nil, "reduce motion: no animation")
    let timing = WelcomeView.soundCardTiming(reduceMotion: false)
    expectEq(timing?.enter, 0.4, "fr-sound-in: .4s")
    expectEq(timing?.exit, 0.6, "fr-sound-out: .6s")
}

@Test @MainActor func aMutedMacIsNeverWrittenNorProbed() async {
    let devices = VolumeDevices(volume(0.5, muted: true))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    welcome.setVolume(0.9)
    await welcome.probe()
    await welcome.volumeWritesSettled()
    expect(devices.writes.isEmpty, "muted: the slider never writes (system mute is respected)")
    expectEq(devices.probes, 0, "muted: no probe")
    expectEq(welcome.soundCheck, .showing(volume(0.5, muted: true)), "muted: the card stays up")
}

@Test @MainActor func letGoOfTheSliderPlaysTheProbeOnlyWhileShowing() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.probe()
    expectEq(devices.probes, 0, "before the check: no probe")
    await welcome.checkSound()
    await welcome.probe()
    expectEq(devices.probes, 1, "let go on the card: one probe")
    welcome.confirmSound()
    await welcome.probe()
    expectEq(devices.probes, 1, "after the card: no probe")
}

@Test @MainActor func aRaiseFromTheKeyboardClearsTheCard() async {
    let devices = VolumeDevices(volume(0.05))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    devices.current = volume(0.4)
    await welcome.rereadVolume()
    expectEq(welcome.soundCheck, .passed, "the volume keys count, as Incredible's volume_changed does")
}

@Test @MainActor func theCheckRunsOncePerWelcomeAndReopenRearmsIt() async {
    let devices = VolumeDevices(volume(0.6))
    let welcome = welcomeModel(devices)
    await welcome.checkSound()
    devices.current = volume(0.01)
    await welcome.checkSound()
    expectEq(welcome.soundCheck, .passed, "back to the cover and forward: not asked again")
    welcome.reopen()
    expectEq(welcome.soundCheck, .unchecked, "the welcome again from Settings: asked again")
    await welcome.checkSound()
    expectEq(welcome.soundCheck, .showing(volume(0.01)), "and the quiet Mac gets the card")
}

@Test @MainActor func theSoundCheckStyleCarriesIncrediblesMeasures() {
    let style = TrackSliderStyle.soundCheck
    expectEq(style.trackHeight, 4, "track: 4 px")
    expectEq(style.hitHeight, 28, "the input: 28 px tall")
    expectEq(style.knob, 18, "thumb: 18 px")
    expectEq(style.restScale, 1, "thumb at rest: full size")
    expectEq(style.activeScale, 1.12, "thumb pressed: scale 1.12")
    expectEq(style.fillHex, "FFFFFF", "fill: white")
    expectEq(style.trackAlpha, 0.22, "track: white at 22 %")
    expectEq(style.knobShadowAlpha, 0.25, "thumb shadow: #00000040")
    expectEq(style.knobShadowY, 4, "thumb shadow: 4 px down")
    expectEq(style.knobShadowRadius, 6, "thumb shadow: a 12 px CSS blur is a 6 pt radius")
    expectEq(style.duration, 0.2, "thumb growth: .2s")
    expectEq(style.curve, MotionCurve.easeOut, "thumb growth: ease-out")
    expectEq(style.step, 0.01, "step: 1 of 100")
}

@Test @MainActor func theCardStringsExistInBothLanguages() async {
    let keys = ["welcome.sound.title", "welcome.sound.body", "welcome.sound.muted", "welcome.sound.slider",
                "welcome.sound.heard", "welcome.sound.anyway"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in keys {
                expect(Localized.string(key) != key, "\(language): \(key) is translated")
            }
        }
    }
}

/// Gated visual review: with COMPANION_SNAPSHOTS=<dir>, the hello screen with
/// and without the card, in a light and a dark system appearance.
@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil))
@MainActor func soundCheckSnapshots() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try await Localized.scoped(to: .es) {
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .light ? "light" : "dark"
            for (name, level) in [("quiet", volume(0.08)), ("muted", volume(0.5, muted: true)), ("loud", volume(0.6))] {
                let welcome = welcomeModel(VolumeDevices(level))
                welcome.jump(to: .hello)
                await welcome.checkSound()
                let view = WelcomeView(welcome: welcome, chat: snapshotChat())
                    .frame(width: 720, height: 640)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                else {
                    Issue.record("snapshot encode failed: \(name)-\(tag)")
                    continue
                }
                try png.write(to: out.appendingPathComponent("welcome-sound-\(name)-\(tag).png"))
            }
        }
    }
}

@MainActor private func welcomeModel(_ devices: VolumeDevices) -> WelcomeModel {
    WelcomeModel(devices: devices, keyReady: { true },
                 defaults: UserDefaults(suiteName: "sound-check-\(UUID().uuidString)")!)
}

@MainActor private func snapshotChat() -> ChatViewModel {
    chat()
}

private final class VolumeDevices: WelcomeDevices, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: OutputVolume?
    private var _writes: [Double] = []
    private var _probes = 0
    private var said: [String] = []
    private var readGate: Gate?
    private var firstWriteGate: Gate?

    init(_ current: OutputVolume?) { _current = current }

    var current: OutputVolume? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
    var writes: [Double] { lock.withLock { _writes } }
    var probes: Int { lock.withLock { _probes } }
    var greetings: [String] { lock.withLock { said } }

    func granted(_ permission: WelcomePermission) async -> Bool { true }
    func request(_ permission: WelcomePermission) async -> Bool { true }
    func verifyScreenCapture() async -> Bool { true }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async { lock.withLock { said.append(text) } }
    func holdReads(on gate: Gate) { lock.withLock { readGate = gate } }
    func holdFirstWrite(on gate: Gate) { lock.withLock { firstWriteGate = gate } }

    func outputVolume() async -> OutputVolume? {
        // The value is taken before the hold, like a read that was already in flight.
        let (value, gate) = lock.withLock { (_current, readGate) }
        await gate?.wait()
        return value
    }

    func setOutputVolume(_ level: Double) async {
        let gate = lock.withLock { () -> Gate? in
            defer { firstWriteGate = nil }
            return firstWriteGate
        }
        await gate?.wait()
        lock.withLock { _writes.append(level) }
    }
    func playProbe() async { lock.withLock { _probes += 1 } }
}

/// Parks one caller until the test lets it go, so a race can be held open.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var open = false
    private var parked = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                parked = true
                if open { return true }
                waiter = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let parked = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            open = true
            defer { waiter = nil }
            return waiter
        }
        parked?.resume()
    }

    func untilArrived() async {
        while !lock.withLock({ parked }) { await Task.yield() }
    }
}
