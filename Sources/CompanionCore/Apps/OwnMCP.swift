import Foundation

/// What a read of mcp.json found. Three states on purpose: a broken file
/// must be distinguishable from an absent one, or the next save silently
/// replaces a hand-edited file — tokens included (H1, review 16k-4).
package enum MCPFileRead: Sendable, Equatable {
    case absent
    case servers([MCPServerConfig])
    case unreadable
}

/// 16k-4 "Add it here": the user's own remote MCP servers, edited from the
/// Apps page instead of by hand in mcp.json. The edits are pure list
/// operations; reading and writing the file stays in Services
/// (MCPConfigFile), so the rules are testable without a disk.
package enum OwnMCPEdit {
    package enum EditError: Error, Equatable {
        case emptyName, invalidName, duplicateName, invalidURL
    }

    /// The label reaches OpenAI as `server_label` and the model
    /// instructions verbatim: ascii word characters only, bounded.
    static let labelLimit = 64

    /// Appends a validated server. https only, no embedded credentials:
    /// the config can carry a bearer token, OpenAI reaches the server from
    /// outside this Mac, and userinfo in the URL would travel in clear
    /// without ever showing in the UI (review 16k-4 M3).
    package static func add(
        _ servers: [MCPServerConfig], label: String, url raw: String
    ) -> Result<[MCPServerConfig], EditError> {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.emptyName) }
        guard name.count <= labelLimit,
              name.unicodeScalars.allSatisfy({
                  $0.isASCII && (CharacterSet.alphanumerics.contains($0)
                      || $0 == "-" || $0 == "_")
              })
        else { return .failure(.invalidName) }
        guard !servers.contains(where: { $0.label.lowercased() == name.lowercased() })
        else { return .failure(.duplicateName) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else { return .failure(.invalidURL) }
        // The stored string is the parsed URL, not the raw text: what was
        // validated is what persists.
        return .success(servers + [MCPServerConfig(label: name, url: url.absoluteString)])
    }

    /// Removes by label; an unknown label removes nothing.
    package static func remove(_ servers: [MCPServerConfig], label: String) -> [MCPServerConfig] {
        servers.filter { $0.label != label }
    }

    /// What the row shows next to the name: the server's host, or the raw
    /// string when it does not parse — the error is the display, never a
    /// prettier guess.
    package static func host(of server: MCPServerConfig) -> String {
        URL(string: server.url)?.host ?? server.url
    }
}
