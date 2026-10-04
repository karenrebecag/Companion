@testable import CompanionServices
import CompanionTestKit
import Testing

// WIN-14: the welcome's pad is synthesized, so the one thing that can go
// wrong without a speaker is the loop point clicking.

@Test func welcomeMusicLoopIsSeamless() {
    let samples = WelcomeMusicLoop.samples()
    expectEq(samples.count, Int(WelcomeMusicLoop.sampleRate * WelcomeMusicLoop.seconds), "loop: exactly 8 s")
    expect(!samples.contains { $0.isNaN }, "loop: no NaN sample")
    let peak = samples.map(abs).max() ?? 0
    expect(peak <= WelcomeMusicLoop.level + 1e-6 && peak > 0.01, "loop: audible and never clipping (peak \(peak))")
    let seam = abs((samples.last ?? 0) - (samples.first ?? 1))
    // One sample step of the top voice at this level is ~1.7e-3, so a tighter bound than the
    // interior-step check below would fail the loop for being a sine.
    expect(seam <= 5e-3, "loop: the last sample meets the first (gap \(seam))")
    let steps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
    expect(seam <= (steps.max() ?? 0), "loop: the seam is no bigger than the steepest step inside the loop")
}

@Test func welcomeMusicRestartsOnlyTheWantedCurrentEngine() {
    expect(WelcomeMusicRestart.restarts(wanted: true, sameEngine: true), "restart: wanted and current")
    expect(!WelcomeMusicRestart.restarts(wanted: false, sameEngine: true), "restart: a stop in between is not undone")
    expect(!WelcomeMusicRestart.restarts(wanted: true, sameEngine: false), "restart: a stale engine's change is ignored")
    expect(!WelcomeMusicRestart.restarts(wanted: false, sameEngine: false), "restart: neither")
}
