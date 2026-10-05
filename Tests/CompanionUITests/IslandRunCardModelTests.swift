import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The run card's pure model, pinned to firstRun-BOTAwJJ8.css.

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@MainActor private func step(
    _ tool: String = "Bash", id: String = "a", done: Bool = false,
    failed: Bool = false, start: Double = 0, end: Double? = nil
) -> JobStepInfo {
    JobStepInfo(
        tool: tool, label: "\(tool) \(id)", done: done, failed: failed, id: id,
        startedAt: t0.addingTimeInterval(start),
        finishedAt: end.map { t0.addingTimeInterval($0) })
}

@Test @MainActor func runCardMetricsPinned() {
    typealias M = RunCardMetrics
    #expect(M.minWidth == 320 && M.maxWidth == 420)
    #expect(M.padTop == 14 && M.padSide == 16 && M.padBottom == 12)
    #expect(M.radius == 20)
    #expect(M.riseOffset == 6 && M.fadeSeconds == 0.2)
    #expect(M.headGap == 10 && M.headBottom == 8)
    #expect(M.titleSize == 13 && M.metaSize == 11.5 && M.metaOpacity == 0.55)
    #expect(M.rowPadV == 5 && M.rowPadH == 2 && M.rowGap == 2 && M.mainGap == 10)
    #expect(M.glyphSide == 18 && M.glyphTop == 1 && M.glyphFont == 11)
    #expect(M.spinnerSide == 14 && M.spinnerStroke == 2 && M.spinnerPeriod == 0.9)
    #expect(M.stepTitleSize == 12.5)
    #expect(M.durationSize == 11.5 && M.durationLead == 10)
}

@Test @MainActor func runCardInksPinned() {
    func c(_ hex: String, _ a: Double = 1) -> Color {
        a == 1 ? Swatch(hex).color : Swatch(hex).color.opacity(a)
    }
    #expect(IslandInk.runCardBg == c("121317"))
    #expect(IslandInk.runCardShadowNear == c("000000", 0x4d / 255))
    #expect(IslandInk.runCardShadowFar == c("000000", 0x52 / 255))
    #expect(IslandInk.runGlyphDoneBg == c("7EE2A8", 0x2e / 255))
    #expect(IslandInk.runGlyphDoneInk == c("7EE2A8"))
    #expect(IslandInk.runGlyphFailedBg == c("E05A46", 0x33 / 255))
    #expect(IslandInk.runGlyphFailedInk == c("F0917F"))
    #expect(IslandInk.runSpinnerTrack == c("7EE2A8", 0x40 / 255))
    #expect(IslandInk.runSpinnerArc == c("7EE2A8", 0.95))
    #expect(IslandInk.runTitleDone == c("FFFFFF", 0x6b / 255))
    #expect(IslandInk.runTitleFailed == c("FFFFFF", 0x9e / 255))
    #expect(IslandInk.runTitleLive == c("FFFFFF"))
    #expect(IslandInk.runDurationLive == c("7EE2A8", 0xd9 / 255))
    #expect(IslandInk.runDurationFinished == c("FFFFFF", 0x66 / 255))
}

@Test(arguments: [
    (0.0, "0s"), (12, "12s"), (59.9, "59s"), (60, "1m 00s"),
    (65, "1m 05s"), (600, "10m 00s"), (-3, "0s"),
])
@MainActor func runCardStepDuration(seconds: Double, expected: String) {
    #expect(RunCardDuration.step(seconds) == expected)
}

@Test(arguments: [(0.0, "0:00"), (65, "1:05"), (754, "12:34"), (3661, "61:01"), (-5, "0:00")])
@MainActor func runCardTotalDuration(seconds: Double, expected: String) {
    #expect(RunCardDuration.total(seconds) == expected)
}

