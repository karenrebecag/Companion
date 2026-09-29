import Foundation

/// A remote MCP server attached to the realtime session (9j-3). OpenAI's
/// server connects to it and EXECUTES its tools server-side — the client only
/// declares the server and answers approvals. Remote HTTP only; local stdio
/// servers are not reachable from OpenAI's side.
public struct MCPServerConfig: Sendable, Equatable, Codable {
    public var label: String
    public var url: String
    public var allowedTools: [String]?
    /// Still decoded so an old file loads, but ignored on the wire: every
    /// call asks (Wave 20c D2).
    public var requireApproval: String?
    /// Bearer token for servers that need one. Lives in the user's 0600
    /// config file. Upgrade trigger: move to the Keychain the day a stored
    /// token is worth stealing.
    public var authorization: String?

    public init(label: String, url: String, allowedTools: [String]? = nil,
                requireApproval: String? = nil, authorization: String? = nil) {
        self.label = label
        self.url = url
        self.allowedTools = allowedTools
        self.requireApproval = requireApproval
        self.authorization = authorization
    }

    /// Tolerant decode: a malformed file yields no servers, never a crash.
    public static func load(fromJSON data: Data) -> [MCPServerConfig] {
        do {
            return try JSONDecoder().decode([MCPServerConfig].self, from: data)
        } catch {
            return []
        }
    }

    public func realtimeObject() -> [String: Any] {
        var obj: [String: Any] = [
            "type": "mcp",
            "server_label": label,
            "server_url": url,
            // Fixed: a "never" in the file would let the server run tools
            // with no sheet, and the user's click is the only approval (20c D2).
            "require_approval": "always",
        ]
        if let allowedTools { obj["allowed_tools"] = allowedTools }
        if let authorization { obj["authorization"] = authorization }
        return obj
    }
}

extension MCPServerConfig {
    /// Guidance injected when servers are configured, so the model knows the
    /// approval dance: ask the user out loud, then resolve.
    public static func approvalPrompt(
        server: String, tool: String, _ language: AppLanguage
    ) -> String {
        switch language {
        case .en:
            return "The MCP server «\(server)» asks permission to run "
                + "«\(tool)». An approval sheet is on screen: tell the user "
                + "what it will do and to answer with the sheet. Do NOT call "
                + "resolve_approval; their click decides."
        case .es:
            return "El servidor MCP «\(server)» pide permiso para ejecutar "
                + "«\(tool)». Hay una hoja de aprobación en pantalla: dile al "
                + "usuario qué hará y que responda en la hoja. NO llames "
                + "resolve_approval; su clic decide."
        }
    }
}
