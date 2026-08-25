import CompanionCore
import CompanionUI
import Foundation

/// Adapter from persisted UserPreferences to the Config protocol.
/// Reads from UserDefaults each time `current` is accessed, allowing
/// voice preferences to apply without session reconstruction.
final class StoredConfigProvider: ConfigProviding, Sendable {
    private let workdir: String?

    init(workdir: String? = nil) {
        self.workdir = workdir
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
            workdir: WorkdirPreference.validated ?? workdir,
            ownerFirstName: ownerName,
            ownerAbout: UserProfile.about,
            ownerInstructions: UserProfile.instructions,
            language: LanguagePreference.current
        )
    }
}
