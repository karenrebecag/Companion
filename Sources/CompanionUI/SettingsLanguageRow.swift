import CompanionCore
import SwiftUI

/// The language row and its choices. Split out of SettingsAppPane at the
/// 400-line gate; it is also the only control that has to repaint the whole
/// pane, which is easier to see on its own.
extension SettingsAppPane {
    var languageRow: some View {
        SettingsLine(
            title: Localized.string("settings.app.language"),
            subtitle: Localized.string("settings.app.language.subtitle")
        ) {
            SettingsItem(
                title: "",
                value: LanguageChoice.current.label,
                options: LanguageChoice.allCases.map { ($0, $0.label) }
            ) { choice in
                LanguagePreference.stored = choice.language
                // The screen is already full of resolved strings; the tick is
                // what repaints all of them at once.
                languageTick += 1
            }
        }
    }

    /// System, English or Spanish. "System" is not the same as English: it
    /// means follow the Mac, and it has to survive changing the Mac's setting.
    enum LanguageChoice: String, CaseIterable, Hashable {
        case system, en, es

        static var current: LanguageChoice {
            LanguagePreference.stored.map {
                LanguageChoice(rawValue: $0.rawValue) ?? .system
            } ?? .system
        }

        var language: AppLanguage? {
            self == .system ? nil : AppLanguage(rawValue: rawValue)
        }

        var label: String {
            Localized.string("settings.app.language.\(rawValue)")
        }
    }
}
