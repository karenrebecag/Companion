import CompanionCore
import Foundation

/// Every user-facing string in the UI layer, looked up by key. English is the
/// source (en.lproj); Spanish follows it.
///
/// The bundle's own localization follows the system, which is not enough: the
/// app lets the user pick a language, so the lookup goes straight at the
/// matching `.lproj` sub-bundle instead of trusting the process locale.
package enum Localized {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var source: @Sendable () -> AppLanguage = {
        LanguagePreference.current
    }

    /// `@Sendable () -> AppLanguage` closures aren't `Sendable`-conforming as
    /// a `TaskLocal` value on their own here because the box needs to carry
    /// one; same `@unchecked` shape `Log`'s sink and `ProviderPreference`'s
    /// store already use.
    private struct Pin: @unchecked Sendable {
        let source: @Sendable () -> AppLanguage
    }

    /// Debugging 2026-09-28: Swift Testing runs `@Test` functions in
    /// parallel by default, and ~20 files assign `Localized.language`
    /// (directly or via `pinLanguage`) to pick which catalog their
    /// assertions read. A shared global let one dispatcher's assignment
    /// land mid-turn in another — confirmed live, JobNarrationTests.swift:108
    /// flaked reading Spanish copy that `jobNarrationTests()` never asked
    /// for. Same seam `Log.capturing`/`ProviderPreference.scoped` already
    /// use. Production/preview code never calls `scoped`, so it keeps
    /// reading the process-wide `source` below, unchanged.
    nonisolated private static let override = TaskLocal<Pin?>(wrappedValue: nil)

    /// Test seam and preview seam: the language picker has to show a string
    /// in the language being previewed, not the one in force. Reads prefer
    /// this task's `scoped` pin; previews and any caller outside a `scoped`
    /// block still see the one process-wide default.
    package static var language: @Sendable () -> AppLanguage {
        get { override.get()?.source ?? lock.withLock { source } }
        set { lock.withLock { source = newValue } }
    }

    /// Binds `language` for this task tree only (including non-detached
    /// `Task`s it spawns) — the isolation `pinLanguage(_:_:)` and every
    /// direct `Localized.language = { … }` test call site route through.
    package static func scoped<R>(
        to language: AppLanguage,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> R
    ) async rethrows -> R {
        try await override.withValue(
            Pin(source: { language }), operation: body, isolation: isolation)
    }

    package static func string(_ key: String) -> String {
        string(key, language: language())
    }

    /// For callers that already hold the language they must speak (the
    /// language picker preview, pure copy functions taking a parameter).
    package static func string(_ key: String, language: AppLanguage) -> String {
        bundle(for: language)?.localizedString(
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
