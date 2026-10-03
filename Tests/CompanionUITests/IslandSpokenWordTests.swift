import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Incredible 0.2.36's spoken reply: every word is on screen from the start in the muted
// ink and turns primary when it is said, its color settling over 220 ms.

@Test @MainActor func aWordNotYetSaidIsMutedAndASaidOneIsPrimary() {
    let word = IslandMotionBudget.spokenWord
    expectEq(word.unsaid, 0.48, "sin decir: blanco al 48 %")
    expectEq(word.said, 0.94, "dicha: blanco al 94 %")
    expectEq(word.curve, [0.32, 0.72, 0, 1], "el color pasa con la curva settle")
    expectEq(word.duration, 0.22, "en 220 ms")
}

@Test @MainActor func aSaidWordLightsAlongTheSettleCurve() {
    let light = IslandMotionBudget.spokenWord.duration
    expectEq(IslandReveal.brightness(word: 0, elapsed: 0, speaking: true), 0, "palabra: empieza apagada")
    let half = IslandReveal.brightness(word: 0, elapsed: light / 2, speaking: true)
    expect(abs(half - MotionCurve.value(MotionCurve.settle, at: 0.5)) < 1e-9, "a mitad: la curva settle, no una recta: \(half)")
    expect(half > 0.5, "settle llega rapido y se asienta: \(half)")
    expectEq(IslandReveal.brightness(word: 0, elapsed: light, speaking: true), 1, "palabra: termina encendida")
    expectEq(IslandReveal.brightness(word: 0, elapsed: 30, speaking: true), 1, "palabra: se queda encendida")
}

@Test @MainActor func eachWordLightsFromItsOwnMoment() {
    let start = 2 / IslandReveal.wordsPerSecond
    expectEq(IslandReveal.brightness(word: 2, elapsed: start, speaking: true), 0, "la tercera empieza a su tiempo")
    expectEq(IslandReveal.brightness(word: 2, elapsed: start - 0.1, speaking: true), 0, "antes de su tiempo, apagada")
    expectEq(IslandReveal.brightness(word: 7, elapsed: 0, speaking: false), 1, "sin voz, todas encendidas")
}

@Test @MainActor func underReduceMotionASaidWordTurnsAtOnce() {
    let start = 2 / IslandReveal.wordsPerSecond
    expectEq(IslandReveal.brightness(word: 2, elapsed: start - 0.01, speaking: true, reduceMotion: true), 0,
             "reducido: sin decir, apagada")
    expectEq(IslandReveal.brightness(word: 2, elapsed: start + 0.01, speaking: true, reduceMotion: true), 1,
             "reducido: dicha, encendida sin transicion")
    expectEq(IslandReveal.brightness(word: 2, elapsed: start, speaking: true, reduceMotion: true), 0,
             "reducido: en su instante aun apagada, como sin reducir")
    expectEq(IslandReveal.brightness(word: 7, elapsed: 0, speaking: false, reduceMotion: true), 1,
             "reducido y sin voz: todas encendidas")
}

@Test @MainActor func aCurveStartsAndEndsExactly() {
    for (name, curve) in [("settle", MotionCurve.settle), ("standard", MotionCurve.standard),
                          ("island", MotionCurve.island)] {
        expectEq(MotionCurve.value(curve, at: 0), 0, "\(name): empieza exacto en 0")
        expectEq(MotionCurve.value(curve, at: 1), 1, "\(name): termina exacto en 1")
        expectEq(MotionCurve.value(curve, at: -0.5), 0, "\(name): antes de empezar, 0")
        expectEq(MotionCurve.value(curve, at: 1.5), 1, "\(name): despues de terminar, 1")
    }
}

@Test @MainActor func aWordsInkGoesFromMutedToPrimary() {
    let word = IslandMotionBudget.spokenWord
    expectEq(word.alpha(brightness: 0), 0.48, "apagada: muted")
    expectEq(word.alpha(brightness: 1), 0.94, "encendida: primary")
    expect(abs(word.alpha(brightness: 0.5) - 0.71) < 1e-9, "a mitad: entre las dos")
}
