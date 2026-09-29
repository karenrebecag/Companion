import CompanionCore
import Foundation

/// The user's MCP servers, declared in a plain JSON file next to the memory
/// folder — same philosophy: user-owned, readable, editable (9j-3).
///
///   ~/Library/Application Support/Companion/mcp.json
///   [{"label": "docs", "url": "https://developers.openai.com/mcp"}]
///
/// Every call asks. An old `requireApproval` key still loads but is ignored
/// and not written back.
public enum MCPConfigFile {
    /// Bearer tokens live in the Keychain, bound to the server (host, port
    /// and path; 20c D6, M5). A token still written in the file is moved there on load and
    /// the file rewritten without it, only after the Keychain took it; if
    /// the Keychain refuses, the file is left as it was and the token keeps
    /// serving from it for this run (nothing lost, nothing newly plaintext).
    public static func load(
        root: URL = MemoryLocation.directory().deletingLastPathComponent(),
        secrets: any HostSecretStore
    ) -> [MCPServerConfig] {
        let url = root.appendingPathComponent("mcp.json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return []  // no file is the normal empty state
        }
        let servers = MCPServerConfig.load(fromJSON: data)
        if servers.isEmpty, !data.isEmpty {
            Log.app("mcp: mcp.json exists but decoded no servers — check its shape")
        }
        return resolvingTokens(servers, root: root, secrets: secrets)
    }

    private static func resolvingTokens(
        _ servers: [MCPServerConfig], root: URL, secrets: any HostSecretStore
    ) -> [MCPServerConfig] {
        let inFile = servers.contains { !($0.authorization ?? "").isEmpty }
        var moved = inFile
        var migration = HostOnlyMigration()
        var resolved: [MCPServerConfig] = []
        for server in servers {
            var copy = server
            if let token = server.authorization, !token.isEmpty {
                if let key = SecretHost.serverKey(of: server.url) {
                    do {
                        try secrets.write(.mcpToken, host: key, value: token)
                    } catch {
                        moved = false
                        Log.app("mcp: a token could not move to the keychain; mcp.json left as it was")
                    }
                } else {
                    // Nothing safe to bind it to (no host, or not https), so
                    // it is not sent anywhere.
                    moved = false
                    copy.authorization = nil
                    Log.app("mcp: a token has no valid https host; left in mcp.json, not used")
                }
            } else {
                do {
                    copy.authorization = try migration.token(for: server, secrets: secrets)
                } catch {
                    Log.app("mcp: keychain read failed for a server token")
                }
            }
            resolved.append(copy)
        }
        migration.retireServed(secrets: secrets)
        if inFile, moved {
            do {
                try write(resolved.map { stripped($0) }, root: root)
            } catch {
                Log.app("mcp: tokens are in the keychain but mcp.json could not be rewritten")
            }
        }
        return resolved
    }

    /// A server with no token of its own gets the one saved under its name;
    /// else the host-only one from before tokens were bound per server, copied
    /// to the server's name so it is not stranded (a copy the Keychain refuses
    /// still serves this run). One place for `load` and `save`, so neither can
    /// retire a host-only token the other would have kept: a host with a
    /// stuck move keeps its host-only copy, the only one there is.
    private struct HostOnlyMigration {
        private var served = Set<String>()
        private var stuck = Set<String>()

        mutating func token(for server: MCPServerConfig, secrets: any HostSecretStore) throws -> String? {
            guard let key = SecretHost.serverKey(of: server.url),
                  let host = SecretHost.of(url: server.url)
            else { return nil }
            if let own = try secrets.read(.mcpToken, host: key) { return own }
            guard let old = try secrets.read(.mcpToken, host: host) else { return nil }
            served.insert(host)
            do {
                try secrets.write(.mcpToken, host: key, value: old)
            } catch {
                stuck.insert(host)
                Log.app("mcp: a host-only token could not move to its server; kept as it was")
            }
            return old
        }

        func retireServed(secrets: any HostSecretStore) { retire(served, secrets: secrets) }

        /// Dropped once every server of the host has its own copy, so a
        /// server added later on that host does not inherit it. A failed
        /// delete only leaves a host-bound copy that the next load retires.
        func retire(_ hosts: Set<String>, secrets: any HostSecretStore) {
            for host in hosts.subtracting(stuck) {
                do {
                    try secrets.delete(.mcpToken, host: host)
                } catch {
                    Log.app("mcp: a host-only token could not be retired; retried on the next load")
                }
            }
        }
    }

