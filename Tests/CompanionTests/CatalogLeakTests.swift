import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// 16p-1: labels that used to live as Spanish literals in code. The catalog
// gate does not see switch statements, so this suite is the guard.

@Test @MainActor func catalogLeakTests() async {
    for language in [AppLanguage.en, .es] {
        await Localized.scoped(to: language) {
            expectLabelsResolve(language)
        }
    }
    await testLabelsMapToTheRightWords()
    await testLeakedLabelsDifferPerLanguage()
    await testOpeningVerbFollowsRequestedLanguage()
}

@MainActor private func expectLabelsResolve(_ language: AppLanguage) {
    let labels = Highlight.allCases.map(\.label)
        + ShortcutAction.allCases.map(\.label)
        + AppearancePreference.allCases.map(\.label)
    for label in labels {
        expect(!label.isEmpty, "i18n \(language.rawValue): ningún label queda vacío")
        expect(!label.contains("."),
               "i18n \(language.rawValue): '\(label)' no es una clave cruda")
    }
}

@MainActor private func testLeakedLabelsDifferPerLanguage() async {
    func labels() -> [String] {
        Highlight.allCases.map(\.label)
            + ShortcutAction.allCases.map(\.label)
            + AppearancePreference.allCases.map(\.label)
    }
    let english = await Localized.scoped(to: .en) { labels() }
    let spanish = await Localized.scoped(to: .es) { labels() }
    expectEq(english.count, spanish.count, "i18n: mismos labels en ambos idiomas")
    for (en, es) in zip(english, spanish) {
        expect(en != es, "i18n: '\(es)' sigue igual en inglés, está fijo en código")
    }
}

@MainActor private func testOpeningVerbFollowsRequestedLanguage() async {
    expectEq(ReferentLine.parts(["Safari"], language: .en).verb, "Opening",
             "i18n: verbo en inglés desde el catálogo")
    expectEq(ReferentLine.parts(["Safari"], language: .es).verb, "Abriendo",
             "i18n: verbo en español desde el catálogo")
}

/// Not empty is not enough: swapping two keys would still pass.
@MainActor private func testLabelsMapToTheRightWords() async {
    let es: [String: String] = [
        "standard": "Predeterminado", "blue": "Azul", "green": "Verde", "yellow": "Amarillo",
        "pink": "Rosa", "orange": "Naranja", "purple": "Morado", "white": "Blanco",
        "light": "Claro", "dark": "Oscuro", "auto": "Sistema",
        "toggleVoice": "Iniciar/terminar turno", "hangUp": "Terminar llamada",
        "settings": "Abrir ajustes", "attach": "Adjuntar archivos", "history": "Ver conversaciones"]
    let en: [String: String] = [
        "standard": "Default", "blue": "Blue", "green": "Green", "yellow": "Yellow",
        "pink": "Pink", "orange": "Orange", "purple": "Purple", "white": "White",
        "light": "Light", "dark": "Dark", "auto": "System",
        "toggleVoice": "Start/end turn", "hangUp": "Hang up",
        "settings": "Open settings", "attach": "Attach files", "history": "View conversations"]
    for (language, want) in [(AppLanguage.es, es), (.en, en)] {
        await Localized.scoped(to: language) {
            var got: [String: String] = [:]
            for h in Highlight.allCases where want[h.rawValue] != nil { got[h.rawValue] = h.label }
            for a in AppearancePreference.allCases { got[a.rawValue] = a.label }
            for a in ShortcutAction.allCases where want[a.rawValue] != nil { got[a.rawValue] = a.label }
            expectEq(got, want, "i18n \(language.rawValue): cada label dice lo suyo")
        }
    }
}
