import CompanionUI
import Foundation
import Testing

@Test @MainActor func typewriterTests() {
    testEmptyPhrases()
    testTypesOneCharacterAtATime()
    testHoldsThenDeletes()
    testLoopsToNextPhrase()
    testOneShotKeepsLastPhrase()
    testReduceMotionShowsLast()
    testHumanJitterStaysInRange()
}

@MainActor private func twCfg() -> TypewriterConfig {
    TypewriterConfig(
        typeSpeed: 0.1,
        deleteSpeed: 0.05,
        pauseTyped: 0.2,
        pauseDeleted: 0.1,
        loop: true,
        human: false,
        cursor: true)
}

@MainActor func testEmptyPhrases() {
    expectEq(
        TypewriterMotion.visible(elapsed: 1, phrases: [], config: twCfg()),
        "",
        "typewriter: empty phrases")
}

@MainActor func testTypesOneCharacterAtATime() {
    let phrases = ["hola"]
    let cfg = twCfg()
    expectEq(
        TypewriterMotion.visible(elapsed: 0, phrases: phrases, config: cfg),
        "",
        "typewriter: start empty")
    expectEq(
        TypewriterMotion.visible(elapsed: 0.25, phrases: phrases, config: cfg),
        "ho",
        "typewriter: 2 chars at 0.25s / 0.1")
    expectEq(
        TypewriterMotion.visible(elapsed: 0.4, phrases: phrases, config: cfg),
        "hola",
        "typewriter: full at 0.4s")
}

@MainActor func testHoldsThenDeletes() {
    let phrases = ["ab"]
    let cfg = twCfg()
    expectEq(
        TypewriterMotion.visible(elapsed: 0.3, phrases: phrases, config: cfg),
        "ab",
        "typewriter: hold after typed")
    expectEq(
        TypewriterMotion.visible(elapsed: 0.45, phrases: phrases, config: cfg),
        "a",
        "typewriter: deleting")
    expectEq(
        TypewriterMotion.visible(elapsed: 0.5, phrases: phrases, config: cfg),
        "",
        "typewriter: deleted")
}

@MainActor func testLoopsToNextPhrase() {
    let phrases = ["a", "z"]
    expectEq(
        TypewriterMotion.visible(elapsed: 0.55, phrases: phrases, config: twCfg()),
        "z",
        "typewriter: second phrase after first cycle")
}

@MainActor func testOneShotKeepsLastPhrase() {
    var once = twCfg()
    once.loop = false
    let phrases = ["uno", "dos"]
    expectEq(
        TypewriterMotion.visible(elapsed: 20, phrases: phrases, config: once),
        "dos",
        "typewriter: one-shot stays on last")
}

@MainActor func testReduceMotionShowsLast() {
    expectEq(
        TypewriterMotion.visible(
            elapsed: 0,
            phrases: ["uno", "dos"],
            config: twCfg(),
            reduceMotion: true),
        "dos",
        "typewriter: reduce-motion last phrase")
}

@MainActor func testHumanJitterStaysInRange() {
    let d = TypewriterMotion.typeStepDuration(
        base: 0.07, human: true, unit: 3)
    expect(d >= 0.07 * 0.5, "typewriter: jitter floor")
    expect(d <= 0.07 * 1.5, "typewriter: jitter ceiling")
    expectEq(
        TypewriterMotion.typeStepDuration(base: 0.07, human: false, unit: 3),
        0.07,
        "typewriter: no jitter when human is off")
}
