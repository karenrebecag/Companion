import CompanionCore
import Foundation

/// The user's MCP servers, declared in a plain JSON file next to the memory
/// folder — same philosophy: user-owned, readable, editable (9j-3).
///
///   ~/Library/Application Support/Companion/mcp.json
///   [{"label": "docs", "url": "https://developers.openai.com/mcp",
///     "requireApproval": "always"}]
public enum MCPConfigFile {
    public static func load(
        root: URL = MemoryLocation.directory().deletingLastPathComponent()
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
        return servers
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
    /// hand. Whole-file replace via a temp file that is 0600 from birth —
    /// the config can carry a bearer token, and a write-then-chmod would
    /// leave it world-readable for a moment (review 16k-4 M2).
    public static func save(
        _ servers: [MCPServerConfig],
        root: URL = MemoryLocation.directory().deletingLastPathComponent()
    ) throws {
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
