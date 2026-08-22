import CompanionCore
import Foundation

/// Every user-facing string in the UI layer, looked up by key. English is the
/// source (en.lproj); Spanish follows it.
///
/// The bundle's own localization follows the system, which is not enough: the
/// app lets the user pick a language, so the lookup goes straight at the
/// matching `.lproj` sub-bundle instead of trusting the process locale.
public enum Localized {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var source: @Sendable () -> AppLanguage = {
        LanguagePreference.current
    }

    /// Test seam and preview seam: the language picker has to show a string
    /// in the language being previewed, not the one in force.
    public static var language: @Sendable () -> AppLanguage {
        get { lock.withLock { source } }
        set { lock.withLock { source = newValue } }
    }

    public static func string(_ key: String) -> String {
        bundle(for: language())?.localizedString(
            forKey: key, value: nil, table: nil)
            ?? fallback(key)
    }

    /// Missing translation must never paint a blank: English is the source,
    /// so it is always the last thing standing before the raw key.
    private static func fallback(_ key: String) -> String {
        bundle(for: .en)?.localizedString(forKey: key, value: nil, table: nil)
            ?? key
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        Bundle.module.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:))
    }
}
