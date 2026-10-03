import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Gap 2: with a live caption a word's light starts when the voice really said
// it; the three-words-a-second clock is only the fallback without one.

@Test @MainActor func aSaidWordRampsFromItsRealMoment() {
    let light = IslandMotionBudget.spokenWord.duration
    expectEq(IslandReveal.brightness(saidAt: nil, now: 100), 0, "sin decir: apagada aunque pase el tiempo")
    expectEq(IslandReveal.brightness(saidAt: 50, now: 50), 0, "empieza apagada al decirse")
    expectEq(IslandReveal.brightness(saidAt: 50, now: 50 + light), 1, "encendida tras el settle")
    // The settle curve's own midpoint, the same as the clock's ramp halfway.
    let half = IslandReveal.brightness(saidAt: 0, now: light / 2)
    expectEq(half, MotionCurve.value(IslandMotionBudget.spokenWord.curve, at: 0.5), "a medio camino: la curva settle")
    expectEq(half, IslandReveal.brightness(word: 0, elapsed: light / 2, speaking: true), "igual que el reloj a medio camino")
}

/// Word 2 said at 0.1 s is lit long before the clock's 2/3 s; word 1 still
/// unsaid at 1 s stays dark although the clock would have lit it.
@Test @MainActor func theRealMomentOverridesTheClock() {
    let light = IslandMotionBudget.spokenWord.duration
    let clock = IslandReveal.brightness(word: 2, elapsed: 0.1 + light, speaking: true)
    expectEq(clock, 0, "el reloj aun no llega a la tercera")
    expectEq(IslandReveal.brightness(saidAt: 0.1, now: 0.1 + light), 1, "la voz si")
    expectEq(IslandReveal.brightness(word: 1, elapsed: 1, speaking: true), 1, "el reloj ya la encendio")
    expectEq(IslandReveal.brightness(saidAt: nil, now: 1), 0, "la voz no la ha dicho")
}

@Test @MainActor func reduceMotionTurnsASaidWordAtOnce() {
    expectEq(IslandReveal.brightness(saidAt: 2, now: 2.01, reduceMotion: true), 1, "dicha: de golpe")
    expectEq(IslandReveal.brightness(saidAt: nil, now: 2.01, reduceMotion: true), 0, "sin decir: apagada")
}

@Test @MainActor func theViewModelMirrorsTheVoiceCaption() async {
    let voice = FakeVoice()
    let model = VoiceViewModel(voice: voice, thread: FakePresenter())
    model.onAppear()
    let caption = CaptionSnapshot(
        utterance: 1, words: [CaptionWord(text: "hola", saidAt: 3), CaptionWord(text: "mundo")])
    voice.yieldCaption(caption)
    await pumpUntil("el caption llega al view model") { model.caption == caption }
}

@Test @MainActor func theViewModelMirrorsAClearedCaption() async {
    let voice = FakeVoice()
    let model = VoiceViewModel(voice: voice, thread: FakePresenter())
    model.onAppear()
    let live = CaptionSnapshot(utterance: 1, words: [CaptionWord(text: "hola", saidAt: 3)])
    voice.yieldCaption(live)
    await pumpUntil("el caption llega") { model.caption == live }
    voice.yieldCaption(CaptionSnapshot(utterance: 2))
    await pumpUntil("el corte llega") { model.caption.words.isEmpty }
}

/// Only a live caption paints with real times; a settled or empty one hands
/// the reply back to the three-words-a-second clock.
@Test @MainActor func aSettledOrEmptyCaptionFallsBackToTheClock() {
    var caption = CaptionSnapshot(
        utterance: 1, words: [CaptionWord(text: "Hola", saidAt: 1), CaptionWord(text: "mundo")])
    let live = IslandLiveReply.painting(caption)
    expectEq(live?.text, "Hola mundo", "en vivo: el texto del caption, ya pasado por el panel")
    expectEq(live?.said, [1, nil], "en vivo: los tiempos reales")
    caption.settled = true
    expect(IslandLiveReply.painting(caption) == nil, "asentado: vuelve el reloj")
    expect(IslandLiveReply.painting(.empty) == nil, "vacio: vuelve el reloj")
}

/// The live text goes through the panel's own shaping, as a finished reply does.
@Test @MainActor func theLiveTextIsShapedLikeTheFinishedReply() {
    let caption = CaptionSnapshot(
        utterance: 1, words: [CaptionWord(text: "**Hola**", saidAt: 1), CaptionWord(text: "mundo")])
    expectEq(IslandLiveReply.painting(caption)?.text, IslandReplyText.spoken(from: "**Hola** mundo"),
             "el mismo filtro que la respuesta terminada")
}
