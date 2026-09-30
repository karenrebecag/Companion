import CompanionCore
import Foundation
import Security

/// Keys in the login keychain — the file-based one, which is what `SecItem`
/// targets on macOS unless asked otherwise.
///
/// HACK: this is the legacy keychain, and it is a deliberate choice, not an
/// oversight. The modern data-protection keychain would end the password
/// dialogs for good (its access is bound to the app's identity rather than to
/// an ACL that a re-signing invalidates), but reaching it needs
/// `kSecUseDataProtectionKeychain` together with an `application-identifier`
/// entitlement, and that needs a Team ID this project does not have yet.
/// Upgrade trigger: the day the Apple Developer account exists, move to the
/// data-protection keychain and delete this note.
///
/// Every secret now lives in ONE generic-password item instead of one per
/// key: the self-signed dev cert makes every rebuild a new binary in the
/// ACL's eyes, so each item asked for the login password again on first
/// touch. One item means one dialog per launch, not one per key. The item's
/// data is a JSON object of `SecretKey.rawValue -> value`, decoded once and
/// cached for the process — see `loadedBundle()`.
///
/// What was removed, and why it mattered: this used to set
/// `kSecAttrAccessible` and `kSecAttrSynchronizable: false` under a comment
/// promising "survive lock, never leave this Mac". Apple documents
/// `kSecAttrAccessible` as irrelevant to the file-based keychain, so the
/// attribute did nothing and the promise was not the code's to make. The
/// no-sync half happens to hold — the file keychain does not sync — but by
/// accident, not by that flag. A security comment that overstates is worse
/// than none: it stops the next person from checking.
package final class KeychainSecretStore: SecretStore, HostSecretStore, @unchecked Sendable {
    package static let service = "Companion"

    /// Account for the single bundle item. Versioned so a future shape
    /// change can migrate forward instead of guessing what an old blob is.
    static let bundleAccount = "secrets.v1"

    /// Where every key used to live: one item per `SecretKey.rawValue`. Not
    /// `SecretKey.CaseIterable` — `SecretKey` stays untouched in Core — so
    /// this is Services' own copy of "every account that ever held a secret
    /// on its own", read once during migration and never written to again.
    private static let legacyKeys: [SecretKey] = [.openAI, .openRouter, .brave]

    /// 15e-2: keys of providers the app no longer talks to. Ajustes has no
    /// row left to delete them, so a secret saved before its provider was
    /// removed would otherwise sit in the Keychain forever: it is never
    /// migrated, and the first load of each launch drops it.
    private static let retiredKeys: [SecretKey] = [.groq]

    private let backend: any KeychainOperations
    private let lock = NSLock()
    /// The decoded bundle, kept for the process lifetime once loaded. `nil`
    /// means "not loaded yet", not "empty" — an empty bundle is a valid,
    /// cacheable answer once it has actually been fetched.
    private var cache: [String: String]?

    package convenience init() {
        self.init(backend: LiveKeychainOperations())
    }

    /// Test seam: the real store never calls this directly.
    init(backend: any KeychainOperations) {
        self.backend = backend
    }

    package func read(_ key: SecretKey) throws -> String? {
        try readEntry(key.rawValue)
    }

    package func write(_ key: SecretKey, value: String) throws {
        try writeEntry(key.rawValue, value: value)
    }

    package func delete(_ key: SecretKey) throws {
        try deleteEntry(key.rawValue)
    }

    // MARK: - Host-bound secrets (20c D6, M5)

    /// The bundle entry name carries the host, so the same item holds them
    /// (one dialog per launch) and a read for another host cannot match.
    private static func hostEntry(_ kind: HostSecretKind, _ host: String) throws -> String {
        guard let normalized = SecretHost.normalized(host) else { throw SecretStoreError.invalidHost }
        return "\(kind.rawValue)@\(normalized)"
    }

    private func readEntry(_ name: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try lockedBundle()[name]
    }

    private func writeEntry(_ name: String, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SecretStoreError.emptyValue }

        lock.lock()
        defer { lock.unlock() }
        var bundle = try lockedBundle()
        bundle[name] = trimmed
        try lockedPersist(bundle)
    }

    private func deleteEntry(_ name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var bundle = try lockedBundle()
        guard bundle.removeValue(forKey: name) != nil else { return }
        try lockedPersist(bundle)
    }

    package func read(_ kind: HostSecretKind, host: String) throws -> String? {
        try readEntry(Self.hostEntry(kind, host))
    }

    package func write(_ kind: HostSecretKind, host: String, value: String) throws {
        try writeEntry(Self.hostEntry(kind, host), value: value)
    }

    package func delete(_ kind: HostSecretKind, host: String) throws {
        try deleteEntry(Self.hostEntry(kind, host))
    }

    // MARK: - Bundle cache

    /// Every public entry point takes `lock` once and holds it for its
    /// entire load -> mutate -> persist sequence (including the first-load
    /// migration), so two callers can never both snapshot the same stale
    /// bundle and have the later persist silently drop the earlier write.
    /// Assumes the lock is already held — never call this or `lockedPersist`
    /// without it, and never take the lock again inside them (NSLock is not
    /// recursive).
    private func lockedBundle() throws -> [String: String] {
        if let cache { return cache }
        let bundle = try fetchOrMigrateBundle()
        cache = bundle
        return bundle
    }

    private func lockedPersist(_ bundle: [String: String]) throws {
        try writeBundleItem(bundle)
        cache = bundle
    }

    /// Loads the bundle item if it exists; otherwise migrates whatever
    /// legacy per-key items are found. A bundle that exists but fails to
    /// decode is corruption, not absence — it must throw, never be treated
    /// as "nothing here yet" and silently replaced.
    private func fetchOrMigrateBundle() throws -> [String: String] {
        guard let data = try readItem(account: Self.bundleAccount) else {
            return try migrateLegacyItems()
        }
        let bundle: [String: String]
        do {
            bundle = try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            // Never overwrite: a corrupt bundle is a diagnosis job for a
            // person, not something this code guesses its way out of.
            throw SecretStoreError.unexpected(-1)
        }
        // Security review 2026-09-24 (bajo): a retired standalone item can sit
        // beside a bundle too; the load is cached, so this runs once.
        deleteRetiredLegacyItems()
        return purgingRetiredKeys(bundle)
    }

    /// A failed rewrite must not cost the keys that are still in use: the
    /// purged bundle is served either way and the next launch tries again.
    private func purgingRetiredKeys(_ bundle: [String: String]) -> [String: String] {
        let retired = Set(Self.retiredKeys.map(\.rawValue))
        let kept = bundle.filter { !retired.contains($0.key) }
        guard kept.count != bundle.count else { return bundle }
        do {
            try writeBundleItem(kept)
        } catch {
            Log.app("keychain: retired key purge failed to persist, retrying next launch")
        }
        return kept
    }

    /// Reads every legacy item found, writes them as one bundle, and only
    /// once that write succeeds deletes the legacy items — so a failed
    /// bundle write leaves the legacy data exactly where it was.
    private func migrateLegacyItems() throws -> [String: String] {
        var migrated: [String: String] = [:]
        for key in Self.legacyKeys {
            guard let data = try readItem(account: key.rawValue) else { continue }
            guard let value = String(data: data, encoding: .utf8) else {
                throw SecretStoreError.unexpected(-2)
            }
            migrated[key.rawValue] = value
        }
        deleteRetiredLegacyItems()
        guard !migrated.isEmpty else { return [:] }

        try writeBundleItem(migrated)
        // The bundle write above is what makes migration real — a legacy
        // item that then refuses to delete is stale leftover data, not a
        // reason to lose the migrated bundle or leave its siblings behind.
        var undeletedCount = 0
        for key in Self.legacyKeys where migrated[key.rawValue] != nil {
            do {
                try deleteItem(account: key.rawValue)
            } catch {
                undeletedCount += 1
            }
        }
        if undeletedCount > 0 {
            Log.app("keychain: \(undeletedCount) legacy item(s) failed to delete after bundle write")
        }
        return migrated
    }

    /// Nothing to preserve in a retired item, so unlike the migrated ones it
    /// does not wait for a bundle write; a refusal only leaves it for the
    /// next launch.
    private func deleteRetiredLegacyItems() {
        for key in Self.retiredKeys {
            do {
                try deleteItem(account: key.rawValue)
            } catch {
                Log.app("keychain: a retired legacy item failed to delete")
            }
        }
    }

    private func writeBundleItem(_ bundle: [String: String]) throws {
        let data = try JSONEncoder().encode(bundle)
        try upsertItem(account: Self.bundleAccount, data: data)
    }

    // MARK: - Single-item keychain calls

    private func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readItem(account: String) throws -> Data? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let (status, data) = backend.copyItemData(query: query)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data else {
            throw SecretStoreError.unexpected(Int(status))
        }
        return data
    }

    private func upsertItem(account: String, data: Data) throws {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = backend.updateItem(query: query, attributesToUpdate: attributes)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound {
            try Self.check(updated)
            return
        }

        var add = query
        add[kSecValueData as String] = data
        try Self.check(backend.addItem(attributes: add))
    }

    private func deleteItem(account: String) throws {
        let status = backend.deleteItem(query: baseQuery(for: account))
        if status == errSecItemNotFound { return }
        try Self.check(status)
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw SecretStoreError.denied
        case errSecNotAvailable:
            throw SecretStoreError.notAvailable
        default:
            throw SecretStoreError.unexpected(Int(status))
        }
    }
}
