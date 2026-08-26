import Foundation

/// A remote MCP server attached to the realtime session (9j-3). OpenAI's
/// server connects to it and EXECUTES its tools server-side — the client only
/// declares the server and answers approvals. Remote HTTP only; local stdio
/// servers are not reachable from OpenAI's side.
public struct MCPServerConfig: Sendable, Equatable, Codable {
    public var label: String
    public var url: String
    public var allowedTools: [String]?
    /// "always" (default — this product asks before acting on the world) or
    /// "never" for servers the user explicitly trusts in the config file.
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
            "require_approval": requireApproval ?? "always",
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
                + "«\(tool)». Ask the user out loud; when they answer, call "
                + "resolve_approval with their decision."
        case .es:
            return "El servidor MCP «\(server)» pide permiso para ejecutar "
                + "«\(tool)». Pregunta al usuario en voz alta; cuando "
                + "responda, llama resolve_approval con su decisión."
        }
    }
}
