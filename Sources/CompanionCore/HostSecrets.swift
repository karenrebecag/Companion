import Foundation

/// What a host-bound secret is for. The raw value is part of the stored
/// name, so it must never contain `@`.
public enum HostSecretKind: String, Sendable, Equatable {
    /// The key the app shows the companion-apps function.
    case appsKey = "apps-key"
    /// A bearer token for one of the user's own MCP servers.
    case mcpToken = "mcp-token"
}

/// Secrets that only make sense for one host (20c D6, M5). The host is part
/// of the key, so a secret saved for host A cannot be read back as host B's:
/// repointing an endpoint or an MCP url elsewhere finds nothing to send.
/// The port is not part of the binding on purpose: a host is the trust unit
/// the user typed in, and a port change is not a new owner.
public protocol HostSecretStore: Sendable {
    func read(_ kind: HostSecretKind, host: String) throws -> String?
    func write(_ kind: HostSecretKind, host: String, value: String) throws
    func delete(_ kind: HostSecretKind, host: String) throws
}

public enum SecretHost {
    /// The lowercased host, or nil when it is empty or holds a character
    /// that would break the stored name.
    public static func normalized(_ raw: String) -> String? {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty,
              !host.contains("@"),
              host.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) })
        else { return nil }
        return host
    }

    /// The host of an absolute URL string, normalized; nil when it has none.
    public static func of(url text: String) -> String? {
        URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host
            .flatMap(normalized)
    }
}

/// The companion-apps key across its two homes: the flat Keychain name it
/// lived under before D6 (`legacy`) and the host-bound one (`bound`).
public enum AppsCredentials {
    /// The key for `host`. A key still under the flat name is moved to the
    /// host on first read (spec R3): written bound first, deleted flat only
    /// after that write held, so a refusing Keychain never costs a working
    /// key. It was saved next to the endpoint now in use, so binding it to
    /// that host is what it always meant.
    public static func key(
        host: String, legacy: any SecretStore, bound: any HostSecretStore
    ) throws -> String? {
        if let found = try bound.read(.appsKey, host: host) { return found }
        guard let old = try legacy.read(.companionApps) else { return nil }
        do {
            try bound.write(.appsKey, host: host, value: old)
        } catch {
            // Still a Keychain-to-Keychain key, not a plaintext fallback:
            // serve it and retry the move on the next read.
            return old
        }
        try legacy.delete(.companionApps)
        return old
    }

    /// Saves the key for `host`, drops the one bound to the endpoint being
    /// replaced (so re-adding that host later cannot resurrect it) and the
    /// flat copy.
    public static func save(
        _ key: String, host: String, previousHost: String?,
        legacy: any SecretStore, bound: any HostSecretStore
    ) throws {
        try bound.write(.appsKey, host: host, value: key)
        if let previousHost, previousHost != host {
            try bound.delete(.appsKey, host: previousHost)
        }
        try legacy.delete(.companionApps)
    }
}
