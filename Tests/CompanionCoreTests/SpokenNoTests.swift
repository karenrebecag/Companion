import CompanionCore
import Foundation
import Testing

// classic-spoken-yes-parent-sheet D3: an explicit "no" to a parent sheet
// refuses it with a line of its own. Refusing is the safe direction, but a
// "no" still settles the sheet without a click, so it is judged as narrowly
// as a yes: a closed es/en list, short, no question.

@Suite struct SpokenNoAnswers {
    @Test(arguments: [
        "no", "No.", "no gracias", "mejor no", "no, por favor", "nope", "no thanks",
        "no lo hagas", "nah", "negativo", "cancela", "no, thank you",
        "nop", "nel", "cancelalo", "niegalo", "no please",
        // Spelled right, the clitic imperatives carry an accent; case never matters.
        "Cancélalo", "Niégalo", "¡Cancélalo!", "NO", "NEGATIVO",
        "no!", "no...", "¡no!", "no, no", "no - gracias",
        // Four words still fit.
        "no, no lo hagas", "no por favor gracias", "no no no no",
    ])
    func aClearNoRefuses(_ said: String) {
        #expect(SpokenNo.refuses(said), "«\(said)» is a no")
    }

    @Test(arguments: [
        // A question, a hedge, a mix, a number, a paragraph: none is a no.
        "no sé", "¿no?", "no?", "sí pero no", "no, mejor sí", "no no no no no",
        "no abras eso y busca vuelos", "no 2", "", "   ", "gracias", "por favor", "mejor",
        "sí", "dale", "de acuerdo", "no problem", "nada", "thanks", "thank you",
        "no ... ... ... gracias",
        // Fail closed on purpose: phrasings the list does not carry are no
        // answer, so adding one is a decision, not an accident.
        "claro que no", "don't do it", "denegado", "nunca", "jamás",
    ])
    func anythingElseIsNotARefusal(_ said: String) {
        #expect(!SpokenNo.refuses(said), "«\(said)» is not a no")
    }

    @Test func aYesIsNeverAlsoANo() {
        for said in ["sí", "dale", "claro que sí", "yes please", "go ahead", "vale"] {
            #expect(SpokenYes.affirms(said) && !SpokenNo.refuses(said), "«\(said)»")
        }
    }

    @Test func theRefusalLineIsRealTranslatedAndItsOwn() {
        for language in [AppLanguage.es, .en] {
            let line = Escalation.approvalRefusedSpoken(language)
            #expect(!line.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(line != Escalation.approvalNeedsClickSpoken(language))
            #expect(line != Escalation.approvalAskedSpoken(language))
        }
        #expect(Escalation.approvalRefusedSpoken(.es) != Escalation.approvalRefusedSpoken(.en))
    }
}
