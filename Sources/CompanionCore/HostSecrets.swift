import Foundation

/// What a host-bound secret is for. The raw value is part of the stored
/// name, so it must never contain `@`.
public enum HostSecretKind: String, Sendable, Equatable {
    /// The key the app shows the companion-apps function.
    case appsKey = "apps-key"
    /// A bearer token for one of the user's own MCP servers.
    case mcpToken = "mcp-token"
    /// Which host the pre-D6 flat apps key was configured for.
    case appsKeyOrigin = "apps-key-origin"
}

/// Secrets that only make sense for one host (20c D6, M5). The host is part
/// of the key, so a secret saved for host A cannot be read back as host B's:
/// repointing an endpoint or an MCP url elsewhere finds nothing to send.
/// The apps key and its origin marker are bound to the host alone, on
/// purpose: a host is the trust unit the user typed in, and a port change is
/// not a new owner. An MCP token is finer: its name is the server key (host,
/// port and path), see `SecretHost.serverKey`.
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

    /// The identity of one MCP server: host, port and path, so two servers
    /// on the same host keep separate tokens. Always holds a `/`, so it can
    /// never equal a host-only name from before the per-server binding.
    /// Only https has one: a bearer token must never ride plain http, and
    /// the scheme is not in the name, so `http://h/p` would otherwise be
    /// served the token saved for `https://h/p`.
    /// The query is left out on purpose: it can carry credentials, and a
    /// stored name is not the place for them. Like the host, the Keychain
    /// lowercases it, so paths that differ only by case share a token.
    /// Fails closed on anything Foundation and a WHATWG parser (the fetcher's)
    /// can read as two different hosts: a backslash, userinfo, or an encoded
    /// or slash-bearing host. Such a URL has no key, so no token.
    public static func serverKey(of url: String) -> String? {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // A WHATWG parser reads `\` as `/`, Foundation does not: two hosts.
        guard !text.contains("\\"),
              let parts = URLComponents(string: text),
              // Only https: a bearer token never rides plain http.
              parts.scheme?.lowercased() == "https",
              // `https://good@evil/` names evil to one parser, good to another.
              parts.user == nil, parts.password == nil,
              let decoded = parts.host, let encoded = parts.percentEncodedHost,
              // An escaped host (`%2F`, `%40`) that one parser decodes and
              // the other keeps literal; the `%` and `/` checks are
              // defensive for a form that survives the equality.
              decoded == encoded, !decoded.contains("%"), !decoded.contains("/"),
              let host = normalized(decoded)
        else { return nil }
        let port = parts.port.map { ":\($0)" } ?? ""
        var path = parts.percentEncodedPath
        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        return normalized("\(host)\(port)/\(path.replacingOccurrences(of: "@", with: "%40"))")
    }
}

/// The apps endpoint host this launch saw, kept in memory only. The flat key
/// is bound to it and to no other host, so an endpoint rewritten after
/// launch (or while the Keychain was unreadable) is never handed the key.
public struct AppsLaunchPin: Sendable, Equatable {
    public let host: String?

    public static let unobserved = AppsLaunchPin(host: nil)

    public static func observed(_ host: String) -> AppsLaunchPin { AppsLaunchPin(host: host) }
}

/// The companion-apps key across its two homes: the flat Keychain name it
/// lived under before D6 (`legacy`) and the host-bound one (`bound`).
///
/// The endpoint lives in UserDefaults, which any process of the same user can
/// rewrite, so the flat key is never allowed to follow the endpoint: it is
/// bound at launch to the host it was configured for, that host is recorded
/// (`originSlot`), and a flat copy that outlives the move is only ever served
/// to the recorded host. When nothing is recorded yet (the Keychain refused
/// the record or could not be read) the key is served only to the host the
/// launch itself observed (`AppsLaunchPin`), never to one that appeared later.
/// HACK: a swap between the app update and its first launch cannot be told
/// from the user's own setting, because the flat key never recorded a host.
/// Upgrade trigger: drop the flat path once no install can still hold one.
///
/// Core has no logger, so the non-fatal failures are reported through `log`;
/// every production caller passes the app's log, the default is for tests.
public enum AppsCredentials {
    /// Where the origin marker lives: `HostSecretStore` reads by kind and
    /// host, and there is one flat key, so one fixed slot holds its host.
    public static let originSlot = "flat"

    /// The key for `host`. A key still under the flat name is moved to the
    /// host (spec R3): written bound first, deleted flat only after that
    /// write held, so a refusing Keychain never costs a working key. A flat
    /// copy that could not be deleted is retried on every read here. With no
    /// recorded origin the flat key only goes to the host `pin` observed.
    public static func key(
        host: String, legacy: any SecretStore, bound: any HostSecretStore, pin: AppsLaunchPin,
        log: @Sendable (String) -> Void = { _ in }
    ) throws -> String? {
        if let found = try bound.read(.appsKey, host: host) {
            retireFlatIfBound(host: host, legacy: legacy, bound: bound, pin: pin, log: log)
            return found
        }
        guard let old = try legacy.read(.companionApps) else { return nil }
        let recorded = try bound.read(.appsKeyOrigin, host: originSlot)
        // Configured for another host: it is not this endpoint's key.
        if let recorded, recorded != host { return nil }
        if recorded == nil, pin.host != host { return nil }
        bind(old, to: host, recorded: recorded != nil, legacy: legacy, bound: bound, log: log)
        return old
    }

