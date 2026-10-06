import CompanionCore
import Foundation
import Observation
import SwiftUI

/// The idle pebble's visibility, and whether a hold was ever completed.
package enum IslandPreference {
    static let key = "companion.island.pebbleHidden"
    static let learnedKey = "companion.island.holdLearned"

    package static var pebbleHidden: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    package static var holdLearned: Bool {
        get { UserDefaults.standard.bool(forKey: learnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: learnedKey) }
    }
}

/// What Settings and the island share about the hold (Wave 12b): whether
/// the FN tap is allowed to listen, and whether the idle mark shows.
@Observable
@MainActor
package final class HoldSettingsModel {
    package private(set) var granted = false
    /// Main is key: it paints the sheet, the island does not.
    package var mainInFront = false
    package var pebbleHidden: Bool {
        didSet { IslandPreference.pebbleHidden = pebbleHidden }
    }
    /// A hold has produced a turn once: hover stops teaching it (12c).
    package var holdLearned: Bool {
        didSet { IslandPreference.holdLearned = holdLearned }
    }
    /// Called after the user answers the system prompt, so the tap can start.
    package var onPermissionChanged: (() -> Void)?
    private let permission: (any AccessibilityChecking)?

    package init(permission: (any AccessibilityChecking)? = nil) {
        self.permission = permission
        self.pebbleHidden = IslandPreference.pebbleHidden
        self.holdLearned = IslandPreference.holdLearned
        refresh()
    }

    package func refresh() {
        granted = permission?.isTrusted() ?? false
    }

    /// The system prompt, once; after a deny it returns false with no UI,
    /// which is why the row also offers the deep link.
    package func request() {
        guard let permission else { return }
        granted = permission.request()
        onPermissionChanged?()
    }

    package var row: PermissionRowModel {
        PermissionRowModel(kind: .accessibility, granted: granted)
    }
}

/// Settings › General (Wave 16g): the key to talk, the key to dictate, the
/// language and the sounds, as one card of rows. The vocabulary moved to its
/// own page; the mark and the hands-free shortcut stay out, as in 16d.
struct SettingsGeneralPage: View {
    /// Owns the Accessibility permission dictation needs.
    let accessibility: (any AccessibilityChecking)?
    let onLanguageChange: () -> Void
    /// 15b-1/15b-2: FN is always the agent now; this is the only thing left
    /// deciding dictation.
    @State private var dictationKey = VoiceProfile.settings.dictationKey
    @State private var sounds = InterfaceSound.enabled && ThinkingSoundPref.enabled
    @State private var muteWhileTalking = MuteSoundWhileTalkingPref.enabled
    @State private var screenGlow = ScreenGlowPreference.enabled()
    @State private var context = ContextSettingsModel()
    @State private var dictationLanguages = SpokenLanguagePreference.dictationCodes()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsPageHeader(title: SettingsTab.general.title)
            SettingsCard {
                SettingsRow(
                    title: Localized.string("settings.app.talk.hold"),
                    subtitle: Localized.string("settings.app.talk.hold.subtitle"),
                    key: "settings.app.talk.hold"
                ) {
                    Keycap(Localized.string("settings.app.talk.fn"), size: .small)
                }
                SettingsRow(
                    title: Localized.string("settings.app.talk.dictationKey"),
                    subtitle: Localized.string("settings.app.talk.dictationKey.subtitle"),
                    key: "settings.app.talk.dictationKey"
                ) {
                    SettingsItem(
                        title: "", value: HoldCopy.dictationKey(dictationKey),
                        options: DictationKey.allCases.map { ($0, HoldCopy.dictationKey($0)) },
                        id: "settings.app.talk.dictationKey"
                    ) { setDictationKey($0) }
                }
                if dictationKey != .off, !context.accessibilityGranted {
                    SettingsPermissionRow(model: context.accessibilityRow)
                }
                SettingsLanguageLine(onChange: onLanguageChange)
                DictationLanguageLine(codes: $dictationLanguages)
                SettingsRow(
                    title: Localized.string("settings.sounds"),
                    subtitle: Localized.string("settings.sounds.subtitle"),
                    key: "settings.sounds"
                ) {
                    SettingsSwitch(label: Localized.string("settings.sounds"), isOn: $sounds)
                }
                SettingsRow(
                    title: Localized.string("settings.muteWhileTalking"),
                    subtitle: Localized.string("settings.muteWhileTalking.subtitle"),
                    key: "settings.muteWhileTalking"
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.muteWhileTalking"), isOn: $muteWhileTalking)
                }
                SettingsRow(
                    title: Localized.string("settings.screenGlow"),
                    subtitle: Localized.string("settings.screenGlow.subtitle"),
                    key: "settings.screenGlow"
                ) {
                    SettingsSwitch(label: Localized.string("settings.screenGlow"), isOn: $screenGlow)
                }
            }
        }
        .onChange(of: screenGlow) { _, on in ScreenGlowPreference.set(on) }
        .onChange(of: muteWhileTalking) { _, on in MuteSoundWhileTalkingPref.enabled = on }
        .onChange(of: sounds) { _, on in
            InterfaceSound.enabled = on
            ThinkingSoundPref.enabled = on
        }
        .onAppear {
            context.accessibility = accessibility
            context.refreshTrust()
            dictationLanguages = SpokenLanguagePreference.dictationCodes()
        }
        .task {
            // The dictation row answers a grant made in System Settings.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                context.refreshTrust()
            }
        }
    }

    private func setDictationKey(_ new: DictationKey) {
        dictationKey = new
        var settings = VoiceProfile.settings
        settings.dictationKey = new
        VoiceProfile.settings = settings
        context.refreshTrust()
    }
}

