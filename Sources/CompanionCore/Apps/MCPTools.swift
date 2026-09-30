import Foundation

/// A remote MCP server attached to the realtime session (9j-3). OpenAI's
/// server connects to it and EXECUTES its tools server-side — the client only
/// declares the server and answers approvals. Remote HTTP only; local stdio
/// servers are not reachable from OpenAI's side.
package struct MCPServerConfig: Sendable, Equatable, Codable {
    package var label: String
    package var url: String
    package var allowedTools: [String]?
    /// Bearer token for servers that need one. At rest it lives in the
    /// Keychain bound to the server's host (20c D6); mcp.json only carries
    /// one a person just typed in, until the next load moves it.
    package var authorization: String?

    /// An old file's `requireApproval` key is ignored on load and never
    /// written back: every call asks, the file cannot relax it (20c D2).
    package init(label: String, url: String, allowedTools: [String]? = nil,
                authorization: String? = nil) {
        self.label = label
        self.url = url
        self.allowedTools = allowedTools
        self.authorization = authorization
    }

    /// Tolerant decode: a malformed file yields no servers, never a crash.
    package static func load(fromJSON data: Data) -> [MCPServerConfig] {
        do {
            return try JSONDecoder().decode([MCPServerConfig].self, from: data)
        } catch {
            return []
        }
    }

    package func realtimeObject() -> [String: Any] {
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
    /// Guidance injected when a server asks permission (16q-1). The request
    /// is a card on screen with Allow and Deny: the model says so in one
    /// short sentence and keeps the detail off its voice. It never approves:
    /// a spoken yes does not, only the click does; a spoken no may refuse.
    package static func approvalPrompt(
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
