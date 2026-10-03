@testable import CompanionUI
import CompanionTestKit
import CoreGraphics
import Testing

// Island volume parity: Incredible draws its island volume as a 6 px track,
// an accent fill and a 12 px white knob that rests small and grows on hover
// or focus (firstRun-BOTAwJJ8.css, the .ov-volume-* rules; overlay-DstkIEbM.js,
// the island-volume-track, step 5 of 100). The native Slider can't take that
// shape, so the design system draws it.

private let unit: ClosedRange<Double> = 0...1
/// The island's own range: its volume never reaches silence.
private let island: ClosedRange<Double> = 0.05...1

@Test @MainActor func theIslandStyleCarriesIncrediblesMeasures() {
    let style = TrackSliderStyle.island
    expectEq(style.trackHeight, 6, "track: 6 px")
    expectEq(style.knob, 12, "knob: 12 px")
    expectEq(style.restScale, 0.75, "knob at rest: scale .75")
    expectEq(style.activeScale, 1.15, "knob on hover or focus: scale 1.15")
    expectEq(style.fillHex, "4A9CFF", "fill: the overlay's --color-accent")
    expectEq(style.trackAlpha, 0.1, "track: the overlay's --color-surface-active, white at 10 %")
    expectEq(style.knobShadowAlpha, 0.4, "knob shadow: #0006")
    expectEq(style.knobShadowY, 1, "knob shadow: 1 px down")
    expectEq(style.knobShadowRadius, 1.5, "knob shadow: a 3 px CSS blur is a 1.5 pt SwiftUI radius")
    expectEq(style.duration, MotionTime.knob, "knob growth: .12s")
    expectEq(MotionTime.knob, 0.12, "knob growth: .12s")
    expectEq(style.curve, MotionCurve.standard, "knob growth: --ease-standard")
    expectEq(style.step, 0.05, "step: 5 of 100")
}

@Test @MainActor func theKnobRestsSmallAndGrowsWhenActive() {
    let style = TrackSliderStyle.island
    expectEq(style.knobScale(active: false), 0.75, "idle: the small knob")
    expectEq(style.knobScale(active: true), 1.15, "hover, focus or drag: the grown knob")
}

@Test @MainActor func reduceMotionDropsTheKnobAnimation() {
    let style = TrackSliderStyle.island
    expect(style.animation(reduceMotion: true) == nil, "reduce motion: the knob changes size at once")
    expect(style.animation(reduceMotion: false) != nil, "otherwise it eases")
}

@Test @MainActor func theFillFollowsTheValueClampedToTheRange() {
    expectEq(TrackSliderMath.fraction(0.5, in: unit), 0.5, "the middle: half full")
    expectEq(TrackSliderMath.fraction(-1, in: unit), 0, "below the range: empty")
    expectEq(TrackSliderMath.fraction(3, in: unit), 1, "above the range: full")
    expectEq(TrackSliderMath.fraction(0.05, in: island), 0, "the island's floor: empty")
    expectEq(TrackSliderMath.fraction(1, in: island), 1, "the island's top: full")
    expectEq(TrackSliderMath.fraction(0.4, in: 0.4...0.4), 0, "an empty range: no division by zero")
}

@Test @MainActor func aPointOnTheTrackSnapsToTheStep() {
    let step = TrackSliderStyle.island.step
    expectEq(TrackSliderMath.value(atX: 50, width: 100, in: unit, step: step), 0.5, "the middle")
    expectNear(TrackSliderMath.value(atX: 52, width: 100, in: unit, step: step), 0.5, "52 % snaps to 50")
    expectNear(TrackSliderMath.value(atX: 53, width: 100, in: unit, step: step), 0.55, "53 % snaps to 55")
    expectEq(TrackSliderMath.value(atX: -20, width: 100, in: unit, step: step), 0, "left of the track: the floor")
    expectEq(TrackSliderMath.value(atX: 140, width: 100, in: unit, step: step), 1, "right of the track: the top")
    expectEq(TrackSliderMath.value(atX: 0, width: 100, in: island, step: step), 0.05, "the island never goes silent")
    expectEq(TrackSliderMath.value(atX: 10, width: 0, in: island, step: step), 0.05, "a track with no width: the floor")
}

