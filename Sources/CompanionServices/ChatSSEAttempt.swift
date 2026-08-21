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
        transport: any ChatTransport,
        yield: @escaping @Sendable (ChatDelta) -> Void
    ) async -> ChatAttemptOutcome {
        guard let request = makeRequest(
            provider: provider, key: key, history: history, tools: tools,
            settings: settings, ownerFirstName: ownerFirstName)
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
            return sink.finish(error: .timeout)
        } catch {
            cap.cancel()
            work.cancel()
            return sink.finish(error: .unreachable)
        }
    }

    static func makeRequest(
        provider: ProviderDescriptor,
        key: String?,
        history: [Turn],
        tools: [ToolSpec],
        settings: ChatSettings,
        ownerFirstName: String
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
            settings: settings, ownerFirstName: ownerFirstName)
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
    ownerFirstName: String
) -> Data? {
    let delegateEnabled = tools.contains { $0.name == "delegate" }
    var messages: [[String: Any]] = [[
        "role": TurnRole.system.rawValue,
        "content": ChatPrompt.system(
            ownerFirstName: ownerFirstName, delegateEnabled: delegateEnabled),
    ]]
    let window = max(settings.historyWindow, 0)
    for turn in history.suffix(window) {
        messages.append([
            "role": turn.role.rawValue,
            "content": Turn.numbered(turn.content, turn.attachments),
        ])
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
            return sink.finish(error: ChatSSEAttempt.mapStatus(status))
        }
        for try await line in lines {
            try Task.checkCancellation()
            await clock.ping()
            sink.feed(line)
        }
        return sink.finish(error: nil)
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
            return sink.finish(error: .timeout)
        }
        return sink.finish(error: .unreachable)
    }
}

private func sleepSeconds(_ seconds: TimeInterval) async throws {
    try await Task.sleep(for: .seconds(max(seconds, 0)))
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

private final class DeltaSink: @unchecked Sendable {
    private let lock = NSLock()
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
        lock.lock()
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
        lock.unlock()
        for cut in cuts { yield(.text(cut)) }
    }

    func finish(error: ChatError?) -> ChatAttemptOutcome {
        lock.lock()
        if finished {
            let cached = outcome
            lock.unlock()
            return cached
        }
        let started = tool.started
        let name = tool.name
        let arguments = tool.arguments
        let spoke = spokePartial
        let reply = full.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = sentenceBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceBuf = ""
        let parsed = started
            ? Handoff.parse(toolName: name, arguments: arguments) : nil
        if let parsed {
            outcome = .handoff(parsed)
        } else if error != nil || reply.isEmpty {
            outcome = spoke ? .spokePartial : .failed(error ?? .empty)
        } else {
            outcome = .reply
        }
        finished = true
        let commit = outcome
        lock.unlock()
        switch commit {
        case .handoff(let handoff):
            if !rest.isEmpty { yield(.text(rest)) }
            yield(.handoff(handoff))
        case .reply, .spokePartial:
            if !rest.isEmpty { yield(.text(rest)) }
        case .failed, .cancelled:
            break
        }
        return commit
    }
}
