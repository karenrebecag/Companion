import AppKit
import CompanionCore
import SwiftUI

/// Settings › Privacidad (Wave 16g): what it may look at, the permissions
/// with their live state, and the keys.
struct SettingsPrivacyPage: View {
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    var browser: BrowserSettingsModel?
    @State private var context = ContextSettingsModel()
    /// Wave 15c-6: reads the Keychain only from `.onAppear`, never at boot.
    @State private var keys = KeysSettingsModel()
    /// Wave 17: starts from the stored preference; `onChange` below is the
    /// only writer, so a background change (none exists today) would not
    /// show up here until the page reappears — same tradeoff `sounds` and
    /// `screenGlow` already make on this page's sibling.
    @State private var lendHands = HandsLendingPreference.enabled
    @Environment(\.openSettingsDialog) private var openSettingsDialog

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
                SettingsRow(
                    title: Localized.string("settings.context.documents"),
                    subtitle: Localized.string("settings.context.documents.subtitle"),
                    key: "settings.context.documents"
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.context.documents"), isOn: contextBinding(\.documents))
                }
                SettingsRow(
                    title: Localized.string("settings.context.location"),
                    subtitle: Localized.string("settings.context.location.subtitle"),
                    key: "settings.context.location"
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.context.location"), isOn: contextBinding(\.location))
                }
                SettingsRow(
                    title: Localized.string("settings.privacy.lendHands"),
                    subtitle: Localized.string("settings.privacy.lendHands.subtitle"),
                    key: "settings.privacy.lendHands"
                ) {
                    SettingsSwitch(label: Localized.string("settings.privacy.lendHands"), isOn: $lendHands)
                }
            }
            if welcome != nil {
                SettingsCard(label: Localized.string("settings.permissions")) {
                    SettingsRow(
                        title: Localized.string("settings.permissions"),
                        subtitle: Localized.string("settings.dialog.permissions.subline"),
                        key: "settings.permissions"
                    ) {
                        SettingsPill(title: Localized.string("settings.dialog.open")) {
                            openSettingsDialog(.permissions)
                        }
                    }
                }
            }
            if let browser { SettingsBrowserCard(model: browser) }
            SettingsCard(label: Localized.string("settings.keys.label"), key: "settings.keys.header") {
                keysBlock.padding(Space.x4)
            }
        }
        .onChange(of: lendHands) { _, on in HandsLendingPreference.enabled = on }
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
                browser?.refresh()
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

/// Sistema's sections, in Incredible's order (S2 of ajustes-hoja-incredible).
/// The danger zone joins when its row does; an empty section is not drawn.
package enum SettingsSystemSection: CaseIterable, Equatable {
    case app, sound, about, data

    package var label: String {
        switch self {
        case .app: Localized.string("settings.system.app")
        case .sound: Localized.string("settings.system.sound")
        case .about: Localized.string("settings.system.about")
        case .data: Localized.string("settings.system.data")
        }
    }

    /// The inventory keys each section holds, top to bottom.
    package var rows: [String] {
        switch self {
        case .app: ["settings.screenGlow"]
        case .sound: ["settings.muteWhileTalking", "settings.muteEffects"]
        case .about: ["settings.app.version"]
        // Both rows erase stored data, so they share Incredible's one "Data" section.
        case .data: [SettingsInventory.clearHistoryRowID, "settings.app.attachments"]
        }
    }

    /// Incredible asks "mute sound effects?"; Companion stores "sounds on".
    /// Only the view inverts it, so the preference keeps its meaning.
    package static func effectsMuted(soundsOn: Bool) -> Bool { !soundsOn }
    package static func soundsOn(effectsMuted: Bool) -> Bool { !effectsMuted }

    /// The switch the page binds: reads and writes `sounds` through the inversion.
    static func effectsMuted(_ sounds: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { effectsMuted(soundsOn: sounds.wrappedValue) },
            set: { sounds.wrappedValue = soundsOn(effectsMuted: $0) })
    }
}

/// Settings › Sistema: app, sound, about and data, as Incredible lays them out.
struct SettingsSystemPage: View {
    var chat: ChatViewModel?
    var updates: UpdateState?
    let storageLabel: String
    /// Attachments change while other pages are open; read on each visit.
    var onAppear: () -> Void = {}
    let history: HistoryClearModel
    @State private var sounds = InterfaceSound.enabled && ThinkingSoundPref.enabled
    @State private var muteWhileTalking = MuteSoundWhileTalkingPref.enabled
    @State private var screenGlow = ScreenGlowPreference.enabled()
    @Environment(\.openURL) private var openURL
    @Environment(\.openSettingsDialog) private var openSettingsDialog

    /// The row only asks; the dialog and its model do the deleting.
    func pressClearRow() { history.present() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.system.title)
            ForEach(SettingsSystemSection.allCases, id: \.self) { section in
                SettingsCard(label: section.label) {
                    ForEach(section.rows, id: \.self) { row($0) }
                }
            }
        }
        .onAppear(perform: onAppear)
        .onChange(of: screenGlow) { _, on in ScreenGlowPreference.set(on) }
        .onChange(of: muteWhileTalking) { _, on in MuteSoundWhileTalkingPref.enabled = on }
        .onChange(of: sounds) { _, on in
            InterfaceSound.enabled = on
            ThinkingSoundPref.enabled = on
        }
    }

    private static let drawn: Set<String> = [
        "settings.screenGlow", "settings.muteWhileTalking", "settings.muteEffects",
        "settings.app.version", SettingsInventory.clearHistoryRowID, "settings.app.attachments",
    ]

    /// The rows `row(_:)` knows how to draw; a section key outside it would draw nothing.
    static func draws(_ key: String) -> Bool { drawn.contains(key) }

    @ViewBuilder private func row(_ key: String) -> some View {
        switch key {
        case "settings.screenGlow":
            SettingsRow(
                title: Localized.string(key), subtitle: Localized.string("settings.screenGlow.subtitle"), key: key
            ) { SettingsSwitch(label: Localized.string(key), isOn: $screenGlow) }
        case "settings.muteWhileTalking":
            SettingsRow(
                title: Localized.string(key), subtitle: Localized.string("settings.muteWhileTalking.subtitle"),
                key: key
            ) { SettingsSwitch(label: Localized.string(key), isOn: $muteWhileTalking) }
        case "settings.muteEffects":
            SettingsRow(
                title: Localized.string(key), subtitle: Localized.string("settings.muteEffects.subtitle"), key: key
            ) { SettingsSwitch(label: Localized.string(key), isOn: SettingsSystemSection.effectsMuted($sounds)) }
        case "settings.app.version":
            SettingsRow(title: Localized.string(key), subtitle: SettingsVersion.current, key: key) { updateControl }
        case SettingsInventory.clearHistoryRowID:
            SettingsRow(
                title: Localized.string("settings.history.row"),
                subtitle: Localized.string("settings.history.row.subtitle"),
                key: SettingsInventory.clearHistoryRowID
            ) {
                SettingsPill(title: Localized.string("settings.history.action"), kind: .destructive) {
                    pressClearRow()
                }
            }
        case "settings.app.attachments":
            SettingsRow(title: Localized.string(key), subtitle: storageLabel, key: key) {
                SettingsPill(
                    title: Localized.string("settings.system.purge"), kind: .destructive,
                    enabled: chat?.hasStoredAttachments ?? false
                ) { openSettingsDialog(.purgeAttachments) }
            }
        default:
            EmptyView()
        }
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
