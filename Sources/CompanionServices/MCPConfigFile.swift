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
    /// Bearer tokens live in the Keychain, bound to the server's host (20c
    /// D6, M5). A token still written in the file is moved there on load and
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
        var resolved: [MCPServerConfig] = []
        for server in servers {
            var copy = server
            if let token = server.authorization, !token.isEmpty {
                if let host = SecretHost.of(url: server.url) {
                    do {
                        try secrets.write(.mcpToken, host: host, value: token)
                    } catch {
                        moved = false
                        Log.app("mcp: a token could not move to the keychain; mcp.json left as it was")
                    }
                } else {
                    // Nothing to bind it to, so it is not sent anywhere.
                    moved = false
                    copy.authorization = nil
                    Log.app("mcp: a token has no valid host; left in mcp.json, not used")
                }
            } else if let host = SecretHost.of(url: server.url) {
                do {
                    copy.authorization = try secrets.read(.mcpToken, host: host)
                } catch {
                    Log.app("mcp: keychain read failed for a server token")
                }
            }
            resolved.append(copy)
        }
        if inFile, moved {
            do {
                try write(resolved.map { stripped($0) }, root: root)
            } catch {
                Log.app("mcp: tokens are in the keychain but mcp.json could not be rewritten")
            }
        }
        return resolved
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
    /// hand. Tokens go to the Keychain, bound to the host, and never into
    /// the file: a Keychain that refuses fails the save with the file
    /// untouched, rather than writing a secret in the clear (D6, M5). A
    /// server that left the list takes its token with it, so re-adding that
    /// host later does not silently resurrect it.
    public static func save(
        _ servers: [MCPServerConfig],
        root: URL = MemoryLocation.directory().deletingLastPathComponent(),
        secrets: any HostSecretStore
    ) throws {
        let previous = savedHosts(root: root)
        for server in servers {
            guard let token = server.authorization, !token.isEmpty else { continue }
            guard let host = SecretHost.of(url: server.url) else { throw SecretStoreError.invalidHost }
            try secrets.write(.mcpToken, host: host, value: token)
        }
        try write(servers.map { stripped($0) }, root: root)
        let kept = Set(servers.compactMap { SecretHost.of(url: $0.url) })
        for host in previous.subtracting(kept) {
            try secrets.delete(.mcpToken, host: host)
        }
    }

    /// Hosts the file names now; an absent or broken file names none.
    private static func savedHosts(root: URL) -> Set<String> {
        let data: Data
        do {
            data = try Data(contentsOf: root.appendingPathComponent("mcp.json"))
        } catch {
            return []
        }
        return Set(MCPServerConfig.load(fromJSON: data).compactMap { SecretHost.of(url: $0.url) })
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
