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
}
