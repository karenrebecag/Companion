import AppKit
import CompanionCore
import SwiftUI

/// Settings › Cuenta: who you are on top, then how the app looks (KD2), then
/// replaying the welcome, which Incredible keeps here as "Replay the tour".
struct SettingsYouPage: View {
    var welcome: WelcomeModel? = nil
    var onClose: () -> Void = {}
    // Pages also render in tests that never open the sheet.
    @Environment(SettingsSaveCenter.self) private var saves: SettingsSaveCenter?
    // Writes must persist with or without a sheet around the page.
    @State private var unhosted = SettingsSaveCenter()
    @State private var nameSlot = SettingsSaveSlot(committed: UserProfile.ownerName)
    @State private var aboutSlot = SettingsSaveSlot(committed: UserProfile.about)
    @State private var instructionsSlot = SettingsSaveSlot(committed: UserProfile.instructions)
    @State private var citySlot = SettingsSaveSlot(committed: UserProfile.city)
    @State private var avatarError: String?
    @State private var avatar = UserProfile.avatarImage
    @State private var fontDelta = TypeScale.delta
    @State private var appearance = AppearancePreference.stored

    static var appearanceOptions: [(AppearancePreference, String)] {
        AppearancePreference.allCases.map { ($0, $0.label) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.you.title, blurb: Localized.string("settings.you.blurb"))
            SettingsCard {
                profileRow.settingsSearchTarget("settings.you.photo")
                SettingsRow(title: Localized.string("settings.you.name"), key: "settings.you.name") {
                    field(
                        Localized.string("settings.you.name.placeholder"),
                        text: binding(.name, $nameSlot),
                        error: nameSlot.error,
                        onEnd: { endEditing(.name, $nameSlot) })
                }
                SettingsRow(
                    title: Localized.string("settings.you.city"),
                    subtitle: description(
                        beside: citySlot.error, Localized.string("settings.you.city.subtitle")),
                    key: "settings.you.city"
                ) {
                    field(
                        Localized.string("settings.you.city.placeholder"),
                        text: binding(.city, $citySlot),
                        error: citySlot.error,
                        onEnd: { endEditing(.city, $citySlot) })
                }
                SettingsTextRow(
                    title: Localized.string("settings.you.about"), key: "settings.you.about",
                    placeholder: Localized.string("settings.you.about.placeholder"),
                    text: binding(.about, $aboutSlot),
                    error: aboutSlot.error,
                    onEnd: { endEditing(.about, $aboutSlot) })
                SettingsTextRow(
                    title: Localized.string("settings.you.instructions"), key: "settings.you.instructions",
                    placeholder: Localized.string("settings.you.instructions.placeholder"),
                    text: binding(.instructions, $instructionsSlot),
                    error: instructionsSlot.error,
                    onEnd: { endEditing(.instructions, $instructionsSlot) })
            }
            SettingsCard(label: Localized.string("settings.you.looks")) {
                SettingsRow(title: Localized.string("settings.app.appearance"), key: "settings.app.appearance") {
                    SegmentedToggle(options: Self.appearanceOptions, selection: $appearance)
                }
                SettingsRow(
                    title: Localized.string("settings.app.textSize"),
                    subtitle: Localized.string("settings.app.textSize.subtitle"),
                    key: "settings.app.textSize"
                ) { fontStepper }
            }
            if let welcome {
                SettingsCard {
                    SettingsRow(title: Localized.string("settings.welcome.again"), key: "settings.welcome.again") {
                        SettingsPill(title: Localized.string("settings.system.open")) {
                            welcome.reopen()
                            onClose()
                        }
                    }
                }
            }
        }
        .onChange(of: appearance) { _, pref in
            AppearancePreference.stored = pref
            if let window = NSApp.keyWindow { WindowChrome.applyAppearance(window) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .companionProfileDidChange)) { _ in
            avatar = UserProfile.avatarImage
        }
    }

    private var profileRow: some View {
        HStack(spacing: Space.x4) {
            avatarThumb
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(nameSlot.shown.isEmpty ? Localized.string("settings.you.photo") : nameSlot.shown)
                    .font(.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                Text(SettingsSaveRow.subtitle(
                    error: avatarError, description: Localized.string("settings.you.photo.subtitle")))
                    .font(.uiCaption)
                    .foregroundStyle(photoFailed ? Semantic.destructive : Semantic.mutedForeground)
            }
            Spacer(minLength: Space.x3)
            SettingsPill(title: Localized.string("settings.change"), action: pickAvatar)
                .accessibilityLabel(Localized.string("settings.you.photo.change"))
        }
        .padding(Space.x4)
    }

    private var avatarThumb: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(width: SettingsOverlayMetrics.bigAvatar, height: SettingsOverlayMetrics.bigAvatar)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fontStepper: some View {
        HStack(spacing: Space.x2) {
            SettingsPill(title: "", symbol: "minus", enabled: fontDelta > TypeScale.min) {
                fontDelta = TypeScale.nudge(-1)
            }
            .accessibilityLabel(Localized.string("settings.app.textSize.smaller"))
            Text(TypeScale.displayLabel(fontDelta))
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
                .frame(minWidth: Space.x6)
                .accessibilityLabel(String(
                    format: Localized.string("settings.app.textSize.label"), TypeScale.displayLabel(fontDelta)))
            SettingsPill(title: "", symbol: "plus", enabled: fontDelta < TypeScale.max) {
                fontDelta = TypeScale.nudge(1)
            }
            .accessibilityLabel(Localized.string("settings.app.textSize.bigger"))
        }
    }

    private var photoFailed: Bool {
        if let avatarError, !avatarError.isEmpty { return true }
        return false
    }

    /// The description stays only while the helper would still show it.
    /// An error replaces it, so the row does not say both.
    private func description(beside error: String?, _ description: String) -> String? {
        guard let error, !error.isEmpty else {
            return SettingsSaveRow.subtitle(error: error, description: description)
        }
        return nil
    }

    private func field(
        _ placeholder: String, text: Binding<String>, error: String?, onEnd: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .trailing, spacing: Space.x1) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.uiLabel)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: Container.hero)
                .onEditingEnd(onEnd)
            if let error, !error.isEmpty {
                Text(SettingsSaveRow.subtitle(error: error, description: ""))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var center: SettingsSaveCenter { saves ?? unhosted }

    /// Persists on every keystroke; the notice waits for the end of the edit.
    /// A revert writes the previous text back through this same binding.
    private func binding(
        _ field: SettingsProfileField, _ slot: Binding<SettingsSaveSlot<String>>
    ) -> Binding<String> {
        Binding(
            get: { slot.wrappedValue.shown },
            set: { next in
                var copy = slot.wrappedValue
                center.commit(field.kind, &copy, next: next, timing: .onEndEditing, write: field.write)
                slot.wrappedValue = copy
            })
    }

    private func endEditing(
        _ field: SettingsProfileField, _ slot: Binding<SettingsSaveSlot<String>>
    ) {
        var copy = slot.wrappedValue
        center.endEditing(field.kind, &copy)
        slot.wrappedValue = copy
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            avatarError = center.avatarSet(saved: UserProfile.setAvatar(from: url))
            if avatarError == nil { avatar = UserProfile.avatarImage }
        }
    }
}

