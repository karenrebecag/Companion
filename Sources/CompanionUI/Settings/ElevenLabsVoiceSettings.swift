import CompanionCore
import Foundation
import Observation

/// 15f-6: the ElevenLabs voice picked in Settings › Voz. Nothing stored
/// (or a value that no longer validates) reads as Karen's default, so an
/// old or hand-edited default can never reach the URL path.
package enum ElevenLabsVoicePreference {
    nonisolated private static let key = "companion.voice.elevenLabsID"
    /// Swappable so a test writes into its own suite, never the user's.
    nonisolated(unsafe) package static var store: UserDefaults = .standard

    nonisolated package static var voiceID: String {
        get {
            guard let raw = store.string(forKey: key),
                  ElevenLabsMouth.isValidVoiceID(raw)
            else { return Config.defaultElevenLabsVoiceID }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set { store.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key) }
    }
}

/// What the voice cards show as chosen: a preset by voice id, or the Custom
/// card, which stands for any id that is not a preset.
package enum ElevenLabsVoiceChoice: Hashable, Sendable {
    case preset(String)
    case custom
}

/// Wave 15f-6: Settings › Voz, the ElevenLabs voice. Same shape as
/// `KeysSettingsModel`: `secrets` arrives from `.onAppear` and `refresh()`
/// is the only Keychain read, so opening the app never touches it. Only
/// presence is kept; the key itself never lands in view state.
@Observable
@MainActor
package final class ElevenLabsVoiceModel {
    package var secrets: (any SecretStore)?
    package private(set) var hasKey = false
    package private(set) var voiceID: String
    package var customField = ""
    package private(set) var errorText: String?
    /// Choosing Custom opens the field without touching the stored voice.
    package private(set) var customOpen = false

    package init(secrets: (any SecretStore)? = nil) {
        self.secrets = secrets
        voiceID = ElevenLabsVoicePreference.voiceID
        prefillCustomField()
    }

    package var shownChoice: ElevenLabsVoiceChoice {
        customOpen || selectedPreset == nil ? .custom : .preset(voiceID)
    }

    package func choose(_ choice: ElevenLabsVoiceChoice) {
        switch choice {
        case .preset(let id):
            guard let preset = ElevenLabsMouth.presets.first(where: { $0.id == id }) else { return }
            customOpen = false
            select(preset)
        case .custom:
            customOpen = true
        }
    }

    /// A stored custom id shows in the field, so Custom is editable, not
    /// blank. Only init does it: a later refresh would refill a field the
    /// person emptied on purpose.
    private func prefillCustomField() {
        if selectedPreset == nil { customField = voiceID }
    }

    package var selectedPreset: ElevenLabsVoicePreset? {
        ElevenLabsMouth.presets.first { $0.id == voiceID }
    }

    package func refresh() {
        voiceID = ElevenLabsVoicePreference.voiceID
        guard let secrets else {
            hasKey = false
            return
        }
        let value: String?
        do {
            value = try secrets.read(.elevenLabs)
        } catch {
            // A locked Keychain reads as no key: the OpenAI voice is what
            // would speak anyway, which is what the section then says.
            hasKey = false
            return
        }
        hasKey = !(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package func select(_ preset: ElevenLabsVoicePreset) {
        store(preset.id)
    }

    /// Refused ids never persist: the router would read them on the next
    /// sentence and the client would drop every request to OpenAI.
    package func applyCustom() {
        guard ElevenLabsMouth.isValidVoiceID(customField) else {
            errorText = Localized.string("settings.voice.eleven.invalid")
            return
        }
        // The stored voice now decides the card: a preset's own id marks that
        // preset, any other id keeps Custom.
        customOpen = false
        store(customField)
    }

    private func store(_ id: String) {
        ElevenLabsVoicePreference.voiceID = id
        voiceID = ElevenLabsVoicePreference.voiceID
        errorText = nil
    }
}