@Test @MainActor func aKeyMovesOneStepAndStopsAtTheEnds() {
    let step = TrackSliderStyle.island.step
    expectNear(TrackSliderMath.step(0.5, by: 1, in: unit, step: step), 0.55, "right or up: one step more")
    expectNear(TrackSliderMath.step(0.5, by: -1, in: unit, step: step), 0.45, "left or down: one step less")
    expectEq(TrackSliderMath.step(1, by: 1, in: island, step: step), 1, "at the top it stays")
    expectEq(TrackSliderMath.step(0.05, by: -1, in: island, step: step), 0.05, "at the floor it stays")
    expectNear(TrackSliderMath.step(0.52, by: 1, in: unit, step: step), 0.55, "off the grid: lands on the next step")
    expectNear(TrackSliderMath.step(0.52, by: -1, in: unit, step: step), 0.5, "off the grid: lands on the previous step")
}

@Test @MainActor func everyKeyStepOnTheIslandMovesAndLandsOnTheEnds() {
    let step = TrackSliderStyle.island.step
    var value = island.lowerBound
    for press in 1...19 {
        let next = TrackSliderMath.step(value, by: 1, in: island, step: step)
        expect(next > value, "up, press \(press): moves from \(value)")
        value = next
    }
    expectEq(value, 1, "19 presses up from the floor: exactly the top")
    for press in 1...19 {
        let next = TrackSliderMath.step(value, by: -1, in: island, step: step)
        expect(next < value, "down, press \(press): moves from \(value)")
        value = next
    }
    expectEq(value, island.lowerBound, "19 presses down from the top: exactly the floor")
    expectNear(TrackSliderMath.step(0.3, by: 1, in: island, step: step), 0.35, "0.3 up: 0.35")
    expectNear(TrackSliderMath.step(0.35, by: -1, in: island, step: step), 0.3, "0.35 down: 0.3")
}

@Test @MainActor func aPointOnTheIslandTrackSnapsToItsGrid() {
    let step = TrackSliderStyle.island.step
    // The island grid starts at its floor: 0.05 + k * 0.05.
    expectNear(TrackSliderMath.value(atX: 40, width: 100, in: island, step: step), 0.45, "40 %: 0.43 snaps to 0.45")
    expectNear(TrackSliderMath.value(atX: 53, width: 100, in: island, step: step), 0.55, "53 %: 0.5535 snaps to 0.55")
    expectEq(TrackSliderMath.value(atX: 100, width: 100, in: island, step: step), 1, "the end: exactly the top, no overshoot")
}

@Test func aStepThatChangesTheValueIsOneWholeEdit() {
    var calls: [String] = []
    TrackSliderMath.commit(0.55, over: 0.5, set: { calls.append("set \($0)") }, editing: { calls.append("editing \($0)") })
    expectEq(calls, ["editing true", "set 0.55", "editing false"], "begin, the value, end: a save-on-release caller saves it")
    calls = []
    TrackSliderMath.commit(1, over: 1, set: { calls.append("set \($0)") }, editing: { calls.append("editing \($0)") })
    expectEq(calls, [], "a press at the end changes nothing and saves nothing")
}

@Test func theKnobCentresOnTheEdgeOfTheFill() {
    expectEq(TrackSliderMath.knobX(fraction: 0, width: 200, knob: 12), -6, "empty: the knob's centre on the start")
    expectEq(TrackSliderMath.knobX(fraction: 1, width: 200, knob: 12), 194, "full: the knob's centre on the end")
    expectEq(TrackSliderMath.knobX(fraction: 0.5, width: 200, knob: 12), 94, "half: on the middle")
}

@Test func aStepOfZeroClampsInsteadOfDividingByIt() {
    expectEq(TrackSliderMath.value(atX: 30, width: 100, in: unit, step: 0), 0.3, "no grid: the raw point")
    expectEq(TrackSliderMath.step(0.3, by: 1, in: unit, step: 0), 0.3, "no grid: a key does nothing")
}

private func expectNear(_ got: Double, _ want: Double, _ message: String) {
    expect(abs(got - want) < 1e-9, "\(message): got \(got), want \(want)")
}
