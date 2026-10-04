import CompanionCore
import Foundation

/// What the Speaking row says about Automatic. Kept apart from the view so
/// the resolved language it names is the one the mouths will actually use.
enum SpeechLanguageCopy {
    static func resolvedName(dictation: [String], interface: AppLanguage) -> String {
        let code = SpokenLanguagePreference.resolvedSpeechCode(
            dictation: dictation, speech: SpokenLanguagePreference.automatic,
            interface: interface)
        return Localized.string("spoken.language.\(code)")
    }

    static func autoLabel(dictation: [String], interface: AppLanguage) -> String {
        String(
            format: Localized.string("settings.speech.language.auto"),
            resolvedName(dictation: dictation, interface: interface))
    }

    static func pill(choice: String, dictation: [String], interface: AppLanguage) -> String {
        if choice == SpokenLanguagePreference.automatic {
            return autoLabel(dictation: dictation, interface: interface)
        }
        return Localized.string("spoken.language.\(choice)")
    }

    static func subtitle(choice: String, dictation: [String], interface: AppLanguage) -> String {
        guard choice == SpokenLanguagePreference.automatic else {
            return Localized.string("settings.speech.language.subtitle")
        }
        if let first = dictation.first {
            return String(
                format: Localized.string("settings.speech.language.auto.same"),
                Localized.string("spoken.language.\(first)"))
        }
        return Localized.string("settings.speech.language.auto.until")
    }
}
