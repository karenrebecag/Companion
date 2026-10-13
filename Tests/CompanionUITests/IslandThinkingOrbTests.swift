import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// The island's lead orb and status words (feat/isla-orbe-pensando): which orb
// each state gets, and the pure timing behind Arc's text-morph and text-shimmer.

@Test @MainActor func leadMarkMapsEachIslandStateToItsOrb() {
    let cases: [(IslandState.Meter, IslandState.Line, IslandLeadMark?)] = [
        (.mic, .none, .voice(.listening)),
        (.agent, .speaking, .voice(.speaking)),
        (.none, .pending, .thinking(.ring)),
        (.none, .pasting, .thinking(.ring)),
        (.none, .thinking, .thinking(.rubik)),
        (.none, .acting(["Safari"]), .thinking(.globe)),
        (.none, .completed, nil),
        (.none, .none, nil),
    ]
    for (meter, line, expected) in cases {
        #expect(IslandLeadMark.of(meter: meter, line: line, jobRunning: false) == expected, "\(meter) \(line)")
    }
}

@Test @MainActor func aJobShowsTheWorkingOrbOnlyWhileItRuns() {
    let job = IslandState.Line.job(goal: "Ordenar", step: nil, steps: 2)
    #expect(IslandLeadMark.of(meter: .none, line: job, jobRunning: true) == .thinking(.braid))
    // A finished job hands the column back to the loader's check or cross.
    #expect(IslandLeadMark.of(meter: .agent, line: job, jobRunning: false) == nil)
}

@Test @MainActor func reduceMotionHandoffFadesWithoutGrowing() {
    #expect(IslandLeadOrb.handoffScale(reduceMotion: true) == 1)
    #expect(IslandLeadOrb.handoffScale(reduceMotion: false) < 1)
}

@Test @MainActor func statusWordsShareOneRowKeySoTheyMorph() {
    let words: [IslandState.Line] = [.pending, .thinking, .acting([]), .completed]
    #expect(Set(words.map(IslandCopy.rowKey)).count == 1)
    #expect(IslandCopy.rowKey(.job(goal: nil, step: nil, steps: 0)) == "job")
}

@Test @MainActor func morphPlanKeepsSharedLettersAndStaggersOnlyNewOnes() {
    let plan = TextMorphPlan.plan(from: "Enviando…", to: "Pensando…")
    let byKey = Dictionary(uniqueKeysWithValues: plan.map { ($0.key, $0) })
    // "ando…" is shared; the second "n" of the new word pairs with the second "n" of the old.
    #expect(byKey["a-0"]?.from == 4 && byKey["a-0"]?.to == 4)
    #expect(byKey["n-1"]?.from == 5 && byKey["n-1"]?.to == 5)
    #expect(plan.compactMap(\.enterOrder) == [0, 1, 2], "P, e and s are new")
    #expect(plan.filter { $0.to == nil }.map(\.character) == ["E", "v", "i"])
    #expect(plan.prefix(9).map { String($0.character) }.joined() == "Pensando…")
}

@Test @MainActor func aLabelAtRestHasNoLetterInMotion() {
    let rest = TextMorphPlan.plan(from: "Listo", to: "Listo")
    for glyph in rest {
        #expect(TextMorphLook(glyph: glyph, elapsed: 0) == TextMorphLook(glyph: glyph, elapsed: .infinity))
        #expect(TextMorphLook(glyph: glyph, elapsed: 0).opacity == 1)
    }
}

@Test @MainActor func morphStaggerIsCappedAndTheMorphEnds() {
    #expect(TextMorphTiming.enterDelay(order: 40) == TextMorphTiming.enterDelay(order: TextMorphTiming.staggerCap))
    let plan = TextMorphPlan.plan(from: "Pensando…", to: "Listo")
    let end = TextMorphTiming.total(plan)
    for glyph in plan {
        let settled = TextMorphLook(glyph: glyph, elapsed: end)
        #expect(settled.opacity == (glyph.to == nil ? 0 : 1), "\(glyph.key)")
    }
    #expect(abs(TextMorphTiming.layoutProgress(end) - 1) < 0.02)
}

@Test @MainActor func shimmerSweepsThenRestsOffTheText() {
    #expect(TextShimmerMotion.sweep(0) == 0)
    let midPass = TextShimmerMotion.leadIn + TextShimmerMotion.pass / 2
    #expect(abs(TextShimmerMotion.sweep(midPass) - 0.5) < 1e-9)
    // Between passes the band waits past the right edge.
    let resting = TextShimmerMotion.leadIn + TextShimmerMotion.pass * (1 + TextShimmerMotion.restShare / 2)
    #expect(TextShimmerMotion.sweep(resting) == 1)
    let left = TextShimmerMotion.bandEnds(sweep: 0, width: 80, em: 13)
    let right = TextShimmerMotion.bandEnds(sweep: 1, width: 80, em: 13)
    #expect(left.end <= 0 && right.start >= 1, "at either end of a pass no light is on the text")
}

@Test @MainActor func shimmerSettlesToSolidWhenWorkEnds() {
    #expect(TextShimmerMotion.settle(active: true, sinceToggle: .infinity) == 0)
    #expect(TextShimmerMotion.settle(active: false, sinceToggle: 0) == 0)
    #expect(TextShimmerMotion.settle(active: false, sinceToggle: TextShimmerMotion.settleOut) == 1)
}