@Test @MainActor func rowsDropThinkingAndKeepEveryStepInOrder() {
    let thinking = step(JobSteps.Thinking.tool, id: "t")
    #expect(RunCardModel.rows(steps: [thinking], now: t0).isEmpty)
    let nine = (0..<9).map { step(id: "s\($0)", done: true, start: Double($0), end: Double($0) + 1) }
    let rows = RunCardModel.rows(steps: [thinking] + nine, now: t0.addingTimeInterval(20))
    #expect(rows.map(\.id) == (0..<9).map { "s\($0)" })
    #expect(rows.first?.title == "Bash s0")
}

@Test @MainActor func rowsStatesAndDurations() {
    let steps = [
        step(id: "d", done: true, start: 0, end: 12),
        step(id: "f", done: true, failed: true, start: 12, end: 77),
        step(id: "l", start: 77),
    ]
    let rows = RunCardModel.rows(steps: steps, now: t0.addingTimeInterval(80))
    #expect(rows.map(\.state) == [.done, .failed, .live])
    #expect(rows[0].duration == "12s" && !rows[0].durationIsLive)
    #expect(rows[1].duration == "1m 05s" && !rows[1].durationIsLive)
    #expect(rows[2].duration == "3s" && rows[2].durationIsLive)
}

@Test @MainActor func finishedStepWithoutEndHasNoDuration() {
    let steps = [
        step(id: "d", done: true, start: 0),
        step(id: "f", done: true, failed: true, start: 0),
        step(id: "l", start: 0),
    ]
    let rows = RunCardModel.rows(steps: steps, now: t0.addingTimeInterval(9))
    #expect(rows[0].duration == nil && rows[1].duration == nil)
    #expect(rows[2].duration == "9s")
}

@Test @MainActor func runCardShadowGeometryPinned() {
    typealias M = RunCardMetrics
    #expect(M.shadowNearY == 1 && M.shadowNearBlur == 2)
    #expect(M.shadowFarY == 18 && M.shadowFarBlur == 48)
}

@Test @MainActor func metaAndFlags() {
    #expect(RunCardModel.meta(jobStartedAt: t0, now: t0.addingTimeInterval(65)) == "1:05")
    let live = RunCardModel.rows(steps: [step(start: 0)], now: t0)
    let none = RunCardModel.rows(steps: [step(done: true, start: 0, end: 1)], now: t0)
    #expect(live.map(\.state) == [.live] && none.map(\.state) == [.done])
    #expect(!RunCardModel.visible(hovering: false, focused: false))
    #expect(RunCardModel.visible(hovering: true, focused: false))
    #expect(RunCardModel.visible(hovering: false, focused: true))
    #expect(RunCardModel.visible(hovering: true, focused: true))
    #expect(RunCardModel.spins(reduceMotion: false))
    #expect(!RunCardModel.spins(reduceMotion: true))
}

@Test @MainActor func glyphPerState() {
    #expect(RunCardModel.glyph(for: .done) == .symbol("checkmark"))
    #expect(RunCardModel.glyph(for: .failed) == .symbol("xmark"))
    #expect(RunCardModel.glyph(for: .live) == .spinner)
}

@Test @MainActor func liveDurationAdvancesWithNow() {
    let steps = [step(id: "l", start: 0)]
    let early = RunCardModel.rows(steps: steps, now: t0.addingTimeInterval(3))
    let late = RunCardModel.rows(steps: steps, now: t0.addingTimeInterval(9))
    #expect(early[0].duration == "3s" && late[0].duration == "9s")
}

@Test @MainActor func aBareJobStillHasAHoverTarget() {
    var p = SessionProjection()
    p.kind = .processing(.subAgentRunning)
    p.voice = .live
    p.presence = .active
    p.job = JobTimeline(goal: "Ordenar")
    let state = IslandState.from(p, pebbleHidden: false)
    guard case .job = state.line else {
        Issue.record("a bare job should draw the job line, got \(state.line)")
        return
    }
    #expect(state.partial == nil && state.receipt == nil && p.touched.isEmpty)
    #expect(RunCardModel.hoverRegionExists(size: state.size))
    #expect(!RunCardModel.hoverRegionExists(size: .hidden))
    #expect(!RunCardModel.hoverRegionExists(size: .pebble))
}

