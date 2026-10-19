import CompanionCore
import Foundation

/// The user's own MCP server over Streamable HTTP: JSON-RPC 2.0 in a POST,
/// answered as JSON or as one SSE event. Stateless on purpose: every
/// operation starts with initialize, so a server that dropped its session
/// costs one extra round trip and never serves a stale tool list. HTTPS only,
/// because the bearer token rides in the Authorization header.
package struct OwnMCPClient: Sendable {
    package enum Failure: Error, Equatable {
        case insecureURL, unreachable, badAnswer
    }

    static let protocolVersion = "2025-06-18"
    static let timeout: TimeInterval = 20
    /// Same ceiling as the connected apps' function: a catalog this big is not
    /// a tool list, and parsing it would stall the turn.
    static let maxBody = 1024 * 1024
    static let maxPages = 5

    private let transport: any ChatTransport

    /// The transport carries the redirect policy, so a redirect to another host
    /// never receives the token (same rule as HTTPAppsService).
    package init(transport: any ChatTransport = URLSessionChatTransport()) {
        self.transport = transport
    }

    package func listTools(_ server: MCPServerConfig) async throws -> [OwnMCPTools.RemoteTool] {
        let session = try await open(server)
        var tools: [OwnMCPTools.RemoteTool] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var params: [String: Any] = [:]
            if let cursor { params["cursor"] = cursor }
            let result = try await rpc(server, session: session, id: 2, method: "tools/list", params: params)
            tools += Self.tools(from: result)
            guard let next = result["nextCursor"] as? String, !next.isEmpty else { break }
            cursor = next
        }
        return tools
    }

    package func callTool(
        _ server: MCPServerConfig, name: String, argumentsJSON: String
    ) async throws -> (text: String, isError: Bool) {
        guard let arguments = ToolArguments.parse(argumentsJSON) else { throw Failure.badAnswer }
        let session = try await open(server)
        let result = try await rpc(server, session: session, id: 2, method: "tools/call",
                                   params: ["name": name, "arguments": arguments])
        let blocks = result["content"] as? [[String: Any]] ?? []
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        return (texts.joined(separator: "\n"), result["isError"] as? Bool ?? false)
    }

    /// initialize, then the initialized notification; returns the session id
    /// the server assigned, if it assigns one.
    private func open(_ server: MCPServerConfig) async throws -> String? {
        let initialize: [String: Any] = [
            "protocolVersion": Self.protocolVersion,
            "capabilities": [:],
            "clientInfo": ["name": "Companion", "version": "1"],
        ]
        let (reply, session) = try await post(server, session: nil, payload: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": initialize,
        ])
        guard reply?["result"] != nil else { throw Failure.badAnswer }
        _ = try await post(server, session: session, payload: [
            "jsonrpc": "2.0", "method": "notifications/initialized",
        ])
        return session
    }

    private func rpc(
        _ server: MCPServerConfig, session: String?, id: Int, method: String, params: [String: Any]
    ) async throws -> [String: Any] {
        let (reply, _) = try await post(server, session: session, payload: [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params,
        ])
        guard let reply, let result = reply["result"] as? [String: Any] else {
            throw Failure.badAnswer
        }
        return result
    }

    private func post(
        _ server: MCPServerConfig, session: String?, payload: [String: Any]
    ) async throws -> (reply: [String: Any]?, session: String?) {
        guard let url = URL(string: server.url), url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil
        else { throw Failure.insecureURL }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        if let token = server.authorization, !token.isEmpty {
            request.setValue(Self.bearer(token), forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await transport.data(for: request)
        } catch {
            // The error can name the URL; the server's label is all the log gets.
            Log.app("mcp: server «\(server.label)» did not answer")
            throw Failure.unreachable
        }
        guard (200..<300).contains(http.statusCode), data.count <= Self.maxBody else {
            throw Failure.badAnswer
        }
        let assigned = http.value(forHTTPHeaderField: "Mcp-Session-Id") ?? session
        guard !data.isEmpty else { return (nil, assigned) }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        return (try Self.reply(data, contentType: contentType), assigned)
    }

    /// JSON, or an SSE stream where the event with a result or an error is the
    /// answer; anything else is not the protocol.
    static func reply(_ data: Data, contentType: String) throws -> [String: Any] {
        if contentType.contains("text/event-stream") {
            let text = String(decoding: data, as: UTF8.self)
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("data:") {
                let json = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
                if let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                   object["result"] != nil || object["error"] != nil {
                    return object
                }
            }
            throw Failure.badAnswer
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.badAnswer }
        return object
    }

    static func tools(from result: [String: Any]) -> [OwnMCPTools.RemoteTool] {
        (result["tools"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let schema = (item["inputSchema"] as? [String: Any])
                .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            return OwnMCPTools.RemoteTool(
                name: name, description: item["description"] as? String ?? "",
                inputSchemaJSON: schema)
        }
    }

    /// The stored value may already carry the scheme (a hand-edited file).
    private static func bearer(_ token: String) -> String {
        token.lowercased().hasPrefix("bearer ") ? token : "Bearer " + token
    }
}
