import AppKit
import CompanionCore
import SwiftUI

/// Settings › Tú (Wave 16g): who you are on top, then how the app looks.
struct SettingsYouPage: View {
    @State private var ownerName = UserProfile.ownerName
    @State private var about = UserProfile.about
    @State private var instructions = UserProfile.instructions
    @State private var avatar = UserProfile.avatarImage
    @State private var fontDelta = TypeScale.delta
    @State private var appearance = AppearancePreference.stored

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.you.title, blurb: Localized.string("settings.you.blurb"))
            SettingsCard {
                profileRow
                SettingsRow(title: Localized.string("settings.you.name"), key: "settings.you.name") {
                    TextField(Localized.string("settings.you.name.placeholder"), text: $ownerName)
                        .textFieldStyle(.plain)
                        .font(.uiLabel)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: Container.hero)
                }
                SettingsTextRow(
                    title: Localized.string("settings.you.about"), key: "settings.you.about",
                    placeholder: Localized.string("settings.you.about.placeholder"), text: $about)
                SettingsTextRow(
                    title: Localized.string("settings.you.instructions"), key: "settings.you.instructions",
                    placeholder: Localized.string("settings.you.instructions.placeholder"), text: $instructions)
            }
            SettingsCard(label: Localized.string("settings.you.looks")) {
                SettingsRow(title: Localized.string("settings.app.appearance"), key: "settings.app.appearance") {
                    SettingsItem(
                        title: "", value: appearance.label,
                        options: AppearancePreference.allCases.map { ($0, $0.label) },
                        id: "settings.app.appearance"
                    ) { appearance = $0 }
                }
                SettingsRow(
                    title: Localized.string("settings.app.textSize"),
                    subtitle: Localized.string("settings.app.textSize.subtitle"),
                    key: "settings.app.textSize"
                ) { fontStepper }
            }
        }
        .onChange(of: ownerName) { persistProfile() }
        .onChange(of: about) { persistProfile() }
        .onChange(of: instructions) { persistProfile() }
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
                Text(ownerName.isEmpty ? Localized.string("settings.you.photo") : ownerName)
                    .font(.uiSubtitle)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("settings.you.photo.subtitle"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
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

    // No notification per keystroke: only the avatar posts, since it is the
    // only thing other views observe; the text is read on demand.
    private func persistProfile() {
        UserProfile.ownerName = ownerName
        UserProfile.about = about
        UserProfile.instructions = instructions
    }

    private func pickAvatar() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if UserProfile.setAvatar(from: url) { avatar = UserProfile.avatarImage }
        }
    }
}

/// A row whose control is a few lines of text, so the field sits under the
/// title instead of squeezing beside it.
struct SettingsTextRow: View {
    let title: String
    var key: String? = nil
    let placeholder: String
    @Binding var text: String
    @Environment(\.settingsHighlight) private var highlight

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
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .background(key != nil && key == highlight ? Semantic.hover : Color.clear)
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
            SettingsCard {
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
