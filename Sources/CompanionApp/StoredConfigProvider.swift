import CompanionCore
import CompanionServices
import CompanionUI
import Foundation

/// Adapter from persisted UserPreferences to the Config protocol.
/// Reads from UserDefaults each time `current` is accessed, allowing
/// voice preferences to apply without session reconstruction.
final class StoredConfigProvider: ConfigProviding, Sendable {
    private let workdir: String?
    /// 9j-2: memory is read per access, like the profile — a note written at
    /// the close of one session reaches the very next message. Files are
    /// tiny; the read costs less than a network hop.
    private let memory: (any MemoryStore)?

    init(workdir: String? = nil, memory: (any MemoryStore)? = nil) {
        self.workdir = workdir
        self.memory = memory
    }

    var current: Config {
        let ownerName = UserProfile.ownerName.isEmpty
            ? NSFullUserName()
                .split(separator: " ").first.map(String.init) ?? ""
            : UserProfile.ownerName

        return Config(
            // Was `.default`, which pinned the preference to nil no matter
            // what the user chose: the field existed and never arrived.
            chat: ChatSettings(providerOrder: ProviderPreference.order),
            voice: VoiceProfile.settings,
            executors: [ExecutorCatalog.native],
            // No chosen folder means full reach (the home tree), not the
            // native fallback: the specialist gets its whole toolbox, like the
            // CLI. A folder the user picked still narrows it.
            workdir: workdir ?? WorkdirPreference.effective,
            ownerFirstName: ownerName,
            ownerAbout: UserProfile.about,
            ownerInstructions: UserProfile.instructions,
            language: LanguagePreference.current,
            memory: memory.map {
                MemoryPrompt.inject($0.load(), language: LanguagePreference.current)
            } ?? "",
            mcpServers: MCPConfigFile.load()
        )
    }
}
