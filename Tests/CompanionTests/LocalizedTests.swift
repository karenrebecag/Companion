import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// El catálogo de la UI. Media app en cada idioma es peor que una monolingüe:
// una clave sin traducir es un fallo de la suite, no un aviso.

@Test @MainActor func localizedTests() {
    testBothCatalogsCoverTheSameKeys()
    testLookupFollowsTheChosenLanguage()
    testCopyLayerGoesThroughTheCatalog()
}

@MainActor func testBothCatalogsCoverTheSameKeys() {
    let english = catalogKeys("en")
    let spanish = catalogKeys("es")
    expect(!english.isEmpty, "catálogo: la fuente inglesa existe y no va vacía")
    expectEq(english.subtracting(spanish), [],
             "catálogo: no hay clave inglesa sin español")
    expectEq(spanish.subtracting(english), [],
             "catálogo: no hay español huérfano de una clave fuente")
}

@MainActor func testLookupFollowsTheChosenLanguage() {
    let saved = Localized.language
    defer { Localized.language = saved }

    Localized.language = { .en }
    let english = Localized.string("chat.job.done")
    Localized.language = { .es }
    let spanish = Localized.string("chat.job.done")

    expect(!english.isEmpty && !spanish.isEmpty,
           "lookup: ninguna de las dos queda vacía")
    expect(english != spanish, "lookup: cada idioma dice lo suyo")
    expect(!english.contains("chat.job.done"),
           "lookup: nunca se pinta la clave cruda en pantalla")
}

/// La capa de copy sigue siendo la API; lo que cambia es de dónde saca el
/// texto. Si un Copy devolviera la clave, el catálogo estaría desconectado.
@MainActor func testCopyLayerGoesThroughTheCatalog() {
    let saved = Localized.language
    defer { Localized.language = saved }

    Localized.language = { .en }
    expect(!ChatCopy.jobDone.contains("."),
           "copy: ChatCopy.jobDone es texto, no una clave")
    expect(!VoiceCopy.failure(.micDenied).contains("voice."),
           "copy: VoiceCopy también pasa por el catálogo")
    let englishDone = ChatCopy.jobDone
    Localized.language = { .es }
    expect(ChatCopy.jobDone != englishDone,
           "copy: cambiar el idioma cambia lo que se pinta")
}

private func catalogKeys(_ language: String) -> Set<String> {
    guard let path = Bundle.module.path(
        forResource: language, ofType: "lproj"),
        let file = try? String(
            contentsOfFile: path + "/Localizable.strings", encoding: .utf8)
    else { return [] }
    var keys: Set<String> = []
    for line in file.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\"") else { continue }
        let parts = trimmed.dropFirst().split(
            separator: "\"", maxSplits: 1, omittingEmptySubsequences: false)
        if let key = parts.first { keys.insert(String(key)) }
    }
    return keys
}