@Test @MainActor func theOuterColumnAnchorsToTheBottomOnlyWhileTheCardShows() {
    #expect(RunCardModel.anchorsColumnBottom(cardVisible: true))
    #expect(!RunCardModel.anchorsColumnBottom(cardVisible: false))
}

@Test @MainActor func theCardNeedsAHoverRegionAtTheCurrentSize() {
    #expect(RunCardModel.showsCard(rawHover: true, size: .bar, focused: false))
    #expect(!RunCardModel.showsCard(rawHover: true, size: .pebble, focused: false))
    #expect(!RunCardModel.showsCard(rawHover: true, size: .hidden, focused: false))
    #expect(!RunCardModel.showsCard(rawHover: false, size: .bar, focused: false))
    #expect(RunCardModel.showsCard(rawHover: false, size: .bar, focused: true))
}

@Test @MainActor func aResizeToASizeWithoutARegionClearsTheHover() {
    #expect(!RunCardModel.hoverAfterResize(raw: true, newSize: .pebble))
    #expect(!RunCardModel.hoverAfterResize(raw: true, newSize: .hidden))
    #expect(RunCardModel.hoverAfterResize(raw: true, newSize: .card))
    #expect(!RunCardModel.hoverAfterResize(raw: false, newSize: .bar))
}

@Test @MainActor func theGoalIsCleanedLikeAStepTitle() {
    #expect(RunCardModel.goal("Ordenar \u{202E}fdp\n\u{200B}capturas") == "Ordenar fdp capturas")
}

@Test @MainActor func lineAndParagraphSeparatorsBecomeASpace() {
    #expect(RunCardModel.goal("a\u{2028}b\u{2029}c") == "a b c")
}

@Test @MainActor func zeroWidthSpaceAndDirectionMarksAreDropped() {
    #expect(RunCardModel.goal("a\u{200B}b\u{200E}c\u{200F}d") == "abcd")
}

@Test @MainActor func joinersSurviveForScriptsAndEmoji() {
    let persian = "می\u{200C}خواهم"
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    #expect(RunCardModel.goal(persian) == persian)
    #expect(RunCardModel.goal(family) == family)
}

@Test @MainActor func titlesLoseControlAndFormatCharacters() {
    func title(_ raw: String) -> String {
        let s = JobStepInfo(tool: "Bash", label: raw, done: true, id: "x", startedAt: t0, finishedAt: t0)
        return RunCardModel.rows(steps: [s], now: t0)[0].title
    }
    #expect(title("rm \u{202E}fdp.txt") == "rm fdp.txt")
    #expect(title("a\u{2066}b\u{2067}c\u{2068}d\u{2069}e") == "abcde")
    #expect(title("one\n\ntwo\t three   four") == "one two three four")
    #expect(title("Bash: ls ~/Desktop") == "Bash: ls ~/Desktop")
    #expect(title("Leer el archivo \u{1F4C4} listo") == "Leer el archivo \u{1F4C4} listo")
}

@Test @MainActor func everyStateHasASpokenValueInBothLanguages() throws {
    let root = try #require(Conformance.repoRoot())
    let base = root.appendingPathComponent("Sources/CompanionUI")
    let en = Conformance.keys(in: base.appendingPathComponent("en.lproj/Localizable.strings"))
    let es = Conformance.keys(in: base.appendingPathComponent("es.lproj/Localizable.strings"))
    let keys = [RunCardRow.State.done, .failed, .live].map(RunCardModel.stateKey)
    #expect(Set(keys).count == 3)
    for key in keys { #expect(en.contains(key) && es.contains(key)) }
    #expect(!en.contains("island.checklist.dismiss") && !es.contains("island.checklist.dismiss"))
}
