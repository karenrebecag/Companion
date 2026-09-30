import CompanionCore
import Foundation

/// The sidebar's pages (Wave 16g). The raw value is an identifier: the island
/// and the menus name a page with it, so it never follows the language.
package enum SettingsTab: String, CaseIterable, Equatable {
    case general, voice, vocabulary, memory
    case you, privacy, system

    package var title: String {
        Localized.string("settings.tab.\(rawValue)")
    }

    package var symbol: String {
        switch self {
        case .general: "gearshape"
        case .voice: "waveform"
        case .vocabulary: "textformat.abc"
        case .memory: "brain"
        case .you: "person.crop.circle"
        case .privacy: "lock.shield"
        case .system: "info.circle"
        }
    }

    /// Where the sidebar draws its gap: what it does above, whose it is below.
    package static let firstGroup: [SettingsTab] = [.general, .voice, .vocabulary, .memory]
    package static let secondGroup: [SettingsTab] = [.you, .privacy, .system]
}

/// What Settings shows (Wave 16d), declared once so a test can hold the line
/// at fifteen: an option changes a preference; a panel shows a status or
/// runs an action (permissions, keys, updates, memory) and is not an option.
package enum SettingsInventory {
    package struct Option: Sendable, Equatable {
        package let tab: SettingsTab
        package let titleKey: String
        package let subtitleKey: String?
    }

    package struct Panel: Sendable, Equatable {
        package let tab: SettingsTab
        package let titleKey: String
    }

    package static let options: [Option] = [
        Option(tab: .general, titleKey: "settings.app.talk.hold", subtitleKey: "settings.app.talk.hold.subtitle"),
        Option(tab: .general, titleKey: "settings.app.talk.dictationKey",
               subtitleKey: "settings.app.talk.dictationKey.subtitle"),
        Option(tab: .general, titleKey: "settings.app.language", subtitleKey: "settings.app.language.subtitle"),
        Option(tab: .general, titleKey: "settings.sounds", subtitleKey: "settings.sounds.subtitle"),
        Option(tab: .general, titleKey: "settings.screenGlow", subtitleKey: "settings.screenGlow.subtitle"),
        Option(tab: .voice, titleKey: "settings.voice.voice", subtitleKey: "settings.voice.blurb"),
        Option(tab: .vocabulary, titleKey: "settings.vocabulary", subtitleKey: "settings.vocabulary.subtitle"),
        Option(tab: .you, titleKey: "settings.you.name", subtitleKey: nil),
        Option(tab: .you, titleKey: "settings.you.photo", subtitleKey: "settings.you.photo.subtitle"),
        Option(tab: .you, titleKey: "settings.you.city", subtitleKey: "settings.you.city.subtitle"),
        Option(tab: .you, titleKey: "settings.you.about", subtitleKey: nil),
        Option(tab: .you, titleKey: "settings.you.instructions", subtitleKey: nil),
        Option(tab: .you, titleKey: "settings.app.appearance", subtitleKey: nil),
        Option(tab: .you, titleKey: "settings.app.textSize", subtitleKey: "settings.app.textSize.subtitle"),
        Option(tab: .privacy, titleKey: "settings.context.screen", subtitleKey: "settings.context.screen.subtitle"),
        Option(tab: .privacy, titleKey: "settings.context.documents",
               subtitleKey: "settings.context.documents.subtitle"),
        Option(tab: .privacy, titleKey: "settings.context.location",
               subtitleKey: "settings.context.location.subtitle"),
        Option(tab: .privacy, titleKey: "settings.privacy.lendHands",
               subtitleKey: "settings.privacy.lendHands.subtitle"),
    ]

    package static let panels: [Panel] = [
        Panel(tab: .memory, titleKey: "settings.memory.header"),
        Panel(tab: .privacy, titleKey: "settings.permissions"),
        Panel(tab: .privacy, titleKey: "settings.keys.header"),
        Panel(tab: .privacy, titleKey: "settings.browser.header"),
        Panel(tab: .system, titleKey: "settings.app.version"),
        Panel(tab: .system, titleKey: "settings.app.attachments"),
        Panel(tab: .system, titleKey: "settings.welcome.again"),
    ]

    package static var panelKeys: [String] { panels.map(\.titleKey) }

    /// Every label a user can read in Settings: titles, subtitles, panels, pages.
    package static var visibleKeys: [String] {
        options.flatMap { [$0.titleKey, $0.subtitleKey].compactMap { $0 } }
            + panelKeys + SettingsTab.allCases.map { "settings.tab.\($0.rawValue)" }
    }

    /// What the search reads, in the language on screen now. A page's own
    /// name finds the page, so "memoria" lands somewhere even with no row.
    @MainActor package static var searchEntries: [SettingsSearch.Entry] {
        options.map {
            SettingsSearch.Entry(
                id: $0.titleKey, page: $0.tab.rawValue, title: Localized.string($0.titleKey),
                subtitle: $0.subtitleKey.map { Localized.string($0) } ?? $0.tab.title)
        }
        + panels.map {
            SettingsSearch.Entry(
                id: $0.titleKey, page: $0.tab.rawValue, title: Localized.string($0.titleKey),
                subtitle: $0.tab.title)
        }
        + SettingsTab.allCases.map {
            SettingsSearch.Entry(id: "settings.tab.\($0.rawValue)", page: $0.rawValue, title: $0.title, subtitle: "")
        }
    }
}
