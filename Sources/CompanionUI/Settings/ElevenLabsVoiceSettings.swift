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

    package init(secrets: (any SecretStore)? = nil) {
        self.secrets = secrets
        voiceID = ElevenLabsVoicePreference.voiceID
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
        store(customField)
    }

    private func store(_ id: String) {
        ElevenLabsVoicePreference.voiceID = id
        voiceID = ElevenLabsVoicePreference.voiceID
        errorText = nil
    }
}
