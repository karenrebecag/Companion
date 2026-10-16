import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func cardVocabularyTests() {
    testBothPromptsTeachTheSameSyntax()
    testTheVocabularyLivesInExactlyOnePlace()
    testItWarnsAgainstInventingCoordinates()
    testItTravelsInBothLanguages()
    testItAsksForTheChoiceCardWhenOfferingOptions()
}

@MainActor func testBothPromptsTeachTheSameSyntax() {
    // El renderizador estaba cableado de punta a punta y solo el especialista
    // sabia pedirle algo. Preguntar por un lugar sin delegar no podia pintar
    // un mapa aunque el mapa estuviera ahi.
    for language in [AppLanguage.en, .es] {
        let chat = ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: true, language: language)
        let specialist = Escalation.executorRole(language)
        for prompt in [chat, specialist] {
            expect(prompt.contains(CompanionBlocks.locationsLanguage),
                   "\(language): el prompt enseña las tarjetas de lugares")
            expect(prompt.contains(CompanionBlocks.galleryLanguage),
                   "\(language): y las de galería")
        }
    }
}

@MainActor func testTheVocabularyLivesInExactlyOnePlace() {
    // Copiar la descripcion a los dos prompts crearia dos fuentes de verdad
    // que se separan al primer cambio de forma del JSON.
    for language in [AppLanguage.en, .es] {
        let vocabulary = CardVocabulary.text(language)
        expect(ChatPrompt.system(
            ownerFirstName: "", delegateEnabled: true, language: language)
            .contains(vocabulary),
            "\(language): la charla usa el vocabulario compartido, no una copia")
        expect(Escalation.executorRole(language).contains(vocabulary),
               "\(language): y el especialista tambien")
    }
}

@MainActor func testItWarnsAgainstInventingCoordinates() {
    // Validamos que lat/lng esten en rango, lo que atrapa el disparate pero
    // no el error plausible: un pin en el sitio equivocado pasa la validacion.
    for language in [AppLanguage.en, .es] {
        let text = CardVocabulary.text(language).lowercased()
        expect(text.contains("invent") || text.contains("inventes"),
               "\(language): dice explicitamente que no se inventen coordenadas")
    }
}

@MainActor func testItTravelsInBothLanguages() {
    expect(!CardVocabulary.text(.en).contains("tarjeta"),
           "el vocabulario en inglés no arrastra español")
    expect(CardVocabulary.text(.es).contains("tarjeta"),
           "y el español está escrito, no traducido a medias")
}

@MainActor func testItAsksForTheChoiceCardWhenOfferingOptions() {
    // QA en vivo 2026-10-16: «dame 3 opciones para elegir con un clic»
    // devolvio una lista numerada aunque la tarjeta ya existia.
    for language in [AppLanguage.en, .es] {
        let chat = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: language)
        expect(chat.contains(CompanionBlocks.choiceLanguage),
               "\(language): la charla conoce la tarjeta de opciones")
        let rule = language == .en ? "instead of the list" : "en lugar de la lista"
        expect(chat.contains(rule), "\(language): pide la tarjeta y no la lista numerada")
        expect(chat.contains("```math"), "\(language): las formulas van en Unicode dentro de un bloque math")
    }
}
