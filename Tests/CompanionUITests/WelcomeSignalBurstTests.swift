import AppKit
import CompanionCore
import CompanionTestKit
import CompanionUITestSupport
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// WIN-15: Incredible 0.2.36's intro "signal burst" (styles-CTdsYdwA.css @8523,
// @8771, @8881-8990, @9046) fires when the welcome's greeting starts speaking.

@MainActor private func near(_ got: Double, _ want: Double, _ message: String) {
    expect(abs(got - want) < 1e-9, "\(message): got \(got), want \(want)")
}

@Test @MainActor func theBurstStartsInvisibleAndSmall() {
    let start = SignalBurst.sample(at: 0)
    near(start.opacity, 0, "0%: invisible")
    near(start.scale, 0.5, "0%: half size")
}

@Test @MainActor func theBurstPeaksAtTenPercent() {
    let peak = SignalBurst.sample(at: 0.1)
    near(peak.opacity, 1, "10%: full")
    near(peak.scale, 0.8, "10%: .8")
}

@Test @MainActor func theBurstEndsInvisibleAndLarge() {
    let end = SignalBurst.sample(at: 1)
    near(end.opacity, 0, "100%: gone")
    near(end.scale, 1.3, "100%: 1.3")
}

@Test @MainActor func eachSegmentFollowsTheCurve() {
    let curve = SignalBurst.curve
    expectEq(curve, [0.2, 0.8, 0.2, 1], "curve: cubic-bezier(.2,.8,.2,1)")
    let rise = SignalBurst.sample(at: 0.05)
    near(rise.opacity, MotionCurve.value(curve, at: 0.5), "rise: opacity on the curve")
    near(rise.scale, 0.5 + 0.3 * MotionCurve.value(curve, at: 0.5), "rise: scale on the curve")
    expect(rise.opacity > 0 && rise.opacity < 1, "rise: strictly between")
    let local = (0.55 - 0.1) / 0.9
    let fall = SignalBurst.sample(at: 0.55)
    near(fall.opacity, 1 - MotionCurve.value(curve, at: local), "fall: opacity on the curve")
    near(fall.scale, 0.8 + 0.5 * MotionCurve.value(curve, at: local), "fall: scale on the curve")
    expect(fall.opacity > 0 && fall.opacity < 1, "fall: strictly between")
}

@Test @MainActor func samplingClampsOutsideTheAnimation() {
    let before = SignalBurst.sample(at: -3)
    let after = SignalBurst.sample(at: 9)
    near(before.opacity, 0, "below 0: the start")
    near(before.scale, 0.5, "below 0: the start scale")
    near(after.opacity, 0, "above 1: the end")
    near(after.scale, 1.3, "above 1: the end scale")
}

@Test @MainActor func theBurstMeasuresMatchIncredible() {
    expectEq(SignalBurst.duration, 0.7, "duration: .7s")
    expectEq(SignalBurst.width, 900, "width: 900")
    expectEq(SignalBurst.height, 320, "height: 320")
}

@Test @MainActor func reduceMotionNeverDrawsTheBurst() {
    expect(!SignalBurst.draws(reduceMotion: true), "reduce motion: nothing is drawn")
    expect(SignalBurst.draws(reduceMotion: false), "otherwise it is drawn")
}

@Test @MainActor func theCurveMatchesAHardCodedAnchor() {
    // Pinned from a run of cubic-bezier(.2,.8,.2,1) at the midpoint, so a
    // broken MotionCurve cannot agree with itself.
    expect(abs(MotionCurve.value([0.2, 0.8, 0.2, 1], at: 0.5) - 0.946079) < 1e-6, "curve anchor at 0.5")
}

@Test @MainActor func theGlowKeepsIncrediblesStopsOnDarkAndReadsOnLight() {
    let dark = SignalBurst.stops(dark: true)
    expectEq(dark.map(\.hex), ["EBF4FF", "C8E1FF", "C8E1FF"], "dark: Incredible's colours")
    expectEq(dark.map(\.alpha), [0.5, 0.2, 0], "dark: #ebf4ff80, #c8e1ff33, clear")
    expectEq(dark.last?.location, 0.7, "dark: clear at 70 %")
    let light = SignalBurst.stops(dark: false)
    expectEq(light.map(\.hex), ["AFCDFF", "AFCDFF", "AFCDFF"], "light: the .fr-bar blue")
    expectEq(light.map(\.alpha), [0.55, 0.2, 0], "light: stronger than on dark")
    expectEq(light.last?.location, 0.7, "light: clear at 70 %")
}

