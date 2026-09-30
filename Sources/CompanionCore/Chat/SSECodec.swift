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

    /// Every fragment in the chunk, each with its `index` — the one field
    /// OpenAI marks required. A fragment without it cannot be stitched and
    /// is dropped. Two calls in one reply arrive interleaved (0, 1, 0, 1):
    /// reading `first` fused them into `"read_filewrite_file"` (10c-A).
    public static func toolDeltas(fromSSE line: String) -> [RawToolCallDelta] {
        guard let payload = ssePayload(line),
              let obj = jsonObject(from: payload),
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let calls = delta["tool_calls"] as? [[String: Any]]
        else { return [] }
        return calls.compactMap { call in
            guard let index = call["index"] as? Int else { return nil }
            let fn = call["function"] as? [String: Any]
            let name = fn?["name"] as? String
            let arguments = fn?["arguments"] as? String
            let id = call["id"] as? String
            if name == nil && arguments == nil && id == nil { return nil }
            return RawToolCallDelta(index: index, id: id, name: name, arguments: arguments)
        }
    }

    public static func handoff(name: String, arguments: String) -> Handoff? {
        Handoff.parse(toolName: name, arguments: arguments)
    }
}

/// spec 07 `RawToolCallDelta { index; id?; function?.arguments? }`. `name`
/// is not in the corpus dump; OpenAI sends it in the first fragment and
/// nothing works without it, so it is added.
public struct RawToolCallDelta: Sendable, Equatable {
    public var index: Int
    public var id: String?
    public var name: String?
    public var arguments: String?

    public init(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// `tool_call_ids.rs` (spec 24 §5): stitch fragments by index into whole
/// calls. The provider's id is kept; one is invented only when none came
/// (Ollama and some compatibles), and it stays the same for the round.
public struct ToolCallBuilder: Sendable, Equatable {
    private struct Partial: Sendable, Equatable {
        var id: String?
        var invented: String
        var name = ""
        var arguments = ""
    }

    private var partials: [Int: Partial] = [:]

    public init() {}

    /// Some fragment carried a name or arguments. An empty name with empty
    /// arguments (a provider clearing the field) does not count.
    public var started: Bool {
        partials.values.contains { !$0.name.isEmpty || !$0.arguments.isEmpty }
    }

    /// In index order, with the id the model must get back on the result.
    public var calls: [ToolCallRef] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index],
                  !partial.name.isEmpty || !partial.arguments.isEmpty
            else { return nil }
            return ToolCallRef(
                id: partial.id ?? partial.invented,
                name: partial.name, arguments: partial.arguments)
        }
    }

    public mutating func feed(fromSSE line: String) {
        for fragment in SSECodec.toolDeltas(fromSSE: line) {
            var partial = partials[fragment.index]
                ?? Partial(invented: "call_\(fragment.index)_\(UUID().uuidString.prefix(8))")
            if let id = fragment.id, !id.isEmpty { partial.id = id }
            if let name = fragment.name { partial.name += name }
            if let arguments = fragment.arguments { partial.arguments += arguments }
            partials[fragment.index] = partial
        }
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
