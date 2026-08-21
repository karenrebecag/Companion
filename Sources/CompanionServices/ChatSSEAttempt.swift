import CompanionCore
import Foundation

enum ChatAttemptOutcome: Sendable, Equatable {
    case reply
    case spokePartial
    case handoff(Handoff)
    case failed(ChatError)
    case cancelled
}

/// One provider: body, SSE, inactivity + turn cap. First timer wins.
/// Unstructured Tasks, not TaskGroup: grouping the SSE iterator deadlocks
/// the cooperative pool on the first 200 body.
enum ChatSSEAttempt {
    static func run(
        provider: ProviderDescriptor,
        key: String?,
        history: [Turn],
        tools: [ToolSpec],
        settings: ChatSettings,
        ownerFirstName: String,
        about: String = "",
        instructions: String = "",
        transport: any ChatTransport,
        resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)? = nil,
        yield: @escaping @Sendable (ChatDelta) -> Void
    ) async -> ChatAttemptOutcome {
        guard let request = makeRequest(
            provider: provider, key: key, history: history, tools: tools,
            settings: settings, ownerFirstName: ownerFirstName,
            about: about, instructions: instructions,
            resolveAttachment: resolveAttachment)
        else { return .failed(.unreachable) }

        let sink = DeltaSink(yield: yield)
        let work = Task {
            try await read(
                request: request, settings: settings,
                transport: transport, sink: sink)
        }
        let cap = Task {
            try await sleepSeconds(settings.turnTimeout)
            work.cancel()
        }
        do {
            let outcome = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            cap.cancel()
            return outcome
        } catch is CancellationError {
            cap.cancel()
            work.cancel()
            if Task.isCancelled { return .cancelled }
            return await sink.finish(error: .timeout)
        } catch {
            cap.cancel()
            work.cancel()
            return await sink.finish(error: .unreachable)
        }
    }

    static func makeRequest(
        provider: ProviderDescriptor,
        key: String?,
        history: [Turn],
        tools: [ToolSpec],
        settings: ChatSettings,
        ownerFirstName: String,
        about: String = "",
        instructions: String = "",
        resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)? = nil
    ) -> URLRequest? {
        guard let url = provider.endpoint else { return nil }
        // Validate endpoint URL against security policy (HTTPS always ok, HTTP only for localhost).
        guard EndpointPolicy.isAcceptable(url) else { return nil }
        var request = URLRequest(
            url: url, timeoutInterval: settings.inactivityTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        guard let body = makeBody(
            provider: provider, history: history, tools: tools,
            settings: settings, ownerFirstName: ownerFirstName,
            about: about, instructions: instructions,
            resolveAttachment: resolveAttachment)
        else { return nil }
        request.httpBody = body
        return request
    }

    static func mapStatus(_ code: Int) -> ChatError {
        switch code {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .rateLimited
        default: return .httpStatus(code)
        }
    }
}

private func makeBody(
    provider: ProviderDescriptor,
    history: [Turn],
    tools: [ToolSpec],
    settings: ChatSettings,
    ownerFirstName: String,
    about: String,
    instructions: String,
    resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)?
) -> Data? {
    let delegateEnabled = tools.contains { $0.name == "delegate" }
    var messages: [[String: Any]] = [[
        "role": TurnRole.system.rawValue,
        "content": ChatPrompt.system(
            ownerFirstName: ownerFirstName, delegateEnabled: delegateEnabled,
            about: about, instructions: instructions),
    ]]
    let window = max(settings.historyWindow, 0)
    for turn in history.suffix(window) {
        var message: [String: Any] = [
            "role": turn.role.rawValue,
            "content": messageContent(turn, resolve: resolveAttachment),
        ]
        // The tool-calling round trip only validates if the assistant's
        // request and the tool's answer both carry the call id.
        if !turn.toolCalls.isEmpty {
            message["tool_calls"] = turn.toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.arguments],
                ] as [String: Any]
            }
        }
        if let toolCallID = turn.toolCallID {
            message["tool_call_id"] = toolCallID
        }
        messages.append(message)
    }
    var body: [String: Any] = [
        "model": provider.model,
        "stream": true,
        "temperature": 0.7,
        "messages": messages,
    ]
    if !tools.isEmpty {
        var encoded: [Any] = []
        for spec in tools {
            guard let data = spec.encodeChat().data(using: .utf8) else { continue }
            do {
                encoded.append(try JSONSerialization.jsonObject(with: data))
            } catch {
                continue
            }
        }
        body["tools"] = encoded
        body["tool_choice"] = "auto"
    }
    do {
        return try JSONSerialization.data(withJSONObject: body)
    } catch {
        return nil
    }
}