enum HoldCopy {
    static func dictationKey(_ key: DictationKey) -> String {
        switch key {
        case .off: Localized.string("settings.app.talk.dictationKey.off")
        case .rightOption: Localized.string("settings.app.talk.dictationKey.rightOption")
        case .rightCommand: Localized.string("settings.app.talk.dictationKey.rightCommand")
        }
    }
}

/// The settings menu commits one row. Dictation keeps up to five codes, so
/// this trigger opens a multi-select popover instead of that menu. The wide
/// settings popup is not on this branch (local reference; Incredible
/// language pickers).
// HACK: a 320pt popover with a search field stands in for Incredible's wide
// popup, and the Speaking row uses a menu without search. Both are tight for
// thirty languages. Replace them with the wide settings popup when it lands.
struct DictationLanguageLine: View {
    @Binding var codes: [String]
    @State private var open = false
    @State private var query = ""

    private var pill: String {
        if codes.isEmpty {
            return Localized.string("settings.dictation.language.auto")
        }
        return codes.map { Localized.string("spoken.language.\($0)") }
            .joined(separator: " · ")
    }

    private var visible: [SpokenLanguagePreference.Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return SpokenLanguagePreference.catalog }
        return SpokenLanguagePreference.catalog.filter { entry in
            entry.code.localizedCaseInsensitiveContains(needle)
                || entry.englishName.localizedCaseInsensitiveContains(needle)
                || entry.nativeName.localizedCaseInsensitiveContains(needle)
                || Localized.string("spoken.language.\(entry.code)")
                    .localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        SettingsRow(
            title: Localized.string("settings.dictation.language"),
            subtitle: Localized.string("settings.dictation.language.subtitle"),
            key: "settings.dictation.language"
        ) {
            Button {
                open = true
            } label: {
                HStack(spacing: SelectMetrics.gap) {
                    Text(pill)
                        .font(Fonts.sans(TypeSize.body).weight(.medium))
                        .foregroundStyle(Semantic.foreground)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.uiMicro)
                        .foregroundStyle(Semantic.faintForeground)
                }
                .padding(.horizontal, SelectMetrics.paddingX)
                .frame(height: SelectMetrics.height)
                .background(Semantic.wash)
                .clipShape(RoundedRectangle(cornerRadius: SelectMetrics.radius))
                .contentShape(RoundedRectangle(cornerRadius: SelectMetrics.radius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(pill))
            .popover(isPresented: $open, arrowEdge: .bottom) {
                picker
            }
        }
        .onChange(of: open) { _, isOpen in
            if !isOpen { query = "" }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            TextField(Localized.string("settings.dictation.language.search"), text: $query)
                .textFieldStyle(.roundedBorder)
            if codes.isEmpty, query.isEmpty {
                Text(Localized.string("settings.dictation.language.empty"))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !codes.isEmpty {
                Text(Localized.string("settings.dictation.language.selected"))
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
                ForEach(codes, id: \.self) { code in
                    Button {
                        toggle(code)
                    } label: {
                        HStack {
                            Text(Localized.string("spoken.language.\(code)"))
                                .font(.uiLabel)
                                .foregroundStyle(Semantic.foreground)
                            Spacer()
                            Image(systemName: "xmark")
                                .font(.uiMicro)
                                .foregroundStyle(Semantic.faintForeground)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(Localized.string("spoken.language.\(code)")))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x1) {
                    if visible.isEmpty {
                        Text(String(
                            format: Localized.string("settings.dictation.language.none"),
                            SpokenLanguagePreference.catalog.count))
                            .typeRole(.micro)
                            .foregroundStyle(Semantic.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(visible, id: \.code) { entry in
                        languageRow(entry)
                    }
                }
            }
            .frame(maxHeight: ControlMetrics.languageListMaxHeight)
        }
        .padding(Space.x3)
        .frame(width: ControlMetrics.languagePickerWidth)
    }

    private func languageRow(_ entry: SpokenLanguagePreference.Entry) -> some View {
        let selected = codes.contains(entry.code)
        return Button {
            toggle(entry.code)
        } label: {
            HStack(spacing: Space.x2) {
                VStack(alignment: .leading, spacing: Space.none) {
                    Text(Localized.string("spoken.language.\(entry.code)"))
                        .font(.uiLabel)
                        .foregroundStyle(Semantic.foreground)
                    if !entry.nativeName.isEmpty {
                        Text(entry.nativeName)
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                }
                Spacer(minLength: Space.x2)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.uiMicro)
                        .foregroundStyle(Semantic.foreground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selected && codes.count >= SpokenLanguagePreference.maxDictation)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ code: String) {
        var next = codes
        if let index = next.firstIndex(of: code) {
            next.remove(at: index)
        } else if next.count < SpokenLanguagePreference.maxDictation {
            next.append(code)
        } else {
            return
        }
        SpokenLanguagePreference.setDictation(next)
        codes = SpokenLanguagePreference.dictationCodes()
    }
}

struct SpeechLanguageLine: View {
    @Binding var choice: String
    let dictation: [String]

    private var interface: AppLanguage { Localized.language() }

    private var autoLabel: String {
        SpeechLanguageCopy.autoLabel(dictation: dictation, interface: interface)
    }

    private var pill: String {
        SpeechLanguageCopy.pill(choice: choice, dictation: dictation, interface: interface)
    }

    private var subtitle: String {
        SpeechLanguageCopy.subtitle(choice: choice, dictation: dictation, interface: interface)
    }

    private var options: [(String, String)] {
        [(SpokenLanguagePreference.automatic, autoLabel)]
            + SpokenLanguagePreference.catalog.map { entry in
                (entry.code, Localized.string("spoken.language.\(entry.code)"))
            }
    }

    var body: some View {
        SettingsRow(
            title: Localized.string("settings.speech.language"),
            subtitle: subtitle,
            key: "settings.speech.language"
        ) {
            SettingsItem(
                title: "",
                value: pill,
                options: options,
                id: "settings.speech.language"
            ) { picked in
                SpokenLanguagePreference.setSpeech(picked)
                choice = SpokenLanguagePreference.speechCode()
            }
        }
    }
}
