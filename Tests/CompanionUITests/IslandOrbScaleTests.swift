import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Incredible 0.2.36's composer orb: it swells with the voice speaking back, never with the mic.

@Test @MainActor func theComposerOrbSwellsWithTheVoice() {
    let orb = IslandMotionBudget.composerOrb
    expectEq(orb.gain, 0.28, "orbe: crece hasta 28 % con el nivel")
    expectEq(orb.follow, .timing(MotionCurve.easeOut, 0.09), "orbe: sigue al nivel en 90 ms ease-out")
    expectEq(MotionCurve.easeOut, [0, 0, 0.58, 1], "ease-out de CSS")
    expectEq(orb.scale(level: 0, reduceMotion: false), 1, "orbe: en silencio, su tamano")
    expectEq(orb.scale(level: 1, reduceMotion: false), 1.28, "orbe: al maximo, 1.28")
    expect(abs(orb.scale(level: 0.5, reduceMotion: false) - 1.14) < 1e-9, "orbe: proporcional al nivel")
}

@Test @MainActor func theComposerOrbKeepsItsSizeOutsideTheRange() {
    let orb = IslandMotionBudget.composerOrb
    expectEq(orb.scale(level: -0.4, reduceMotion: false), 1, "orbe: un nivel negativo no lo encoge")
    expectEq(orb.scale(level: 3, reduceMotion: false), 1.28, "orbe: un pico no lo infla de mas")
}

// QA review: the headline rule lives in which level the orb reads.
@Test @MainActor func theComposerOrbReadsTheVoiceNotTheMic() {
    let orb = IslandMotionBudget.composerOrb
    expectEq(orb.scale(levels: VoiceLevels(mic: 1, agent: 0), reduceMotion: false), 1, "orbe: el microfono no lo mueve")
    expectEq(orb.scale(levels: VoiceLevels(mic: 0, agent: 1), reduceMotion: false), 1.28, "orbe: la voz si")
}

@Test @MainActor func aBrokenLevelLeavesTheComposerOrbItsSize() {
    let orb = IslandMotionBudget.composerOrb
    expectEq(orb.scale(level: .nan, reduceMotion: false), 1, "orbe: un nivel invalido no rompe la transformacion")
    expectEq(orb.scale(level: .infinity, reduceMotion: false), 1.28, "orbe: infinito topa en 1.28")
    expectEq(orb.scale(level: -.infinity, reduceMotion: false), 1, "orbe: menos infinito, su tamano")
}

@Test @MainActor func underReduceMotionTheComposerOrbHoldsStill() {
    let orb = IslandMotionBudget.composerOrb
    expectEq(orb.scale(level: 0.8, reduceMotion: true), 1, "reducido: sin escala")
    expect(orb.animation(reduceMotion: true) == nil, "reducido: sin transicion")
    expect(orb.animation(reduceMotion: false) == MotionCurve.animation(MotionCurve.easeOut, 0.09),
           "sin reducir: 90 ms ease-out")
}
