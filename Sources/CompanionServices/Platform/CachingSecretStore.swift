import CompanionCore
import Foundation

/// Remembers what the Keychain answered, so one turn costs one read per key.
///
/// Why this exists: the router asks for a provider's key twice per attempt —
/// once at the guard that skips keyless providers, once when handing it to the
/// request — and voice asks again when a session opens. That was three to five
/// Keychain reads per message. Harmless while the stored item's ACL recognises
/// the app; the moment it does not — a rename, a re-signing — every read is a
/// password dialog, and the user gets one per read instead of one per session.
///
/// The value does live in memory for the life of the process. It already did
/// during every request; what changes is the duration, and that is the trade
/// made knowingly for not asking someone their password three times a message.
///
/// Not cached: failures, because a locked or denied Keychain is usually
/// temporary and remembering the "no" would condemn the whole session. And a
/// key changed by another app (Keychain Access) is not seen until relaunch —
/// the price of the cache, small enough to name and move on.
package final class CachingSecretStore: SecretStore, @unchecked Sendable {
    private let inner: any SecretStore
    private let lock = NSLock()
    /// Two levels of optional on purpose: no entry means "never asked",
    /// an entry holding nil means "asked, and there is none" — which is the
    /// common case for someone running on the local base and must not cost a
    /// Keychain round trip every message.
    private var cache: [SecretKey: String?] = [:]

    package init(_ inner: any SecretStore) {
        self.inner = inner
    }

    package func read(_ key: SecretKey) throws -> String? {
        if let cached = cached(key) { return cached }
        let value = try inner.read(key)
        remember(key, value)
        return value
    }

    package func write(_ key: SecretKey, value: String) throws {
        try inner.write(key, value: value)
        forget(key)
    }

    package func delete(_ key: SecretKey) throws {
        try inner.delete(key)
        forget(key)
    }

    /// Drops everything. For a settings screen that lets keys be edited
    /// outside the two methods above.
    package func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    private func cached(_ key: SecretKey) -> String?? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private func remember(_ key: SecretKey, _ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = value
    }

    private func forget(_ key: SecretKey) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }
}
