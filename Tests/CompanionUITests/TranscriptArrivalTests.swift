import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// Arc's VoiceTranscript: words settle in from a soft blur as they stream.
// Only words that are new (or that the ear rewrote) arrive; the rest stay put.

@Test @MainActor func newWordsArriveNowAndOldOnesKeepTheirTime() {
    let first = TranscriptArrivals.update(previous: [], births: [], next: ["abre", "el"], now: 10)
    expectEq(first, [10, 10], "las primeras llegan ahora")
    let more = TranscriptArrivals.update(previous: ["abre", "el"], births: first, next: ["abre", "el", "correo"], now: 11)
    expectEq(more, [10, 10, 11], "solo la nueva llega ahora")
}

@Test @MainActor func aRewrittenWordArrivesAgain() {
    let next = TranscriptArrivals.update(previous: ["abre", "el", "coreo"], births: [1, 1, 2],
                                         next: ["abre", "el", "correo", "de"], now: 3)
    expectEq(next, [1, 1, 3, 3], "lo que el oido corrigio vuelve a entrar")
}

@Test @MainActor func aShorterTextDropsTheTail() {
    let next = TranscriptArrivals.update(previous: ["a", "b", "c"], births: [1, 2, 3], next: ["a"], now: 4)
    expectEq(next, [1], "lo que se fue no deja huella")
}

@Test @MainActor func aWordSettlesInFromABlur() {
    let start = TranscriptArrivals.look(age: 0, reduceMotion: false)
    expectEq(start.opacity, 0, "al llegar: invisible")
    expectEq(start.blur, ArcMotion.Blur.soft, "al llegar: blur suave de Arc")
    expectEq(start.rise, TranscriptArrivals.rise, "al llegar: tres puntos abajo")
    let settled = TranscriptArrivals.look(age: TranscriptArrivals.duration, reduceMotion: false)
    expectEq(settled.opacity, 1, "asentada: entera")
    expectEq(settled.blur, 0, "asentada: nitida")
    expectEq(settled.rise, 0, "asentada: en su linea")
    expectEq(TranscriptArrivals.duration, 0.34, "Arc: 0.34 s por palabra")
}

@Test @MainActor func reduceMotionShowsWordsAtOnce() {
    let look = TranscriptArrivals.look(age: 0, reduceMotion: true)
    expectEq(look.opacity, 1, "reducido: entera de inmediato")
    expectEq(look.blur, 0, "reducido: sin blur")
    expectEq(look.rise, 0, "reducido: sin viaje")
}

@Test @MainActor func aClockStepBackNeverRewindsAWord() {
    let look = TranscriptArrivals.look(age: -2, reduceMotion: false)
    expectEq(look.opacity, 0, "edad negativa: como recien llegada, no algo raro")
}

// Review: the top fade belongs only to lines that lift away past the cap;
// a one- or two-line transcript is drawn whole.
@Test @MainActor func theTranscriptFadesOnlyWhatOverflows() {
    expect(!TranscriptFade.fadesTop(content: 21, cap: 42), "una linea: sin fundido")
    expect(!TranscriptFade.fadesTop(content: 42, cap: 42), "dos lineas justas: sin fundido")
    expect(TranscriptFade.fadesTop(content: 63, cap: 42), "tres lineas: la de arriba se va")
}

@Test @MainActor func theFadeIgnoresLayoutRounding() {
    expect(!TranscriptFade.fadesTop(content: 42.4, cap: 42), "medio punto de redondeo: sin fundido")
    expect(TranscriptFade.fadesTop(content: 42.6, cap: 42), "pasado el redondeo: fundido")
}
