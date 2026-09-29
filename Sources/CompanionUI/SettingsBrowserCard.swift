import CompanionCore
import SwiftUI

/// Settings › Privacidad › Navegador (Wave 18-4b): the link between Companion
/// and the browser extension. Connecting writes the native host manifest;
/// the user still loads the extension folder once, so its path and id are shown.
struct SettingsBrowserCard: View {
    var model: BrowserSettingsModel

    var body: some View {
        SettingsCard(label: Localized.string("settings.browser.header")) {
            VStack(alignment: .leading, spacing: Space.x3) {
                Text(Localized.string("settings.browser.blurb"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.statusText)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                if let notice = model.noticeText {
                    Text(notice)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                detail(Localized.string("settings.browser.id"), model.extensionID)
                if let folder = model.extensionFolder {
                    detail(Localized.string("settings.browser.folder"), folder)
                }
            }
            .padding(Space.x4)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(label).font(.uiCaption).foregroundStyle(Semantic.mutedForeground)
            Text(value)
                .font(.uiCaption.monospaced())
                .foregroundStyle(Semantic.foreground)
                .textSelection(.enabled)
        }
    }
}
