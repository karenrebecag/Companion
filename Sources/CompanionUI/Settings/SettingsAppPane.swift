import AppKit
import CompanionCore
import CompanionUIPro
import SwiftUI

/// Settings › Privacidad: what it may look at, the permissions with their
/// live state, the browser link, and the keys.
struct SettingsPrivacyPage: View {
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    var browser: BrowserSettingsModel?
    @State private var context = ContextSettingsModel()
    /// Wave 15c-6: reads the Keychain only from `.onAppear`, never at boot.
    @State private var keys = KeysSettingsModel()
    /// Wave 17: starts from the stored preference; `onChange` below is the
    /// only writer, so a background change (none exists today) would not
    /// show up here until the page reappears.
    @State private var lendHands = HandsLendingPreference.enabled
    /// Puente QA D1: starts off and is never stored; `QAScopePreference` is
    /// the only writer and refuses to turn on without the hands lent and an
    /// owner check that can be shown.
    @State private var qaMode = QAScopePreference.enabled
    @State private var qaRefused = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SecuritySection(title: Localized.string("settings.context.label")) {
                SettingsRow(
                    title: Localized.string("settings.context.screen"),
                    description: Localized.string("settings.context.screen.subtitle")
                ) {
                    SettingsSwitch(label: Localized.string("settings.context.screen"), isOn: contextBinding(\.screen))
                }
                .settingsAnchor("settings.context.screen")
                SettingsRow(
                    title: Localized.string("settings.context.documents"),
                    description: Localized.string("settings.context.documents.subtitle")
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.context.documents"), isOn: contextBinding(\.documents))
                }
                .settingsAnchor("settings.context.documents")
                SettingsRow(
                    title: Localized.string("settings.context.location"),
                    description: Localized.string("settings.context.location.subtitle")
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.context.location"), isOn: contextBinding(\.location))
                }
                .settingsAnchor("settings.context.location")
                SettingsRow(
                    title: Localized.string("settings.privacy.lendHands"),
                    description: Localized.string("settings.privacy.lendHands.subtitle")
                ) {
                    SettingsSwitch(label: Localized.string("settings.privacy.lendHands"), isOn: $lendHands)
                }
                .settingsAnchor("settings.privacy.lendHands")
                SettingsRow(
                    title: Localized.string("settings.privacy.qaMode"),
                    description: Localized.string(
                        qaRefused ? "settings.privacy.qaMode.unavailable" : "settings.privacy.qaMode.subtitle")
                ) {
                    SettingsSwitch(label: Localized.string("settings.privacy.qaMode"), isOn: $qaMode)
                        .disabled(!lendHands)
                }
                .settingsAnchor("settings.privacy.qaMode")
            }
            if let welcome {
                SecuritySection(title: Localized.string("settings.permissions")) {
                    ForEach(WelcomePermission.allCases, id: \.self) { permission in
                        SettingsPermissionRow(model: PermissionRowModel(
                            kind: permission.rowKind,
                            granted: welcome.facts.granted.contains(permission)))
                    }
                }
                .settingsAnchor("settings.permissions")
            }
            if let browser { SettingsBrowserSection(model: browser) }
            SettingsAlwaysAllowCard()
            keysSection
        }
        .onChange(of: lendHands) { _, on in
            HandsLendingPreference.enabled = on
            if !on { qaMode = false }
        }
        .onChange(of: qaMode) { _, on in
            Task { await applyQAMode(on) }
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
                browser?.refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    /// The switch shows what the preference accepted, not what was tapped.
    private func applyQAMode(_ on: Bool) async {
        let canVerify = on ? await chat?.qaGate?.canVerify() ?? false : false
        let applied = QAScopePreference.set(on, handsLent: lendHands, canVerify: canVerify)
        qaRefused = on && !applied
        if qaMode != applied { qaMode = applied }
    }

    private func contextBinding(
        _ keyPath: ReferenceWritableKeyPath<ContextSettingsModel, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { context[keyPath: keyPath] },
            set: { context[keyPath: keyPath] = $0 })
    }

    /// Wave 15c-6: a stored value never comes back to the screen: the row shows
    /// only the mask the model built, and the field is secure.
    private var keysSection: some View {
        APIKeysSection(
            rows: keyRows, strings: keyStrings,
            draft: keyDraft,
            onSave: { id in saveKey(id) },
            onRemove: { id in removeKey(id) })
        .settingsAnchor("settings.keys.header")
    }

    private static let keyProviders: [(id: String, provider: KeysSettingsModel.Provider, title: String, privacy: String?)] = [
        ("openai", .openAI, "settings.keys.openai", nil),
        ("cerebras", .cerebras, "settings.keys.cerebras", "settings.keys.cerebras.privacy"),
        ("elevenlabs", .elevenLabs, "settings.keys.elevenlabs", "settings.keys.elevenlabs.privacy"),
        ("exa", .exa, "settings.keys.exa", "settings.keys.exa.privacy"),
        ("typesafe", .typesafe, "settings.keys.typesafe", "settings.keys.typesafe.privacy"),
    ]

    private var keyRows: [APIKeyRowModel] {
        Self.keyProviders.map { item in
            APIKeyRowModel(
                id: item.id, title: Localized.string(item.title),
                detail: item.privacy.map { Localized.string($0) },
                masked: keys.masked[item.provider])
        }
    }

    private var keyStrings: APIKeyStrings {
        let countFormat = Localized.string("settings.keys.count")
        return APIKeyStrings(
            title: Localized.string("settings.keys.title"),
            description: Localized.string("settings.keys.blurb"),
            count: { String(format: countFormat, $0, $1) },
            savedStatus: Localized.string("settings.keys.status.saved"),
            missingStatus: Localized.string("settings.keys.status.missing"),
            placeholder: Localized.string("settings.keys.paste"),
            replacePlaceholder: Localized.string("settings.keys.replace.placeholder"),
            save: Localized.string("settings.keys.save"),
            addKey: Localized.string("settings.keys.add"),
            cancel: Localized.string("settings.keys.cancel"),
            providerLabel: Localized.string("settings.keys.provider"),
            allSet: Localized.string("settings.keys.allSet"),
            providerRequired: Localized.string("settings.keys.providerRequired"),
            keyRequired: Localized.string("settings.keys.keyRequired"),
            holdToRemove: Localized.string("settings.keys.holdToRemove"),
            removed: Localized.string("settings.keys.removed"))
    }

    private func keyDraft(_ id: String) -> Binding<String> {
        Binding(
            get: { draftText(id) },
            set: { setDraftText(id, $0) })
    }

    private func draftText(_ id: String) -> String {
        switch id {
        case "cerebras": keys.cerebrasField
        case "elevenlabs": keys.elevenLabsField
        case "exa": keys.exaField
        case "typesafe": keys.typesafeField
        default: keys.openAIField
        }
    }

    private func setDraftText(_ id: String, _ value: String) {
        switch id {
        case "cerebras": keys.cerebrasField = value
        case "elevenlabs": keys.elevenLabsField = value
        case "exa": keys.exaField = value
        case "typesafe": keys.typesafeField = value
        default: keys.openAIField = value
        }
    }

    private func provider(_ id: String) -> KeysSettingsModel.Provider? {
        Self.keyProviders.first { $0.id == id }?.provider
    }

    private func saveKey(_ id: String) {
        if let provider = provider(id) { keys.save(provider) }
    }

    private func removeKey(_ id: String) {
        if let provider = provider(id) { keys.delete(provider) }
    }
}

