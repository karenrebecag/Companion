import Foundation

public enum SSECodec: Sendable {
    public static func delta(fromSSE line: String) -> String? {
        guard let payload = ssePayload(line),
              let obj = jsonObject(from: payload),
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty
        else { return nil }
        return content
    }

    public static func toolDelta(fromSSE line: String) -> (name: String?, arguments: String?)? {
        guard let payload = ssePayload(line),
              let obj = jsonObject(from: payload),
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let calls = delta["tool_calls"] as? [[String: Any]],
              let fn = calls.first?["function"] as? [String: Any]
        else { return nil }
        let name = fn["name"] as? String
        let args = fn["arguments"] as? String
        if name == nil && args == nil { return nil }
        return (name, args)
    }

    public static func handoff(name: String, arguments: String) -> Handoff? {
        Handoff.parse(toolName: name, arguments: arguments)
    }
}

public struct ToolCallBuilder: Sendable, Equatable {
    public private(set) var name: String
    public private(set) var arguments: String
    public var started: Bool { !name.isEmpty || !arguments.isEmpty }

    public init() {
        name = ""
        arguments = ""
    }

    public mutating func feed(fromSSE line: String) {
        guard let fragment = SSECodec.toolDelta(fromSSE: line) else { return }
        if let n = fragment.name { name += n }
        if let a = fragment.arguments { arguments += a }
    }
}

/// `data:` is the only SSE field chat/completions uses for token payloads.
private func ssePayload(_ line: String) -> String? {
    let t = line.trimmingCharacters(in: .whitespaces)
    guard t.hasPrefix("data:") else { return nil }
    let payload = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" { return nil }
    return String(payload)
}
