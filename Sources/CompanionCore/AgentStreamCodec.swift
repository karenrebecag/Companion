import Foundation

public struct ApprovalRequest: Sendable, Equatable {
    public var requestId: String
    public var toolName: String
    public var summary: String
    public var inputJSON: String

    public init(requestId: String, toolName: String, summary: String, inputJSON: String) {
        self.requestId = requestId
        self.toolName = toolName
        self.summary = summary
        self.inputJSON = inputJSON
    }
}

public enum AgentStreamEvent: Sendable, Equatable {
    case initialized(sessionId: String)
    case result(text: String, isError: Bool)
    case approval(ApprovalRequest)
    case toolUse(name: String, detail: String)
    case thought(String)
    case ignored
}

public enum AgentStreamCodec: Sendable {
    public static func userTurn(_ text: String) -> String? {
        let obj: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": text]],
            ],
        ]
        return encodeLine(obj)
    }

    /// init/result/control_request and assistant tool/thinking blocks matter;
    /// hooks, rate limits and plain assistant text are noise on the wire.
    public static func parse(_ line: String) -> AgentStreamEvent {
        guard let obj = jsonObject(from: line),
              let type = obj["type"] as? String
        else { return .ignored }
        switch type {
        case "system":
            guard obj["subtype"] as? String == "init",
                  let sid = obj["session_id"] as? String, !sid.isEmpty
            else { return .ignored }
            return .initialized(sessionId: sid)
        case "result":
            // Missing fields are an error so we never announce a false success.
            return .result(text: obj["result"] as? String ?? "",
                           isError: jsonBool(obj["is_error"]) ?? true)
        case "assistant":
            return parseAssistant(obj)
        case "control_request":
            return parseControl(obj)
        default:
            return .ignored
        }
    }

    public static func controlResponse(
        requestId: String, allow: Bool, inputJSON: String, message: String
    ) -> String? {
        var inner: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if allow {
            inner["updatedInput"] = jsonObject(from: inputJSON) ?? [:]
        } else {
            inner["message"] = message
        }
        let obj: [String: Any] = [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestId,
                "response": inner,
            ],
        ]
        return encodeLine(obj)
    }

    public static func toolDetail(fromInputJSON json: String) -> String {
        guard let input = jsonObject(from: json) else { return "" }
        return toolDetail(from: input)
    }

    /// Technical tool names are opaque in a glanceable timeline.
    public static func stepLabel(_ tool: String, _ detail: String) -> String {
        let verb: String
        switch tool {
        case "WebSearch": verb = "buscando en internet"
        case "WebFetch": verb = "leyendo la web"
        case "Read": verb = "leyendo"
        case "Write", "Edit", "NotebookEdit": verb = "editando"
        case "Bash": verb = "corriendo"
        case "Grep", "Glob": verb = "buscando en el código"
        case "Task", "Agent": verb = "delegando"
        case "TodoWrite": verb = "organizando el plan"
        default: verb = tool.lowercased()
        }
        return detail.isEmpty ? verb : "\(verb): \(detail)"
    }

    /// Action beats thought when both arrive in one assistant message:
    /// the visible step of a job is what the specialist did, not what it mused.
    private static func parseAssistant(_ obj: [String: Any]) -> AgentStreamEvent {
        guard let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]]
        else { return .ignored }
        for block in content where block["type"] as? String == "tool_use" {
            let name = block["name"] as? String ?? "?"
            let input = block["input"] as? [String: Any] ?? [:]
            return .toolUse(name: name, detail: toolDetail(from: input))
        }
        for block in content where block["type"] as? String == "thinking" {
            guard let raw = block["thinking"] as? String else { continue }
            let line = raw.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty } ?? ""
            guard !line.isEmpty else { continue }
            return .thought(String(line.prefix(80)))
        }
        return .ignored
    }

    private static func parseControl(_ obj: [String: Any]) -> AgentStreamEvent {
        guard let rid = obj["request_id"] as? String, !rid.isEmpty,
              let req = obj["request"] as? [String: Any],
              req["subtype"] as? String == "can_use_tool"
        else { return .ignored }
        let tool = req["tool_name"] as? String ?? "?"
        let input = req["input"] as? [String: Any] ?? [:]
        let summary = (input["command"] as? String)
            ?? (req["description"] as? String) ?? tool
        return .approval(ApprovalRequest(
            requestId: rid, toolName: tool,
            summary: summary, inputJSON: jsonString(from: input)))
    }

    private static func toolDetail(from input: [String: Any]) -> String {
        for key in ["command", "query", "pattern", "url", "file_path",
                    "path", "description", "prompt"] {
            if let v = input[key] as? String, !v.isEmpty {
                return String(v.prefix(60))
            }
        }
        return ""
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func jsonString(from obj: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: obj)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    private static func encodeLine(_ obj: [String: Any]) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: obj)
            guard let s = String(data: data, encoding: .utf8) else { return nil }
            return s + "\n"
        } catch {
            return nil
        }
    }
}
