import AppKit
import CompanionCore
import SwiftUI

/// Settings › Privacidad (Wave 16g): what it may look at, the permissions
/// with their live state, and the keys.
struct SettingsPrivacyPage: View {
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    @State private var context = ContextSettingsModel()
    /// Wave 15c-6: reads the Keychain only from `.onAppear`, never at boot.
    @State private var keys = KeysSettingsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.privacy.title)
            SettingsCard(label: Localized.string("settings.context.label")) {
                SettingsRow(
                    title: Localized.string("settings.context.screen"),
                    subtitle: Localized.string("settings.context.screen.subtitle"),
                    key: "settings.context.screen"
                ) {
                    SettingsSwitch(label: Localized.string("settings.context.screen"), isOn: contextBinding(\.screen))
                }
                SettingsRow(title: Localized.string("settings.context.documents"), key: "settings.context.documents") {
                    SettingsSwitch(
                        label: Localized.string("settings.context.documents"), isOn: contextBinding(\.documents))
                }
            }
            if let welcome {
                SettingsCard(label: Localized.string("settings.permissions")) {
                    ForEach(WelcomePermission.allCases, id: \.self) { permission in
                        SettingsPermissionRow(model: PermissionRowModel(
                            kind: permission.rowKind,
                            granted: welcome.facts.granted.contains(permission)))
                    }
                }
            }
            SettingsCard(label: Localized.string("settings.keys.label")) {
                keysBlock.padding(Space.x4)
            }
        }
        .onAppear {
            context.accessibility = chat?.accessibility
            context.screenRecording = chat?.screenRecording
            context.refreshTrust()
            keys.secrets = chat?.secrets
            keys.refresh()
        }
        .task {
            // Rows answer a change made in System Settings while this is open.
            while !Task.isCancelled {
                await welcome?.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private func contextBinding(
        _ keyPath: ReferenceWritableKeyPath<ContextSettingsModel, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { context[keyPath: keyPath] },
            set: { context[keyPath: keyPath] = $0 })
    }

    /// Wave 15c-6: pasted values never surface back — `KeysSettingsModel`
    /// only exposes a saved/not-saved boolean, so this view has nothing to
    /// leak even by accident.
    private var keysBlock: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(Localized.string("settings.keys.blurb"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            keyRow(.openAI, title: "settings.keys.openai",
                   placeholder: "settings.keys.openai.placeholder", text: $keys.openAIField)
            keyRow(.cerebras, title: "settings.keys.cerebras",
                   placeholder: "settings.keys.cerebras.placeholder", text: $keys.cerebrasField)
            Text(Localized.string("settings.keys.cerebras.privacy"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            keyRow(.elevenLabs, title: "settings.keys.elevenlabs",
                   placeholder: "settings.keys.elevenlabs.placeholder",
                   text: $keys.elevenLabsField)
            Text(Localized.string("settings.keys.elevenlabs.privacy"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let error = keys.errorText {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
            }
        }
    }

    /// 15c-7: the saved key reads as its mask next to a check, so a blank
    /// field no longer looks like nothing happened; delete is quiet because
    /// it is the one action here that cannot be undone from this screen.
    private func keyRow(
        _ provider: KeysSettingsModel.Provider, title: String, placeholder: String,
        text: Binding<String>
    ) -> some View {
        let mask = keys.masked[provider]
        let hasInput = !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: Space.x2) {
            HStack(spacing: Space.x2) {
                Text(Localized.string(title))
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                if let mask {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Semantic.accentText)
                        .accessibilityHidden(true)
                    Text(mask)
                        .font(.uiCaption.monospaced())
                        .foregroundStyle(Semantic.foreground)
                        .accessibilityLabel(String(
                            format: Localized.string("settings.keys.saved.label"), mask))
                }
                Spacer()
            }
            HStack(spacing: Space.x2) {
                AppField(
                    placeholder: Localized.string(
                        mask == nil ? placeholder : "settings.keys.replace.placeholder"),
                    text: text, secure: true)
                SettingsPill(
                    title: Localized.string("settings.keys.save"), kind: .primary,
                    enabled: hasInput, action: { keys.save(provider) })
                if mask != nil {
                    SettingsPill(
                        title: Localized.string("settings.keys.delete"),
                        action: { keys.delete(provider) })
                }
            }
        }
    }

}

/// Settings › Sistema (Wave 16g): about, the stored files, the welcome, and
/// a danger zone that holds the one action here that cannot be undone.
struct SettingsSystemPage: View {
    var chat: ChatViewModel?
    var updates: UpdateState?
    var welcome: WelcomeModel?
    let storageLabel: String
    @Binding var confirmPurge: Bool
    let onClose: () -> Void
    /// Attachments change while other pages are open; read on each visit.
    var onAppear: () -> Void = {}
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.system.title)
            SettingsCard(label: Localized.string("settings.system.about")) {
                SettingsRow(
                    title: Localized.string("settings.app.version"), subtitle: SettingsVersion.current,
                    key: "settings.app.version"
                ) { updateControl }
                if let welcome {
                    SettingsRow(title: Localized.string("settings.welcome.again"), key: "settings.welcome.again") {
                        SettingsPill(title: Localized.string("settings.system.open")) {
                            welcome.reopen()
                            onClose()
                        }
                    }
                }
            }
            SettingsCard(label: Localized.string("settings.system.danger")) {
                SettingsRow(
                    title: Localized.string("settings.app.attachments"), subtitle: storageLabel,
                    key: "settings.app.attachments"
                ) {
                    SettingsPill(
                        title: Localized.string("settings.system.purge"), kind: .destructive,
                        enabled: chat?.hasStoredAttachments ?? false
                    ) { confirmPurge = true }
                }
            }
        }
        .onAppear(perform: onAppear)
    }

    @ViewBuilder private var updateControl: some View {
        if let updates {
            if let available = updates.available {
                SettingsPill(
                    title: String(format: Localized.string("settings.app.version.see"), available.tag),
                    kind: .primary
                ) { openURL(available.pageURL) }
            } else {
                SettingsPill(
                    title: updates.checking
                        ? Localized.string("settings.app.version.checking")
                        : Localized.string("settings.app.version.check"),
                    enabled: !updates.checking
                ) { updates.requestCheck() }
            }
        }
    }
}

/// A permission as a row: what it is for, and either its state or the way
/// to System Settings, which never runs out (the system prompt shows once).
struct SettingsPermissionRow: View {
    let model: PermissionRowModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsRow(title: model.title, subtitle: model.body) {
            if model.showsButton {
                SettingsPill(title: Localized.string("settings.system.open")) { openURL(model.link) }
            } else {
                Text(model.status)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.accentText)
            }
        }
    }
}

extension WelcomePermission {
    var rowKind: PermissionRowModel.Kind {
        switch self {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .screenRecording: .screenRecording
        case .speechRecognition: .speechRecognition
        }
    }
}
