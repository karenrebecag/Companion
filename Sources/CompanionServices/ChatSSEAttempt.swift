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
        language: AppLanguage = .en,
        memory: String = "",
        skills: String = "",
        voice: Bool = false,
        transport: any ChatTransport,
        resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)? = nil,
        yield: @escaping @Sendable (ChatDelta) -> Void
    ) async -> ChatAttemptOutcome {
        guard let request = makeRequest(
            provider: provider, key: key, history: history, tools: tools,
            settings: settings, ownerFirstName: ownerFirstName,
            about: about, instructions: instructions, language: language,
            memory: memory, skills: skills, voice: voice,
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
        language: AppLanguage = .en,
        memory: String = "",
        skills: String = "",
        voice: Bool = false,
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
            about: about, instructions: instructions, language: language,
            memory: memory, skills: skills, voice: voice,
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
    language: AppLanguage,
    memory: String = "",
    skills: String = "",
    voice: Bool = false,
    resolveAttachment: (@Sendable (AttachmentRef) -> AttachmentPayload?)?
) -> Data? {
    let delegateEnabled = tools.contains { $0.name == "delegate" }
    // Derived from the tools, like delegate: what is declared is what the
    // prompt may promise, and nothing the prompt promises goes undeclared.
    let parentToolsEnabled = tools.contains { ParentTool(rawValue: $0.name) != nil }
    // Wave 15g-3: the hands are declared only with Accessibility granted,
    // so the declaration, not a setting, decides whether typing is promised.
    let handsEnabled = tools.contains { $0.name == "type_text" }
    var messages: [[String: Any]] = [[
        "role": TurnRole.system.rawValue,
        "content": ChatPrompt.system(
            ownerFirstName: ownerFirstName, delegateEnabled: delegateEnabled,
            parentToolsEnabled: parentToolsEnabled,
            handsEnabled: handsEnabled,
            sightEnabled: tools.contains { $0.name == ParentTool.look.rawValue },
            about: about, instructions: instructions, language: language,
            memory: memory, skills: skills, voice: voice),
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
        "messages": messages,
    ]
    // Sent only when the descriptor chose one AND the model takes it. A
    // reasoning model answers 400 to the field itself, which the ladder would
    // report as "no provider available" — the wrong place to send someone
    // looking for the fault.
    if let temperature = provider.temperature,
       ChatParameters.acceptsTemperature(provider.model) {
        body["temperature"] = temperature
    }
    // 15c-3: only the descriptor that asks for it (the hold's gpt-oss
    // brain) — never guessed from the model name.
    if let effort = provider.reasoningEffort {
        body["reasoning_effort"] = effort
    }
    if !tools.isEmpty {
        var encoded: [Any] = []
        for spec in tools {
            guard let data = spec.encodeChat(strict: provider.supportsStrictTools)
                .data(using: .utf8) else { continue }
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

/// OpenAI-compatible servers such as Ollama reject multimodal parts. Parts only appear when a resolved
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
        let calls = tool.calls.filter { !$0.name.isEmpty }
        let spoke = spokePartial
        let reply = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceBuf = ""

        // `delegate` is the conversation layer's; everything else is a call
        // the parent (10b) or the specialist answers. Both may come in one
        // round: the calls travel first, the handoff closes the turn.
        var handoff: Handoff?
        var others: [ToolCallRef] = []
        for call in calls {
            if call.name == "delegate" {
                // A malformed delegate does not escalate; the text stands.
                if handoff == nil {
                    handoff = Handoff.parse(toolName: call.name, arguments: call.arguments)
                }
            } else {
                others.append(call)
            }
        }
        if let handoff {
            outcome = .handoff(handoff)
        } else if !others.isEmpty {
            outcome = .reply
        } else if error != nil || reply.isEmpty {
            outcome = spoke ? .spokePartial : .failed(error ?? .empty)
        } else {
            outcome = .reply
        }
        finished = true
        let commit = outcome

        switch commit {
        case .handoff(let handoff):
            if !rest.isEmpty { yield(.text(rest)) }
            if !others.isEmpty { yield(.toolCalls(others)) }
            yield(.handoff(handoff))
        case .reply, .spokePartial:
            if !rest.isEmpty { yield(.text(rest)) }
            if !others.isEmpty { yield(.toolCalls(others)) }
        case .failed, .cancelled:
            break
        }
        return commit
    }
}