private func read(
    request: URLRequest,
    settings: ChatSettings,
    transport: any ChatTransport,
    sink: DeltaSink
) async throws -> ChatAttemptOutcome {
    let clock = PingClock()
    let consume = Task {
        let (status, lines) = try await transport.lines(for: request)
        await clock.ping()
        guard status == 200 else {
            return await sink.finish(error: ChatSSEAttempt.mapStatus(status))
        }
        for try await line in lines {
            try Task.checkCancellation()
            await clock.ping()
            await sink.feed(line)
        }
        return await sink.finish(error: nil)
    }
    let watchdog = Task {
        do {
            try await clock.wait(timeout: settings.inactivityTimeout)
        } catch is CancellationError {
            return
        }
        consume.cancel()
    }
    do {
        let outcome = try await withTaskCancellationHandler {
            try await consume.value
        } onCancel: {
            consume.cancel()
            watchdog.cancel()
        }
        watchdog.cancel()
        return outcome
    } catch {
        consume.cancel()
        watchdog.cancel()
        if error is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            return await sink.finish(error: .timeout)
        }
        return await sink.finish(error: .unreachable)
    }
}

private func sleepSeconds(_ seconds: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(max(seconds, 0)))
}

/// Groq/Ollama reject multimodal parts. Parts only appear when a resolved
/// image is actually going to travel; everything else stays a String.
private func messageContent(
    _ turn: Turn,
    resolve: (@Sendable (AttachmentRef) -> AttachmentPayload?)?
) -> Any {
    let numbered = Turn.numbered(turn.content, turn.attachments)
    guard let resolve else { return numbered }
    var imageURLs: [String] = []
    var inline: [String] = []
    for ref in turn.attachments {
        switch resolve(ref) {
        case .imageDataURL(let url):
            imageURLs.append(url)
        case .text(let body):
            inline.append("Contenido de \(ref.name):\n\(body)")
        case .path, .none:
            break
        }
    }
    if imageURLs.isEmpty {
        if inline.isEmpty { return numbered }
        return numbered + "\n" + inline.joined(separator: "\n")
    }
    var parts: [[String: Any]] = [["type": "text", "text": numbered]]
    for block in inline {
        parts.append(["type": "text", "text": block])
    }
    for url in imageURLs {
        parts.append(["type": "image_url", "image_url": ["url": url]])
    }
    return parts
}

/// Cancelling the sleeper on ping restarts inactivity from the last SSE line.
private actor PingClock {
    private var sleeper: Task<Void, Error>?

    func ping() {
        sleeper?.cancel()
        sleeper = nil
    }

    func wait(timeout: TimeInterval) async throws {
        let slice = max(timeout, 0)
        if slice == 0 { throw ChatError.timeout }
        while !Task.isCancelled {
            let task = Task { try await sleepSeconds(slice) }
            sleeper = task
            do {
                try await task.value
                return
            } catch is CancellationError {
                sleeper?.cancel()
                sleeper = nil
                if Task.isCancelled { throw CancellationError() }
                continue
            }
        }
        throw CancellationError()
    }
}

private actor DeltaSink {
    private var spokePartial = false
    private var tool = ToolCallBuilder()
    private var full = ""
    private var sentenceBuf = ""
    private var finished = false
    private var outcome: ChatAttemptOutcome = .failed(.empty)
    private let yield: @Sendable (ChatDelta) -> Void

    init(yield: @escaping @Sendable (ChatDelta) -> Void) {
        self.yield = yield
    }

    func feed(_ line: String) {
        tool.feed(fromSSE: line)
        var cuts: [String] = []
        if let piece = SSECodec.delta(fromSSE: line) {
            full += piece
            sentenceBuf += piece
            while let cut = SentenceSplitter.takeSentence(sentenceBuf) {
                sentenceBuf = cut.rest
                spokePartial = true
                cuts.append(cut.sentence)
            }
        }
        for cut in cuts { yield(.text(cut)) }
    }

    func finish(error: ChatError?) -> ChatAttemptOutcome {
        if finished { return outcome }
        let started = tool.started
        let name = tool.name
        let arguments = tool.arguments
        let spoke = spokePartial
        let reply = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceBuf = ""

        // Determine outcome based on tool call and text
        var toolCallDelta: ChatDelta? = nil
        if started && !name.isEmpty {
            if name == "delegate" {
                // Delegate is for conversation layer - try to parse handoff
                let parsed = Handoff.parse(toolName: name, arguments: arguments)
                if let parsed {
                    outcome = .handoff(parsed)
                } else {
                    // Malformed delegate - fall through to text-based outcome
                    if error != nil || reply.isEmpty {
                        outcome = spoke ? .spokePartial : .failed(error ?? .empty)
                    } else {
                        outcome = .reply
                    }
                }
            } else {
                // Non-delegate tool is for specialists - emit as toolCall
                let callId = UUID().uuidString
                toolCallDelta = .toolCall(id: callId, name: name, arguments: arguments)
                outcome = .reply
            }
        } else if error != nil || reply.isEmpty {
            outcome = spoke ? .spokePartial : .failed(error ?? .empty)
        } else {
            outcome = .reply
        }
        finished = true
        let commit = outcome

        // Emit deltas based on outcome
        switch commit {
        case .handoff(let handoff):
            if !rest.isEmpty { yield(.text(rest)) }
            yield(.handoff(handoff))
        case .reply, .spokePartial:
            if !rest.isEmpty { yield(.text(rest)) }
            if let toolCall = toolCallDelta {
                yield(toolCall)
            }
        case .failed, .cancelled:
            break
        }
        return commit
    }
}
