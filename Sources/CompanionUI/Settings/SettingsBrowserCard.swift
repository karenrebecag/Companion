import CompanionCore
import CompanionUIPro
import SwiftUI

/// Settings › Privacidad › Navegador (Wave 18-4b): the link between Companion
/// and the browser extension. Connecting writes the native host manifest;
/// the user still loads the extension folder once, so its path and id are shown.
struct SettingsBrowserSection: View {
    var model: BrowserSettingsModel

    var body: some View {
        SecuritySection(
            title: Localized.string("settings.browser.header"),
            description: Localized.string("settings.browser.blurb")
        ) {
            SecurityRow(
                title: model.statusText,
                detail: model.noticeText
            ) {
                HStack(spacing: Space.x2) {
                    SettingsPill(
                        title: Localized.string("settings.browser.connect"), kind: .primary,
                        action: model.connect)
                    if model.status != .notInstalled {
                        SettingsPill(
                            title: Localized.string("settings.browser.remove"), kind: .destructive,
                            action: model.remove)
                    }
                }
            }
            SettingsRow(title: Localized.string("settings.browser.id"), description: model.extensionID) {
                EmptyView()
            }
            if let folder = model.extensionFolder {
                SettingsRow(title: Localized.string("settings.browser.folder"), description: folder) {
                    EmptyView()
                }
            }
        }
    }
}
