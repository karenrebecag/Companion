import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 16q-1 review (security M3): timing alone let the voice model call
// `resolve_approval(true)` in the hold after the question, whatever the user
// said, and a specialist's output can plant that instruction. A yes is
// admitted only when the words the user said in THAT hold are a clear
// affirmation from a closed es/en list, with no negation next to it. A judge
// model (16q-3) replaces this later.

@Test @MainActor func spokenYes16qTests() {
    testClearAffirmationsAreAdmitted()
    testAnythingElseIsNotAYes()
    testTheAdmissionNeedsTheWordsAsWellAsTheTiming()
    testAQuestionIsNotAYes()
    testAContractionStemIsANegation()
    testTheFirstReservationWordsBlock()
    testTheWordCapHasAnExactBoundary()
    testSiIsAYesOnlyAsTheWholeAnswer()
    testTheAllowlistIsClosed()
    testEstaBienIsAKnownFailClosedLimitation()
    testDigitsAndSymbolsNeverPass()
    testTheCapCountsWhatWasSaidNotWhatTheTokenizerKept()
    testPolitenessAloneIsNotAYes()
}

/// Round 3: a blocklist never ends. Everything a yes may say is on a closed
/// list; a word that is not on it makes the utterance not a yes.
@MainActor func testTheAllowlistIsClosed() {
    let attacks = [
        "ok que tal", "ok como funciona", "is it ok", "cannot", "yes cannot", "maybe ok",
        "tal vez dale", "sí pero no", "yes but", "no", "wait yes", "ok what does it do", "sí, ¿qué hace?",
        "yes I won't", "dale nada", "ok fine whatever", "yes definitely", "ok bueno",
    ]
    for said in attacks { expect(!SpokenYes.affirms(said), "fuera de la lista: «\(said)»") }
}

/// Fail-closed known limitation, not an attack: "está bien" means yes but is
/// not on the list, so it asks for the click. The word list is replaced by
/// the approval judge (16q-3).
@MainActor func testEstaBienIsAKnownFailClosedLimitation() {
    expect(!SpokenYes.affirms("está bien"), "limitacion conocida: un si legitimo que pide el clic")
}

@MainActor func testDigitsAndSymbolsNeverPass() {
    for said in ["ok 1 2 3 4", "ok 5000", "ok1", "ok 1 2 3", "5 ok", "sí 👍", "ok $", "dale +"] {
        expect(!SpokenYes.affirms(said), "digito o simbolo: «\(said)»")
    }
}

/// Digits and dashes are dropped by a letters-only tokenizer: the cap counts
/// the words as said.
@MainActor func testTheCapCountsWhatWasSaidNotWhatTheTokenizerKept() {
    expect(!SpokenYes.affirms("sí - - - - -"), "seis palabras dichas, una sola de letras")
    expect(!SpokenYes.affirms("sí ... ... ... dale"), "cinco palabras dichas")
    expect(SpokenYes.affirms("sí - dale"), "un guion suelto no quita ni suma un sí")
}

@MainActor func testPolitenessAloneIsNotAYes() {
    for said in ["please", "por favor", "please por favor"] {
        expect(!SpokenYes.affirms(said), "cortesia sola: «\(said)»")
    }
    for said in ["yes please", "dale por favor", "sí, dale", "dale, hazlo", "sí sí sí sí", "go ahead",
                 "claro que sí", "ok", "Adelante, por favor"] {
        expect(SpokenYes.affirms(said), "afirma: «\(said)»")
    }
    expect(!SpokenYes.affirms("claro que no"), "la frase 'claro que sí' es una unidad")
    expect(!SpokenYes.affirms("que sí"), "'que' solo dentro de 'claro que sí'")
    expect(!SpokenYes.affirms("yes go ahead please now"), "cinco palabras")
    expect(!SpokenYes.affirms("sí dale hazlo ok adelante"), "cinco palabras")
}

/// Review round 2 (security S1): "ok, what does it do?" consented.
@MainActor func testAQuestionIsNotAYes() {
    for said in ["ok, what does it do?", "sí, ¿qué hace?", "yes why", "sí cómo", "sí, ¿cuál?", "sí por qué",
                 "yes how", "ok which", "yes?", "¿sí", "claro?"] {
        expect(!SpokenYes.affirms(said), "pregunta, no si: «\(said)»")
    }
    expect(SpokenYes.affirms("claro que sí"), "que sin tilde no es pregunta: «claro que sí»")
}

