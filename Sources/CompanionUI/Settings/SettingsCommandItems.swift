import CompanionCore
import CompanionUIPro

extension SettingsInventory {
    /// What the settings palette can jump to: every option and panel row, and
    /// each page by its own name, so "memoria" lands on Memory with no row.
    @MainActor package static var commandItems: [SettingsCommandItem] {
        options.map {
            SettingsCommandItem(
                id: $0.titleKey, sectionID: $0.tab.rawValue, title: Localized.string($0.titleKey),
                subtitle: $0.subtitleKey.map { Localized.string($0) } ?? $0.tab.title)
        }
        + panels.map {
            SettingsCommandItem(
                id: $0.rowId ?? $0.titleKey, sectionID: $0.tab.rawValue, title: Localized.string($0.titleKey),
                subtitle: $0.tab.title, keywords: $0.keywords)
        }
        + SettingsTab.allCases.map {
            SettingsCommandItem(id: "settings.tab.\($0.rawValue)", sectionID: $0.rawValue, title: $0.title)
        }
    }
}
