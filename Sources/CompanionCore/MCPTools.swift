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
    /// Guidance injected when a server asks permission (16q-1). The request
    /// is a card on screen with Allow and Deny: the model says so in one
    /// short sentence and keeps the detail off its voice. It never approves:
    /// a spoken yes does not, only the click does; a spoken no may refuse.
    public static func approvalPrompt(
        server: String, tool: String, _ language: AppLanguage
    ) -> String {
        switch language {
        case .en:
            return "The MCP server «\(server)» asks permission to run "
                + "«\(tool)». A card with Allow and Deny is on screen. Tell the "
                + "user in one short sentence that it waits for their click; do "
                + "not read out its details. A spoken yes does not approve it: "
                + "never call resolve_approval with approved true for it. If "
                + "they say no out loud, call resolve_approval with approved false."
        case .es:
            return "El servidor MCP «\(server)» pide permiso para ejecutar "
                + "«\(tool)». Hay una tarjeta en pantalla con Permitir y Rechazar. "
                + "Dile al usuario en una frase corta que espera su clic; no leas "
                + "el detalle. Un sí hablado no la aprueba: nunca llames "
                + "resolve_approval con approved true para ella. Si dice que no "
                + "en voz alta, llama resolve_approval con approved false."
        }
    }
}
