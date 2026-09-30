import CompanionCore
import SwiftUI

/// The language row (Wave 16g: in General). The only control that has
/// to repaint the whole sheet, so it reports the change instead of owning a
/// tick of its own.
struct SettingsLanguageLine: View {
    let onChange: () -> Void

    var body: some View {
        SettingsRow(
            title: Localized.string("settings.app.language"),
            subtitle: Localized.string("settings.app.language.subtitle"),
            key: "settings.app.language"
        ) {
            SettingsItem(
                title: "",
                value: SettingsLanguageChoice.current.label,
                options: SettingsLanguageChoice.allCases.map { ($0, $0.label) },
                id: "settings.app.language"
            ) { choice in
                LanguagePreference.stored = choice.language
                onChange()
            }
        }
    }
}

/// System, English or Spanish. "System" is not the same as English: it
/// means follow the Mac, and it has to survive changing the Mac's setting.
enum SettingsLanguageChoice: String, CaseIterable, Hashable {
    case system, en, es

    static var current: SettingsLanguageChoice {
        LanguagePreference.stored.map {
            SettingsLanguageChoice(rawValue: $0.rawValue) ?? .system
        } ?? .system
    }

    var language: AppLanguage? {
        self == .system ? nil : AppLanguage(rawValue: rawValue)
    }

    var label: String {
        Localized.string("settings.app.language.\(rawValue)")
    }
}