/// Focus loss, submit or the field leaving the screen ends an edit, so the
/// page can announce it once; the settle is idempotent.
private struct EditingEnd: ViewModifier {
    let perform: () -> Void
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { perform() }
            }
            .onSubmit(perform)
            .onDisappear(perform: perform)
    }
}

private extension View {
    func onEditingEnd(_ perform: @escaping () -> Void) -> some View {
        modifier(EditingEnd(perform: perform))
    }
}

/// A row whose control is a few lines of text, so the field sits under the
/// title instead of squeezing beside it.
struct SettingsTextRow: View {
    let title: String
    var key: String? = nil
    let placeholder: String
    @Binding var text: String
    var error: String? = nil
    var onEnd: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title)
                .font(.uiLabel)
                .foregroundStyle(Semantic.foreground)
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(2 ... 6)
                .padding(Space.x3)
                .background(RoundedRectangle(cornerRadius: Radius.lg).fill(Semantic.muted))
                .onEditingEnd(onEnd)
            if let error, !error.isEmpty {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .settingsSearchTarget(key)
    }
}

/// Settings › Vocabulario (Wave 16g): an example of what the list is for,
/// the words, and one field to add another.
struct SettingsVocabularyPage: View {
    @State private var text = VocabularyPreference.text
    @State private var draft = ""

