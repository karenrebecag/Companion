import CompanionCore
import CompanionUIPro
import SwiftUI

// Companion's words and tokens for the Arc Pro settings components. The
// components never see a Companion type; this file is the only place the two meet.

extension SettingsTab {
    /// The section the page nav shows for this tab.
    var pageSection: SettingsPageSection {
        SettingsPageSection(id: rawValue, title: title, description: pageBlurb, symbol: symbol)
    }

    private var pageBlurb: String {
        switch self {
        case .general: Localized.string("settings.general.blurb")
        case .voice: Localized.string("settings.voice.blurb")
        case .vocabulary: Localized.string("settings.vocabulary.subtitle")
        case .memory: Localized.string("settings.memory.blurb")
        case .you: Localized.string("settings.you.blurb")
        case .privacy: Localized.string("settings.privacy.blurb")
        case .system: Localized.string("settings.system.blurb")
        }
    }
}

@MainActor
enum SettingsPageChrome {
    static var pageStrings: SettingsPageStrings {
        // The closure below runs off the main actor, so the format is read here.
        let unsavedFormat = Localized.string("settings.bar.unsaved")
        return SettingsPageStrings(
            navLabel: Localized.string("settings.nav.label"),
            save: Localized.string("settings.bar.save"),
            saving: Localized.string("settings.bar.saving"),
            saved: Localized.string("settings.bar.saved"),
            discard: Localized.string("settings.bar.discard"),
            unsaved: { String(format: unsavedFormat, $0) })
    }

    static var avatarStrings: AvatarUploadStrings {
        AvatarUploadStrings(
            title: Localized.string("settings.you.photo"),
            choose: Localized.string("settings.avatar.choose"),
            remove: Localized.string("settings.avatar.remove"),
            drop: Localized.string("settings.avatar.drop"),
            zoom: Localized.string("settings.avatar.zoom"),
            cancel: Localized.string("settings.avatar.cancel"),
            done: Localized.string("settings.avatar.done"),
            typeError: Localized.string("settings.avatar.typeError"),
            sizeError: Localized.string("settings.avatar.sizeError"),
            unreadable: Localized.string("settings.avatar.unreadable"),
            saveFailed: Localized.string("settings.avatar.saveFailed"))
    }

    static var commandStrings: SettingsCommandStrings {
        let noneFormat = Localized.string("settings.search.none")
        return SettingsCommandStrings(
            placeholder: Localized.string("settings.search.placeholder"),
            noResults: { String(format: noneFormat, $0) })
    }
}