    /// Read-time entry for every caller: the endpoint as stored, validated,
    /// its host, and the key for it under the launch pin. One path, so a
    /// caller cannot skip the pin or the log. Nil when the endpoint is unset
    /// or invalid; the key is nil when none is stored. A Keychain failure
    /// throws, so callers can tell it from "not configured".
    public static func currentKey(
        endpoint: String?, legacy: any SecretStore, bound: any HostSecretStore, pin: AppsLaunchPin,
        log: @Sendable (String) -> Void = { _ in }
    ) throws -> (url: URL, key: String?)? {
        guard let url = endpoint.flatMap(AppsEndpoint.validated),
              let host = SecretHost.of(url: url.absoluteString) else { return nil }
        return (url, try key(host: host, legacy: legacy, bound: bound, pin: pin, log: log))
    }

    /// The launch step: the endpoint as the user typed it, validated like the
    /// runner does, and the flat key moved to it before anything can rewrite
    /// the endpoint. The pin it returns is what `key` checks later.
    public static func launch(
        endpoint: String?, legacy: any SecretStore, bound: any HostSecretStore,
        log: @Sendable (String) -> Void = { _ in }
    ) -> AppsLaunchPin {
        let host = endpoint.flatMap(AppsEndpoint.validated).flatMap { SecretHost.of(url: $0.absoluteString) }
        migrateFlatKey(configuredHost: host, legacy: legacy, bound: bound, log: log)
        return host.map(AppsLaunchPin.observed) ?? .unobserved
    }

    /// Launch-time move of the flat key to the host it was configured for,
    /// so no read path has to do it. Skipped when there is no endpoint to
    /// bind to; a host recorded by an earlier attempt wins over the current
    /// endpoint, which may have been rewritten since.
    public static func migrateFlatKey(
        configuredHost: String?, legacy: any SecretStore, bound: any HostSecretStore,
        log: @Sendable (String) -> Void = { _ in }
    ) {
        do {
            guard let old = try legacy.read(.companionApps) else { return }
            let recorded = try bound.read(.appsKeyOrigin, host: originSlot)
            guard let host = recorded ?? configuredHost else { return }
            bind(old, to: host, recorded: recorded != nil, legacy: legacy, bound: bound, log: log)
        } catch {
            log("apps: the flat key could not be inspected; left as it was")
        }
    }

    /// Records the host, writes the bound key and only then retires the flat
    /// copy. A key already bound to that host is newer than the flat one and
    /// stays.
    private static func bind(
        _ old: String, to host: String, recorded: Bool,
        legacy: any SecretStore, bound: any HostSecretStore, log: @Sendable (String) -> Void
    ) {
        do {
            if !recorded { try bound.write(.appsKeyOrigin, host: originSlot, value: host) }
            if try bound.read(.appsKey, host: host) == nil {
                try bound.write(.appsKey, host: host, value: old)
            }
        } catch {
            log("apps: the flat key could not move to its host; kept and retried")
            return
        }
        retireFlat(legacy, log: log)
    }

    /// A bound hit for `host` retires the flat copy only when that copy is
    /// not the sole one of another host's key: its recorded origin must have
    /// its own bound copy, or be absent or this host. With no recorded origin
    /// the flat key belongs to the launch host, so only that host retires it.
    private static func retireFlatIfBound(
        host: String, legacy: any SecretStore, bound: any HostSecretStore, pin: AppsLaunchPin,
        log: @Sendable (String) -> Void
    ) {
        do {
            let recorded = try bound.read(.appsKeyOrigin, host: originSlot)
            if let recorded, recorded != host, try bound.read(.appsKey, host: recorded) == nil { return }
            if recorded == nil, let launch = pin.host, launch != host { return }
        } catch {
            log("apps: the flat key's origin could not be read; kept and retried")
            return
        }
        retireFlat(legacy, log: log)
    }

    private static func retireFlat(_ legacy: any SecretStore, log: @Sendable (String) -> Void) {
        do {
            if try legacy.read(.companionApps) != nil { try legacy.delete(.companionApps) }
        } catch {
            log("apps: the flat key could not be deleted; retried on the next read")
        }
    }

    /// Saves the key for `host`. The flat copy and the key of the endpoint
    /// being replaced go after the new one is safe, and neither failing
    /// undoes it: a save never destroys a working key. A flat copy that
    /// stays is pinned to `host`, so it cannot follow a later endpoint swap.
    public static func save(
        _ key: String, host: String, previousHost: String?,
        legacy: any SecretStore, bound: any HostSecretStore,
        log: @Sendable (String) -> Void = { _ in }
    ) throws {
        try bound.write(.appsKey, host: host, value: key)
        do {
            try legacy.delete(.companionApps)
        } catch {
            log("apps: the flat key could not be deleted on save; pinned to the new host")
            do {
                try bound.write(.appsKeyOrigin, host: originSlot, value: host)
            } catch {
                log("apps: the flat key could not be pinned; retried on the next read")
            }
        }
        if let previousHost, previousHost != host {
            do {
                try bound.delete(.appsKey, host: previousHost)
            } catch {
                log("apps: the previous host's key could not be deleted; still bound to that host")
            }
        }
    }
}
