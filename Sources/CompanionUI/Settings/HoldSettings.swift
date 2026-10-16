import CompanionCore
import CompanionUIPro
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
/// language and the sounds, as one group of rows. The vocabulary moved to its
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
    @State private var microphone = SettingsMicrophoneModel()
    @State private var microphoneOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            SettingsGroup {
                SettingsRow(
                    title: Localized.string("settings.app.talk.hold"),
                    description: Localized.string("settings.app.talk.hold.subtitle")
                ) {
                    Keycap(Localized.string("settings.app.talk.fn"), size: .small)
                }
                .settingsAnchor("settings.app.talk.hold")
                SettingsRow(
                    title: Localized.string("settings.app.talk.dictationKey"),
                    description: Localized.string("settings.app.talk.dictationKey.subtitle")
                ) {
                    SettingsItem(
                        title: "", value: HoldCopy.dictationKey(dictationKey),
                        options: DictationKey.allCases.map { ($0, HoldCopy.dictationKey($0)) },
                        id: "settings.app.talk.dictationKey"
                    ) { setDictationKey($0) }
                }
                .settingsAnchor("settings.app.talk.dictationKey")
                if dictationKey != .off, !context.accessibilityGranted {
                    SettingsPermissionRow(model: context.accessibilityRow)
                }
                SettingsRow(
                    title: Localized.string("settings.microphone"),
                    description: microphone.rowSubtitle
                ) {
                    SettingsPill(title: Localized.string("settings.change")) {
                        microphoneOpen = true
                    }
                    .popover(isPresented: $microphoneOpen) {
                        SettingsMicrophonePopover(model: microphone)
                            .onAppear { microphone.opened() }
                            .onDisappear { microphone.closed() }
                    }
                }
                .settingsAnchor("settings.microphone")
                SettingsLanguageLine(onChange: onLanguageChange)
                SettingsRow(
                    title: Localized.string("settings.sounds"),
                    description: Localized.string("settings.sounds.subtitle")
                ) {
                    SettingsSwitch(label: Localized.string("settings.sounds"), isOn: $sounds)
                }
                .settingsAnchor("settings.sounds")
                SettingsRow(
                    title: Localized.string("settings.muteWhileTalking"),
                    description: Localized.string("settings.muteWhileTalking.subtitle")
                ) {
                    SettingsSwitch(
                        label: Localized.string("settings.muteWhileTalking"), isOn: $muteWhileTalking)
                }
                .settingsAnchor("settings.muteWhileTalking")
                SettingsRow(
                    title: Localized.string("settings.screenGlow"),
                    description: Localized.string("settings.screenGlow.subtitle")
                ) {
                    SettingsSwitch(label: Localized.string("settings.screenGlow"), isOn: $screenGlow)
                }
                .settingsAnchor("settings.screenGlow")
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
            microphone.reload()
        }
        // The popover's own onDisappear is skipped when the page goes away
        // while it is up; this one keeps the meter from outliving the page.
        .onDisappear { microphone.closed() }
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