/// Settings › Sistema: about, the stored files, the welcome, and a danger
/// zone that holds the one action here that cannot be undone.
struct SettingsSystemPage: View {
    var chat: ChatViewModel?
    var updates: UpdateState?
    var welcome: WelcomeModel?
    let storageLabel: String
    @Binding var confirmPurge: Bool
    let onClose: () -> Void
    /// Attachments change while other pages are open; read on each visit.
    var onAppear: () -> Void = {}
    let history: HistoryClearModel
    @Environment(\.openURL) private var openURL

    /// The row only asks; the dialog and its model do the deleting.
    func pressClearRow() { history.present() }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsGroup(title: Localized.string("settings.system.about")) {
                SettingsRow(
                    title: Localized.string("settings.app.version"), description: SettingsVersion.current
                ) { updateControl }
                .settingsAnchor("settings.app.version")
                if let welcome {
                    SettingsRow(title: Localized.string("settings.welcome.again")) {
                        SettingsPill(title: Localized.string("settings.system.open")) {
                            welcome.reopen()
                            onClose()
                        }
                    }
                    .settingsAnchor("settings.welcome.again")
                }
            }
            SettingsGroup(title: Localized.string("settings.history.label")) {
                SettingsRow(
                    title: Localized.string("settings.history.row"),
                    description: Localized.string("settings.history.row.subtitle")
                ) {
                    SettingsPill(title: Localized.string("settings.history.action"), kind: .destructive) {
                        pressClearRow()
                    }
                }
                .settingsAnchor(SettingsInventory.clearHistoryRowID)
            }
            SettingsGroup(title: Localized.string("settings.system.danger")) {
                SettingsRow(
                    title: Localized.string("settings.app.attachments"), description: storageLabel
                ) {
                    SettingsPill(
                        title: Localized.string("settings.system.purge"), kind: .destructive,
                        enabled: chat?.hasStoredAttachments ?? false
                    ) { confirmPurge = true }
                }
                .settingsAnchor("settings.app.attachments")
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

/// A permission as a row: what it is for, its state as a badge, and the way
/// to System Settings, which never runs out (the system prompt shows once).
struct SettingsPermissionRow: View {
    let model: PermissionRowModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        SecurityRow(
            title: model.title, detail: model.body,
            badge: SecurityBadge(model.status, tone: model.granted ? .positive : .warning)
        ) {
            if model.showsButton {
                SettingsPill(title: Localized.string("settings.system.open")) { openURL(model.link) }
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
