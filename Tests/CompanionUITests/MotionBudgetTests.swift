import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Spec 16f §9: the smooth-motion rules, checked on the tokens every view
// reads. A view cannot write its own curve (conformance rule soft-easing),
// so holding the tokens holds the app.

@Test @MainActor func motionBudgetTests() {
    testOneEnterCurve()
    testSpringsBarelyOvershoot()
    testOpeningSettlesInFourHundredMilliseconds()
    testClosingIsFasterThanOpening()
    testAmplitudesStaySmall()
    testLinesEnterInStepsOfFortyMilliseconds()
    testReduceMotionIsAShortFade()
    testEachWordBrightensOverAFade()
    testTheStatusLineSwapsOnlyWhenItsKindChanges()
    testSettleCountsTheEnvelope()
}

@MainActor func testOneEnterCurve() {
    expectEq(MotionCurve.enter, [0.22, 1, 0.36, 1], "M3: la curva de entrada es ease-out fuerte")
    expect(MotionCurve.enter[1] >= 1, "M3: arranca rápido, nunca ease-in al entrar")
}

@MainActor func testSpringsBarelyOvershoot() {
    for (name, spring) in MotionSpring.all {
        expect(spring.overshoot <= 0.02, "M4: \(name) sobrepasa \(spring.overshoot)")
    }
    expectEq(MotionSpring(response: 0.2, damping: 1).overshoot, 0, "M4: críticamente amortiguado no rebota")
    expect(abs(MotionSpring(response: 0.18, damping: 0.82).overshoot - 0.011) < 0.003,
           "M4: el resorte del panel rebota poco, como en la grabación (1,6 % medido)")
}

@MainActor func testOpeningSettlesInFourHundredMilliseconds() {
    let open = IslandMotion.shapeOpen
    let shape = IslandMotion.secondPhase + MotionCurve.settledAt(MotionCurve.island, duration: open.duration)
    expect(shape <= 0.3, "M2: la forma queda a 2 % en \(shape) s")
    let content = IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false)
        + IslandMotionBudget.contentIn.duration
    expect(content <= 0.4, "M2: el contenido termina de entrar en \(content) s")
}

@MainActor func testClosingIsFasterThanOpening() {
    let close = IslandMotion.shapeClose.duration
    let open = IslandMotion.secondPhase + IslandMotion.shapeOpen.duration
    expect(close <= 0.28, "Incredible: cerrar en 280 ms como máximo (\(close) s)")
    expect(close < open, "cerrar es más rápido que abrir")
}

@MainActor func testAmplitudesStaySmall() {
    for (name, move) in IslandMotionBudget.moves {
        expect(move.blur <= 3, "M5: \(name) desenfoca \(move.blur)")
        expect(abs(move.offset) <= 12, "M5: \(name) se desplaza \(move.offset)")
        expect(move.duration >= MotionTime.fast * 0.8, "M1: \(name) dura \(move.duration), casi un corte")
    }
}

@MainActor func testLinesEnterInStepsOfFortyMilliseconds() {
    expectEq(IslandMotionBudget.lineStep, 0.04, "M6: escalonado de 40 ms")
    expectEq(IslandMotionBudget.delay(line: 0), 0, "M6: la primera ya")
    expectEq(IslandMotionBudget.delay(line: 9), IslandMotionBudget.lineStep * 4,
             "M6: después de la quinta línea, todas juntas")
}

@MainActor func testReduceMotionIsAShortFade() {
    for (name, move) in IslandMotionBudget.moves {
        let reduced = move.reduced
        expect(reduced.duration <= MotionTime.fast, "M8: \(name) dura \(reduced.duration)")
        expectEq(reduced.blur, 0, "M8: \(name) sin desenfoque")
        expectEq(reduced.offset, 0, "M8: \(name) sin desplazamiento")
    }
}

@MainActor func testEachWordBrightensOverAFade() {
    let fade = IslandMotionBudget.wordFade
    expectEq(IslandReveal.brightness(word: 0, elapsed: 0, speaking: true), 0, "palabra: empieza gris")
    expectEq(IslandReveal.brightness(word: 0, elapsed: fade / 2, speaking: true), 0.5, "palabra: a medio fundido")
    expectEq(IslandReveal.brightness(word: 0, elapsed: fade, speaking: true), 1, "palabra: termina clara")
    let third = 2 / IslandReveal.wordsPerSecond
    expectEq(IslandReveal.brightness(word: 2, elapsed: third, speaking: true), 0,
             "palabra: cada una empieza a su tiempo")
    expectEq(IslandReveal.brightness(word: 7, elapsed: 0, speaking: false), 1, "palabra: sin voz, clara")
}

/// Code review 16f-2 (HIGH): the swap was keyed on the formatted text, so a
/// job's step counter blurred the line out and in on every step.
@MainActor func testTheStatusLineSwapsOnlyWhenItsKindChanges() {
    expectEq(IslandCopy.swapKey(.job(goal: "ordenar", step: "uno", steps: 1)),
             IslandCopy.swapKey(.job(goal: "ordenar", step: "dos", steps: 2)),
             "estado: un paso más no es otro estado")
    expect(IslandCopy.swapKey(.thinking) != IslandCopy.swapKey(.speaking), "estado: pensar y hablar sí cambian")
}

/// Code review 16f-2 (LOW): settle left out the envelope's amplitude term.
@MainActor func testSettleCountsTheEnvelope() {
    let spring = MotionSpring(response: 0.18, damping: 0.82)
    expect(abs(spring.settle - 0.156) < 0.005, "resorte: 0,18/0,82 se asienta en ~156 ms (\(spring.settle))")
}