    private static func stripped(_ server: MCPServerConfig) -> MCPServerConfig {
        MCPServerConfig(label: server.label, url: server.url, allowedTools: server.allowedTools)
    }

    /// 16k-4: what the editing UI reads. Unlike `load` — deliberately
    /// tolerant so a session open never crashes on a typo — this read keeps
    /// the difference between "no file" and "broken file": the editor must
    /// refuse to overwrite a file it could not parse (H1, review 16k-4).
    public static func read(
        root: URL = MemoryLocation.directory().deletingLastPathComponent()
    ) -> MCPFileRead {
        let url = root.appendingPathComponent("mcp.json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .absent
        }
        do {
            return .servers(try JSONDecoder().decode([MCPServerConfig].self, from: data))
        } catch {
            return .unreadable
        }
    }

    /// 16k-4: the Apps page edits the same file the user could edit by
    /// hand. Tokens go to the Keychain, bound to the server, and never into
    /// the file: a Keychain that refuses fails the save with the file
    /// untouched, rather than writing a secret in the clear (D6, M5). A
    /// server that left the list takes its token with it, so re-adding it
    /// later does not silently resurrect it.
    ///
    /// A server with no `authorization` keeps the token it has in the
    /// Keychain (`read` hands the editor stripped servers, so nil cannot
    /// mean "clear"). The Apps page has no token field, so nothing there
    /// needs to clear one: removing the server does, and so does hand-editing
    /// a new token into mcp.json, which replaces it on the next load.
    public static func save(
        _ servers: [MCPServerConfig],
        root: URL = MemoryLocation.directory().deletingLastPathComponent(),
        secrets: any HostSecretStore
    ) throws {
        let previous = savedIdentities(root: root)
        var migration = HostOnlyMigration()
        for server in servers {
            let token = server.authorization ?? ""
            guard let key = SecretHost.serverKey(of: server.url),
                  let host = SecretHost.of(url: server.url)
            else {
                if !token.isEmpty { throw SecretStoreError.invalidHost }
                continue
            }
            if token.isEmpty {
                _ = try migration.token(for: server, secrets: secrets)
            } else {
                try secrets.write(.mcpToken, host: key, value: token)
            }
        }
        try write(servers.map { stripped($0) }, root: root)
        let kept = Set(servers.compactMap { SecretHost.serverKey(of: $0.url) })
        for key in Set(previous.keys).subtracting(kept) {
            try secrets.delete(.mcpToken, host: key)
        }
        let hosts = Set(previous.values).union(servers.compactMap {
            SecretHost.serverKey(of: $0.url) == nil ? nil : SecretHost.of(url: $0.url)
        })
        migration.retire(hosts, secrets: secrets)
    }

    /// Server key -> host of what the file names now; an absent or broken
    /// file names none.
    private static func savedIdentities(root: URL) -> [String: String] {
        let data: Data
        do {
            data = try Data(contentsOf: root.appendingPathComponent("mcp.json"))
        } catch {
            return [:]
        }
        var found: [String: String] = [:]
        for server in MCPServerConfig.load(fromJSON: data) {
            if let key = SecretHost.serverKey(of: server.url), let host = SecretHost.of(url: server.url) {
                found[key] = host
            }
        }
        return found
    }

    /// Whole-file replace via a temp file that is 0600 from birth — the
    /// config used to carry a bearer token, and a write-then-chmod would
    /// leave it world-readable for a moment (review 16k-4 M2).
    private static func write(_ servers: [MCPServerConfig], root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(servers)
        let url = root.appendingPathComponent("mcp.json")
        let temp = root.appendingPathComponent(".mcp.json.tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: temp.path, contents: nil,
            attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
        do {
            // An in-place write keeps the 0600 the file was born with.
            try data.write(to: temp)
            _ = try FileManager.default.replaceItemAt(
                url, withItemAt: temp, options: .usingNewMetadataOnly)
        } catch {
            do {
                try FileManager.default.removeItem(at: temp)
            } catch {
                Log.app("mcp: could not clean the temp file after a failed save")
            }
            throw error
        }
    }
}
