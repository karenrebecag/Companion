import CompanionCore
import Foundation
import Observation
import SwiftUI

/// The idle pebble's visibility, and whether a hold was ever completed.
public enum IslandPreference {
    static let key = "companion.island.pebbleHidden"
    static let learnedKey = "companion.island.holdLearned"

    public static var pebbleHidden: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    public static var holdLearned: Bool {
        get { UserDefaults.standard.bool(forKey: learnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: learnedKey) }
    }
}

/// What Settings and the island share about the hold (Wave 12b): whether
/// the FN tap is allowed to listen, and whether the idle mark shows.
@Observable
@MainActor
public final class HoldSettingsModel {
    public private(set) var granted = false
    /// Main is key: it paints the sheet, the island does not.
    public var mainInFront = false
    public var pebbleHidden: Bool {
        didSet { IslandPreference.pebbleHidden = pebbleHidden }
    }
    /// A hold has produced a turn once: hover stops teaching it (12c).
    public var holdLearned: Bool {
        didSet { IslandPreference.holdLearned = holdLearned }
    }
    /// Called after the user answers the system prompt, so the tap can start.
    public var onPermissionChanged: (() -> Void)?
    private let permission: (any AccessibilityChecking)?

    public init(permission: (any AccessibilityChecking)? = nil) {
        self.permission = permission
        self.pebbleHidden = IslandPreference.pebbleHidden
        self.holdLearned = IslandPreference.holdLearned
        refresh()
    }

    public func refresh() {
        granted = permission?.isTrusted() ?? false
    }

    /// The system prompt, once; after a deny it returns false with no UI,
    /// which is why the row also offers the deep link.
    public func request() {
        guard let permission else { return }
        granted = permission.request()
        onPermissionChanged?()
    }

    public var row: PermissionRowModel {
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
    @State private var screenGlow = ScreenGlowPreference.enabled()
    @State private var context = ContextSettingsModel()

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
                SettingsRow(
                    title: Localized.string("settings.sounds"),
                    subtitle: Localized.string("settings.sounds.subtitle"),
                    key: "settings.sounds"
                ) {
                    SettingsSwitch(label: Localized.string("settings.sounds"), isOn: $sounds)
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
        .onChange(of: sounds) { _, on in
            InterfaceSound.enabled = on
            ThinkingSoundPref.enabled = on
        }
        .onAppear {
            context.accessibility = accessibility
            context.refreshTrust()
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
