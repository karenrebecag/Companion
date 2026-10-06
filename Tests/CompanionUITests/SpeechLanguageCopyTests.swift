import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// El idioma al hablar en automático nombra lo que de verdad se va a usar:
// el primer idioma de dictado, o el de la interfaz mientras no haya ninguno.

@Test @MainActor func speechLanguageAutomaticNamesTheResolvedLanguage() async {
    await Localized.scoped(to: .es) {
        expectEq(SpeechLanguageCopy.autoLabel(dictation: [], interface: .es),
                 "Automático · Español",
                 "automático es: sin dictado nombra el idioma de la app")
        expectEq(SpeechLanguageCopy.autoLabel(dictation: [], interface: .en),
                 "Automático · Inglés",
                 "automático es: la interfaz en inglés nombra Inglés")
        expectEq(SpeechLanguageCopy.autoLabel(dictation: ["fr", "de"], interface: .es),
                 "Automático · Francés",
                 "automático es: con dictado nombra el primero")
        expectEq(SpeechLanguageCopy.subtitle(choice: "auto", dictation: [], interface: .es),
                 "El idioma de la app hasta que elijas un idioma de dictado.",
                 "subtítulo es: sin dictado dice que es el idioma de la app")
    }
    await Localized.scoped(to: .en) {
        expectEq(SpeechLanguageCopy.autoLabel(dictation: [], interface: .en),
                 "Automatic · English",
                 "automático en: sin dictado nombra el idioma de la app")
        expectEq(SpeechLanguageCopy.subtitle(choice: "auto", dictation: [], interface: .en),
                 "The app language until you pick a dictation language.",
                 "subtítulo en: sin dictado dice que es el idioma de la app")
        expectEq(SpeechLanguageCopy.subtitle(choice: "auto", dictation: ["fr"], interface: .en),
                 "Same as your dictation language, French.",
                 "subtítulo en: con dictado sigue al primero")
        expectEq(SpeechLanguageCopy.pill(choice: "de", dictation: [], interface: .en),
                 "German", "pastilla en: un idioma elegido se nombra solo")
    }
}

// El dictado y el habla dicen lo que de verdad pasa: con la tecla pulsada el
// oído del dispositivo escucha un idioma a la vez; el manos libres los oye todos.

@Test @MainActor func dictationAndSpeakingSubtitlesAreHonestAboutTheHold() async {
    await Localized.scoped(to: .en) {
        expectEq(Localized.string("settings.dictation.language.subtitle"),
                 "So Companion understands you in any of them. When you hold the key it listens "
                     + "in the first one you pick; hands-free listens for all of them.",
                 "dictado en: la tecla pulsada escucha el primero, manos libres todos")
        expectEq(SpeechLanguageCopy.subtitle(choice: "fr", dictation: [], interface: .en),
                 "The language Companion speaks to you in when you hold the key. "
                     + "Hands-free follows the app language.",
                 "habla en: aplica a la tecla pulsada, manos libres sigue la app")
    }
    await Localized.scoped(to: .es) {
        expectEq(Localized.string("settings.dictation.language.subtitle"),
                 "Para que Companion te entienda en cualquiera de ellos. Al mantener pulsada la "
                     + "tecla escucha en el primero que elijas; el manos libres escucha en todos.",
                 "dictado es: la tecla pulsada escucha el primero, manos libres todos")
        expectEq(SpeechLanguageCopy.subtitle(choice: "fr", dictation: [], interface: .es),
                 "El idioma en el que Companion te habla cuando mantienes pulsada la tecla. "
                     + "El manos libres sigue el idioma de la app.",
                 "habla es: aplica a la tecla pulsada, manos libres sigue la app")
    }
}

// Con nada elegido, el hold escucha en el idioma de la app; solo el manos
// libres detecta el idioma solo.

@Test @MainActor func dictationEmptyStateIsHonestAboutTheHold() async {
    await Localized.scoped(to: .en) {
        expectEq(Localized.string("settings.dictation.language.auto"),
                 "App language until you pick one",
                 "dictado en: la pastilla vacía dice que el hold usa el idioma de la app")
        expectEq(Localized.string("settings.dictation.language.empty"),
                 "Nothing picked. Holding the key listens in the app language; hands-free "
                     + "detects the language as you speak.",
                 "dictado en: el estado vacío separa hold y manos libres")
    }
    await Localized.scoped(to: .es) {
        expectEq(Localized.string("settings.dictation.language.auto"),
                 "Idioma de la app hasta que elijas uno",
                 "dictado es: la pastilla vacía dice que el hold usa el idioma de la app")
        expectEq(Localized.string("settings.dictation.language.empty"),
                 "Nada elegido. Al mantener la tecla escucha en el idioma de la app; el manos "
                     + "libres detecta el idioma mientras hablas.",
                 "dictado es: el estado vacío separa hold y manos libres")
    }
}
