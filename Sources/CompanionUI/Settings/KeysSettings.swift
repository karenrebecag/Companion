import CompanionCore
import Foundation
import Observation

/// Wave 15c-6: Ajustes → Claves. §8 forbids reading the Keychain at boot —
/// `secrets` arrives after init (the `ContextSettingsModel` pattern: an
/// optional dependency set from `.onAppear`) and `refresh()` is the only
/// thing that reads presence, called from the pane's own `.onAppear`. The
/// pasted value never round-trips back into view state: a save clears the
/// field and only a mask survives.
@Observable
@MainActor
package final class KeysSettingsModel {
    package enum Provider: Sendable, Equatable, Hashable, CaseIterable {
        case openAI, cerebras, elevenLabs

        var secretKey: SecretKey {
            switch self {
            case .openAI: .openAI
            case .cerebras: .cerebras
            case .elevenLabs: .elevenLabs
            }
        }
    }

    package var secrets: (any SecretStore)?
    package var openAIField = ""
    package var cerebrasField = ""
    package var elevenLabsField = ""
    /// 15c-7: a blank field after saving read as "nothing happened" (Karen);
    /// the row shows which key is in without ever holding the key itself.
    package private(set) var masked: [Provider: String] = [:]
    package var errorText: String?

    package var openAISaved: Bool { masked[.openAI] != nil }
    package var cerebrasSaved: Bool { masked[.cerebras] != nil }
    package var elevenLabsSaved: Bool { masked[.elevenLabs] != nil }

    package init(secrets: (any SecretStore)? = nil) {
        self.secrets = secrets
    }

    /// Never more than the first and last four characters, and nothing at
    /// all for a key too short to hide its middle.
    package static func mask(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return "••••" }
        return "\(trimmed.prefix(4))••••\(trimmed.suffix(4))"
    }

    package func refresh() {
        var next: [Provider: String] = [:]
        for provider in Provider.allCases {
            if let value = storedValue(provider.secretKey) {
                next[provider] = Self.mask(value)
            }
        }
        masked = next
    }

    package func save(_ provider: Provider) {
        guard let secrets else { return }
        let trimmed = field(provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorText = Localized.string("settings.keys.empty")
            return
        }
        do {
            try secrets.write(provider.secretKey, value: trimmed)
        } catch {
            errorText = Localized.string("settings.keys.error")
            return
        }
        errorText = nil
        setField(provider, "")
        masked[provider] = Self.mask(trimmed)
    }

    package func delete(_ provider: Provider) {
        guard let secrets else { return }
        do {
            // A key that was never written deletes without throwing, so
            // anything thrown here is a Keychain that kept the key.
            try secrets.delete(provider.secretKey)
        } catch {
            errorText = Localized.string("settings.keys.delete.error")
            return
        }
        errorText = nil
        setField(provider, "")
        masked[provider] = nil
    }

    private func field(_ provider: Provider) -> String {
        switch provider {
        case .openAI: openAIField
        case .cerebras: cerebrasField
        case .elevenLabs: elevenLabsField
        }
    }

    private func setField(_ provider: Provider, _ value: String) {
        switch provider {
        case .openAI: openAIField = value
        case .cerebras: cerebrasField = value
        case .elevenLabs: elevenLabsField = value
        }
    }

    private func storedValue(_ key: SecretKey) -> String? {
        guard let secrets else { return nil }
        let value: String?
        do {
            value = try secrets.read(key)
        } catch {
            return nil
        }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