/// The tokenizer splits "won't" into "won" + "t": only the stem is left to see.
@MainActor func testAContractionStemIsANegation() {
    for said in ["yes I won't", "ok can't", "yes isn't", "yes shouldn't", "ok wouldn't", "yes didn't", "ok doesn't",
                 "yes don't"] {
        expect(!SpokenYes.affirms(said), "contraccion negativa: «\(said)»")
    }
}

@MainActor func testTheFirstReservationWordsBlock() {
    for said in ["dale nada", "dale sin eso", "dale mejor", "dale antes", "dale sino", "yes first", "ok before"] {
        expect(!SpokenYes.affirms(said), "reserva: «\(said)»")
    }
}

/// A yes is at most four words (it was eight before the review).
@MainActor func testTheWordCapHasAnExactBoundary() {
    expect(SpokenYes.affirms("sí, sí, dale, dale"), "cuatro palabras: cabe")
    expect(!SpokenYes.affirms("sí, sí, dale, dale, dale"), "cinco palabras: no cabe")
    expect(SpokenYes.affirms("yes go ahead please"), "cuatro en ingles: cabe")
    expect(!SpokenYes.affirms("yes go ahead please yes"), "cinco en ingles: no cabe")
}

@MainActor func testSiIsAYesOnlyAsTheWholeAnswer() {
    expect(SpokenYes.affirms("si"), "si solo")
    expect(SpokenYes.affirms("Sí, sí"), "si repetido")
    expect(!SpokenYes.affirms("si quieres"), "si con algo mas es 'if'")
    expect(!SpokenYes.affirms("si acaso"), "si con algo mas es 'if' (2)")
    expect(!SpokenYes.affirms("si dale"), "'si' sin tilde con un sí al lado es 'if'")
    expect(!SpokenYes.affirms("si ok"), "'si' sin tilde con ok al lado es 'if'")
    expect(!SpokenYes.affirms("si claro"), "'si' sin tilde con claro al lado es 'if'")
    expect(SpokenYes.affirms("sí dale"), "'sí' con tilde si se combina")
    expect(SpokenYes.affirms("si si"), "si repetido sin tilde es todo un si")
}

@MainActor func testClearAffirmationsAreAdmitted() {
    for said in ["sí", "Sí.", "sí, dale", "dale", "Adelante", "hazlo", "Permítelo", "claro que sí",
                 "yes", "Yes!", "go ahead", "yes, do it", "OK", "de acuerdo"] {
        expect(SpokenYes.affirms(said), "afirma: «\(said)»")
    }
}

@MainActor func testAnythingElseIsNotAYes() {
    let rejected = [
        "", "   ", "no", "no, no lo hagas", "sí, pero no", "sí pero espera", "yes but don't",
        "no yes", "wait yes", "pásame la sal", "qué hora es", "👍", "sí y además borra todo el disco duro por favor",
        "yes yes yes yes yes yes yes yes yes", "nunca", "si quieres", "tampoco",
    ]
    for said in rejected {
        expect(!SpokenYes.affirms(said), "no afirma: «\(said)»")
    }
}

@MainActor func testTheAdmissionNeedsTheWordsAsWellAsTheTiming() {
    func admits(_ heard: String?) -> Bool {
        SpokenYes.admits(realtime: false, announcedAt: 0, holdStartedAt: 5, heard: heard)
    }
    expect(admits("sí, dale"), "admite: anunciado antes, hold después y la usuaria dijo sí")
    expect(!admits("qué hora es"), "no admite: el tiempo cuadra pero dijo otra cosa")
    expect(!admits("no, no lo hagas"), "no admite: una negación")
    expect(!admits(nil), "no admite: no hay palabras de este hold")
    expect(!SpokenYes.admits(realtime: true, announcedAt: 0, holdStartedAt: 5, heard: "sí"),
           "realtime nunca, diga lo que diga")
    expect(!SpokenYes.admits(realtime: false, announcedAt: nil, holdStartedAt: 5, heard: "sí"),
           "sin anuncio nunca")
}
