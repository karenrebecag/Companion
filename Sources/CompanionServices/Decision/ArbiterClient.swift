import CompanionCore
import Foundation

/// N2: arbitrates over the shortlist N1 already weighed, one forced function
/// call constrained to `ArbitrationShortlist.choiceSchema()`. It never sees
/// the installed-app list, never emits a free tool call, and never invents a
/// confidence — a Chat Completions function call carries no logprobs, unlike
/// `OllamaDecisionProvider`'s single-token trick.
package struct ArbiterClient: Sendable {
    private let transport: any ChatTransport
    private let secrets: any SecretStore
    private let fastModel: ProviderDescriptor
    private let strongModel: ProviderDescriptor
    private let timeout: TimeInterval

    package init(
        transport: any ChatTransport,
        secrets: any SecretStore,
        fastModel: ProviderDescriptor,
        strongModel: ProviderDescriptor,
        timeout: TimeInterval = 8
    ) {
        self.transport = transport
        self.secrets = secrets
        self.fastModel = fastModel
        self.strongModel = strongModel
        self.timeout = timeout
    }

    package func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? {
        // An empty shortlist is `choiceSchema`'s own thrown error (OpenAI
        // strict rejects `enum: []`); catching it inside `ask` would still
        // spend a request first, so it is checked here instead.
        guard !shortlist.entries.isEmpty else { return nil }
        guard let fastPick = await ask(utterance: utterance, shortlist: shortlist, provider: fastModel)
        else { return nil }
        let fastConfidence = confidence(for: fastPick, in: shortlist)
        guard ArbitrationTier.needsStrong(fastConfidence: fastConfidence) else {
            return (fastPick, fastConfidence)
        }
        guard let strongPick = await ask(utterance: utterance, shortlist: shortlist, provider: strongModel)
        else { return nil }
        return (strongPick, confidence(for: strongPick, in: shortlist))
    }

    /// Chat function calls carry no logprobs, so 0.9-for-a-fast-answer would
    /// be invented, not measured. Agreeing with the shortlist's own top-mass
    /// entry inherits N1's uncertainty (the mass itself, which may be low —
    /// that is exactly what should still escalate); overriding the top pick
    /// is a flat 0.6, never a claimed high number.
    private func confidence(for entry: ShortlistEntry, in shortlist: ArbitrationShortlist) -> Double {
        let topMass = shortlist.entries.map(\.mass).max() ?? entry.mass
        return abs(entry.mass - topMass) < 1e-9 ? entry.mass : 0.6
    }

    private func ask(
        utterance: String, shortlist: ArbitrationShortlist, provider: ProviderDescriptor
    ) async -> ShortlistEntry? {
        let function: [String: Any]
        do {
            let schema = try shortlist.choiceSchema()
            guard let data = schema.data(using: .utf8),
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            function = obj
        } catch {
            Log.chat("arbiter: schema failed (\(error))")
            return nil
        }
        guard let url = provider.endpoint else { return nil }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = storedKey(for: provider) {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            request.httpBody = try JSONSerialization.data(
                withJSONObject: Self.requestBody(utterance: utterance, model: provider.model, function: function))
        } catch {
            Log.chat("arbiter: body encode failed (\(error.localizedDescription))")
            return nil
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            Log.chat("arbiter: request failed (\(error.localizedDescription))")
            return nil
        }
        guard response.statusCode == 200 else {
            Log.chat("arbiter: http \(response.statusCode)")
            return nil
        }
        guard let choiceId = Self.choiceId(from: data) else {
            Log.chat("arbiter: malformed response")
            return nil
        }
        guard shortlist.accepts(choiceId), let entry = shortlist.entry(for: choiceId) else {
            Log.chat("arbiter: id not on the shortlist (\(choiceId))")
            return nil
        }
        return entry
    }

    private func storedKey(for provider: ProviderDescriptor) -> String? {
        guard let name = provider.secretKey else { return nil }
        let value: String?
        do {
            value = try secrets.read(name)
        } catch {
            return nil
        }
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Wire (pure, tested indirectly through fixtures)

    static func requestBody(utterance: String, model: String, function: [String: Any]) -> [String: Any] {
        [
            "model": model,
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": "Pick the one shortlist entry that matches what the user said. "
                        + "Call arbitrate with its id; never invent one.",
                ],
                ["role": "user", "content": utterance],
            ],
            "tools": [["type": "function", "function": function]],
            "tool_choice": ["type": "function", "function": ["name": "arbitrate"]],
        ]
    }

    static func choiceId(from data: Data) -> String? {
        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            return nil
        }
        guard let call = decoded.choices.first?.message.toolCalls?.first,
              let argsData = call.function.arguments.data(using: .utf8)
        else { return nil }
        do {
            return try JSONDecoder().decode(ChoiceArguments.self, from: argsData).choice
        } catch {
            return nil
        }
    }
}

/// Chat Completions response, trimmed to the forced tool call this adapter
/// reads. Free-text `content` is never consulted: an answer that skipped the
/// tool call is not a choice.
private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable {
        let toolCalls: [ToolCall]?
        enum CodingKeys: String, CodingKey { case toolCalls = "tool_calls" }
    }
    struct ToolCall: Decodable { let function: FunctionCall }
    struct FunctionCall: Decodable { let arguments: String }
    let choices: [Choice]
}

private struct ChoiceArguments: Decodable {
    let choice: String
}