// MARK: the model fires one burst per spoken greeting

private final class QuietDevices: WelcomeDevices, @unchecked Sendable {
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {}
}

/// greet() suspends until the test releases it, so the burst can be observed
/// while the greeting is still being spoken.
private final class GatedDevices: WelcomeDevices, @unchecked Sendable {
    private let gate: AsyncStream<Void>
    private let open: AsyncStream<Void>.Continuation
    let entered: AsyncStream<Void>
    private let enter: AsyncStream<Void>.Continuation

    init() {
        (gate, open) = AsyncStream.makeStream()
        (entered, enter) = AsyncStream.makeStream()
    }

    func release() { open.yield() }
    func granted(_ permission: WelcomePermission) async -> Bool { false }
    func request(_ permission: WelcomePermission) async -> Bool { false }
    func verifyScreenCapture() async -> Bool { false }
    func micLevels() -> AsyncStream<Double> { AsyncStream { $0.finish() } }
    func greet(_ text: String, language: AppLanguage) async {
        enter.yield()
        for await _ in gate { return }
    }
}

@MainActor private func withQuietModel(
    _ devices: any WelcomeDevices = QuietDevices(),
    _ body: (WelcomeModel) async throws -> Void
) async rethrows {
    let suite = "burst-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(WelcomeModel(devices: devices, keyReady: { true }, defaults: defaults))
}

@Test @MainActor func theGreetingFiresOneBurstAndReopeningFiresAnother() async {
    await withQuietModel { welcome in
        expectEq(welcome.bursts, 0, "before the greeting: none")
        await welcome.greet()
        expectEq(welcome.bursts, 1, "the greeting starts: one burst")
        await welcome.greet()
        expectEq(welcome.bursts, 1, "a second greet does not start: still one")
        welcome.reopen()
        await welcome.greet()
        expectEq(welcome.bursts, 2, "reopened welcome greets again: another burst")
    }
}

@Test @MainActor func theBurstFiresWhenTheGreetingStartsNotWhenItEnds() async {
    let devices = GatedDevices()
    await withQuietModel(devices) { welcome in
        expectEq(welcome.bursts, 0, "before greet(): none")
        let first = Task { @MainActor in await welcome.greet() }
        for await _ in devices.entered { break }
        expectEq(welcome.bursts, 1, "greet suspended mid-speech: already one burst")
        await welcome.greet()
        expectEq(welcome.bursts, 1, "a concurrent greet: still one")
        devices.release()
        await first.value
        expectEq(welcome.bursts, 1, "greeting finished: still one")
    }
}

@Test @MainActor func skippingPastHelloWithoutGreetingFiresNoBurst() async {
    await withQuietModel { welcome in
        welcome.next()
        expectEq(welcome.bursts, 0, "no greet(): no burst")
    }
}

// MARK: gallery

@Test @MainActor func signalBurstSnapshots() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        let tag = scheme == .light ? "light" : "dark"
        for (name, shown) in [("peak", true), ("none", false)] {
            try await withQuietModel { welcome in
                welcome.next()
                let page = WelcomeView(welcome: welcome, chat: chat())
                    .overlay(alignment: .top) {
                        if shown { WelcomeSignalBurst(fraction: 0.1).environment(\.colorScheme, scheme) }
                    }
                try render(page, scheme: scheme, to: out, "welcome-burst-\(name)-\(tag)")
            }
        }
    }
}

@MainActor private func render<V: View>(_ view: V, scheme: ColorScheme, to dir: URL, _ name: String) throws {
    let framed = view
        .frame(width: 1120, height: 700)
        .environment(\.colorScheme, scheme)
        .environment(DropdownHost())
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        Issue.record("welcome-burst: \(name) could not be rendered")
        return
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
}