    private var words: [String] { Vocabulary.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(
                title: SettingsTab.vocabulary.title, blurb: Localized.string("settings.vocabulary.subtitle"))
            example
            SettingsCard(key: "settings.vocabulary") {
                addRow
                ForEach(words, id: \.self) { word in
                    SettingsRow(title: word) {
                        IconButton(
                            "xmark",
                            label: String(format: Localized.string("settings.vocabulary.remove"), word),
                            danger: true
                        ) { commit(Vocabulary.removing(word, from: text)) }
                    }
                }
            }
            if words.isEmpty {
                Text(Localized.string("settings.vocabulary.empty"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
    }

    /// Shows a word from the list, so the example is about the user's words.
    private var example: some View {
        let word = words.first ?? Localized.string("settings.vocabulary.sample")
        let parts = Localized.string("settings.vocabulary.example").components(separatedBy: "%@")
        var line = AttributedString(parts.first ?? "")
        var highlighted = AttributedString(word)
        highlighted.foregroundColor = Semantic.accentText
        highlighted.inlinePresentationIntent = .stronglyEmphasized
        line += highlighted + AttributedString(parts.dropFirst().joined())
        return Text(line)
            .font(.uiSubtitle)
            .foregroundStyle(Semantic.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.x6)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private var addRow: some View {
        HStack(spacing: Space.x3) {
            TextField(Localized.string("settings.vocabulary.placeholder"), text: $draft)
                .textFieldStyle(.plain)
                .font(.uiLabel)
                .onSubmit(add)
            SettingsPill(
                title: Localized.string("settings.vocabulary.add"), kind: .primary, symbol: "plus",
                enabled: canAdd, action: add)
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
    }

    private var canAdd: Bool {
        Vocabulary.adding(draft, to: text) != Vocabulary.adding("", to: text)
    }

    private func add() {
        guard canAdd else { return }
        commit(Vocabulary.adding(draft, to: text))
        draft = ""
    }

    private func commit(_ new: String) {
        text = new
        VocabularyPreference.text = new
    }
}

/// Settings › Memoria (Wave 16g): what Companion kept from past
/// conversations, each with a way to forget it. The profile file is edited
/// as the file it is, so it only gets a way to open its folder.
struct SettingsMemoryPage: View {
    let memory: (any MemoryBrowsing)?
    @State private var entries: [MemoryEntry] = []
    @State private var confirming: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.memory.title, blurb: Localized.string("settings.memory.blurb"))
            SettingsCard {
                SettingsRow(
                    title: Localized.string("settings.memory.profile"),
                    subtitle: Localized.string("settings.memory.profile.subtitle"),
                    key: "settings.memory.header"
                ) {
                    SettingsPill(title: Localized.string("settings.memory.openFolder"), action: openFolder)
                }
            }
            if failed {
                Text(Localized.string("settings.memory.forget.error"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
            }
            if entries.isEmpty {
                SettingsEmptyState(symbol: "brain", text: Localized.string("settings.memory.empty")) { EmptyView() }
            } else {
                SettingsCard(label: Localized.string("settings.memory.header")) {
                    ForEach(entries) { entry in row(entry) }
                }
            }
        }
        .onAppear(perform: reload)
    }

    @ViewBuilder private func row(_ entry: MemoryEntry) -> some View {
        if confirming == entry.id {
            SettingsRow(title: Localized.string("settings.memory.forget.ask"), subtitle: MemoryCopy.headline(entry)) {
                HStack(spacing: Space.x2) {
                    SettingsPill(title: Localized.string("settings.purge.cancel")) { confirming = nil }
                    SettingsPill(title: Localized.string("settings.memory.forget"), kind: .destructive) {
                        forget(entry)
                    }
                }
            }
        } else {
            SettingsRow(title: MemoryCopy.headline(entry), subtitle: MemoryCopy.caption(entry)) {
                SettingsPill(title: Localized.string("settings.memory.forget")) { confirming = entry.id }
            }
        }
    }

    private func reload() {
        entries = memory?.entries() ?? []
    }

    private func forget(_ entry: MemoryEntry) {
        confirming = nil
        do {
            try memory?.forget(entry.id)
            failed = false
        } catch {
            failed = true
        }
        reload()
    }

    private func openFolder() {
        NSWorkspace.shared.open(MemoryLocation.directory())
    }
}

enum MemoryCopy {
    /// The first line that says what happened: summaries open with a date
    /// heading, which reads as a title but says nothing. A heading is the
    /// fallback when there is nothing else.
    static func headline(_ entry: MemoryEntry) -> String {
        let lines = entry.text.split(whereSeparator: \.isNewline).map { String($0) }
        let body = lines.first { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !clean($0).isEmpty }
        let line = clean(body ?? lines.first ?? "")
        return line.count > IslandResult.maxLine ? String(line.prefix(IslandResult.maxLine)) + "…" : line
    }

    private static func clean(_ line: String) -> String {
        line.trimmingCharacters(in: CharacterSet(charactersIn: "#-* ").union(.whitespaces))
    }

    static func caption(_ entry: MemoryEntry) -> String {
        let kind = Localized.string("settings.memory.kind.\(entry.kind.rawValue)")
        return entry.day.isEmpty ? kind : "\(kind) · \(entry.day)"
    }
}
