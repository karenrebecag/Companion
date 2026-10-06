import CompanionCore
import Foundation

/// The sidebar's pages (Wave 16g). The raw value is an identifier: the island
/// and the menus name a page with it, so it never follows the language.
package enum SettingsTab: String, CaseIterable, Equatable {
    case general, voice, vocabulary, memory, system
    case you, privacy

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

    /// Incredible's map (S2 of ajustes-hoja-incredible): the app above, the account below.
    package static let firstGroup: [SettingsTab] = [.general, .voice, .vocabulary, .memory, .system]
    package static let secondGroup: [SettingsTab] = [.you, .privacy]

    /// Ids that older callers, and Incredible's own deep links, use for a page
    /// that has another id here. Pages Companion has no backend for resolve to nil.
    private static let aliases: [String: SettingsTab] = [
        "preferences": .general, "tools": .general, "microphone": .general, "updates": .general,
        "shortcuts": .general, "incredible": .voice, "companion": .voice, "personalization": .you,
        "account": .you, "dictionary": .vocabulary, "permissions": .privacy, "data": .privacy,
    ]

    package static func resolve(_ id: String) -> SettingsTab? {
        SettingsTab(rawValue: id) ?? aliases[id]
    }
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
        /// The row's own id when it is not the title key; search lights it.
        package var rowId: String?
        /// Words the user may type that the title and subtitle do not carry.
        package var keywords: [String] = []
    }

    package static let clearHistoryRowID = "settings-clear-history"

    package static let options: [Option] = [
        Option(tab: .general, titleKey: "settings.app.talk.hold", subtitleKey: "settings.app.talk.hold.subtitle"),
        Option(tab: .general, titleKey: "settings.app.talk.dictationKey",
               subtitleKey: "settings.app.talk.dictationKey.subtitle"),
        Option(tab: .general, titleKey: "settings.app.language", subtitleKey: "settings.app.language.subtitle"),
        Option(tab: .system, titleKey: "settings.screenGlow", subtitleKey: "settings.screenGlow.subtitle"),
        Option(tab: .system, titleKey: "settings.muteWhileTalking",
               subtitleKey: "settings.muteWhileTalking.subtitle"),
        Option(tab: .system, titleKey: "settings.muteEffects", subtitleKey: "settings.muteEffects.subtitle"),
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
        Panel(tab: .system, titleKey: "settings.history.row", rowId: clearHistoryRowID,
              keywords: ["clear", "history", "delete", "erase", "conversations", "chats", "reset", "wipe", "forget"]),
        Panel(tab: .you, titleKey: "settings.welcome.again"),
    ]

    package static var panelKeys: [String] { panels.map(\.titleKey) }

    /// Every label a user can read in Settings: titles, subtitles, panels, pages.
    package static var visibleKeys: [String] {
        options.flatMap { [$0.titleKey, $0.subtitleKey].compactMap { $0 } }
            + panelKeys + SettingsTab.allCases.map { "settings.tab.\($0.rawValue)" }
    }

    /// What the search reads, in the language on screen now. One entry per row
    /// and one per page. Keywords carry the other language and a few synonyms;
    /// the page name stays the weakest match, so "memoria" still lands.
    /// local reference; brief ajustes-hoja-incredible S2
    @MainActor package static var searchEntries: [SettingsSearch.Entry] {
        options.map {
            entry(id: $0.titleKey, titleKey: $0.titleKey, tab: $0.tab, subtitleKey: $0.subtitleKey)
        }
        + panels.map {
            // A panel that carries a `rowId` is the row, not the section header; the
            // id is the row's so search lands on the action it actually performs.
            entry(
                id: $0.rowId ?? $0.titleKey, titleKey: $0.titleKey, tab: $0.tab,
                subtitleKey: nil, extraKeywords: $0.keywords)
        }
        + SettingsTab.allCases.map {
            entry(
                id: "settings.tab.\($0.rawValue)", titleKey: "settings.tab.\($0.rawValue)",
                tab: $0, subtitleKey: nil)
        }
    }

    /// Old names people still type, beside the label in both languages.
    static let extraKeywords: [String: [String]] = [
        "settings.tab.general": ["preferencias", "preferences"],
        "settings.tab.voice": ["voz", "voice"],
        "settings.tab.vocabulary": ["diccionario", "dictionary"],
        "settings.tab.memory": ["recuerdos"],
        "settings.tab.you": ["perfil", "profile"],
        "settings.tab.privacy": ["permisos", "permissions"],
        "settings.app.talk.hold": ["atajo", "shortcut"],
        "settings.app.talk.dictationKey": ["microfono", "microphone"],
    ]

    @MainActor private static func entry(
        id: String, titleKey: String, tab: SettingsTab, subtitleKey: String?,
        extraKeywords: [String] = []
    ) -> SettingsSearch.Entry {
        SettingsSearch.Entry(
            id: id, page: tab.rawValue, title: Localized.string(titleKey),
            subtitle: subtitleKey.map { Localized.string($0) } ?? "",
            keywords: keywords(id: titleKey, subtitleKey: subtitleKey) + extraKeywords,
            pageTitle: tab.title)
    }

    @MainActor private static func keywords(id: String, subtitleKey: String?) -> [String] {
        var lines: [String] = []
        for language in [AppLanguage.es, .en] {
            lines.append(Localized.string(id, language: language))
            if let subtitleKey { lines.append(Localized.string(subtitleKey, language: language)) }
        }
        lines.append(contentsOf: extraKeywords[id] ?? [])
        return lines
    }
}
