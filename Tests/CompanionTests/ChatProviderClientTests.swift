import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func chatProviderClientTests() {
    testOpenAI200YieldsText()
    testOpenAI500FallsToGroq()
    testSpokePartialDoesNotFailover()
    testSkipOpenAIWithoutKey()
    testNoProviderWhenNothingAvailable()
    testOllamaProbeFalseNotAttempted()
    testFragmentedDelegateHandoff()
    testMalformedToolNoHandoff()
    testEmptyToolsOmitsToolsKey()
    testToolsAttachedWhenNonEmpty()
    testVerify200And401()
    testVerifyEmptyKey()
    testRequestBodyAndAuth()
    testAttachmentsAreNumberedText()
    testHistoryWindow()
    testInactivityAndTurnTimeout()
    testVerifyHTTPMapping()
    testOllamaWithoutKey()
    testFailedPartialDoesNotLeakIntoFailover()
}

@MainActor func testOpenAI200YieldsText() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let deltas = collectChat(makeChatClient(transport: transport))
    expectEq(deltas, [.text("Hola")], "openai 200: emite el chunk de texto")
    expectEq(transport.requests.count, 1, "openai 200: un solo intento")
    expect(
        transport.requests[0].url?.absoluteString
            == ProviderDescriptor.openAI.endpoint?.absoluteString,
        "openai 200: pega el endpoint de OpenAI")
}

@MainActor func testOpenAI500FallsToGroq() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(status: 500))
    transport.stub(.groq, ScriptedReply(lines: [SSEFixtures.groq, SSEFixtures.done]))
    let deltas = collectChat(makeChatClient(transport: transport))
    expectEq(deltas, [.text("Desde Groq")], "fallback: Groq contesta tras 500")
    expectEq(chatHosts(transport), ["api.openai.com", "api.groq.com"],
             "fallback: OpenAI luego Groq")
}

@MainActor func testSpokePartialDoesNotFailover() {
    let transport = ScriptedTransport()
    transport.stub(
        .openAI,
        ScriptedReply(
            lines: [SSEFixtures.sentence],
            streamError: URLError(.networkConnectionLost)))
    transport.stub(.groq, ScriptedReply(lines: SSEFixtures.chunks("NO-GROQ")))
    let deltas = collectChat(makeChatClient(transport: transport))
    expectEq(
        deltas, [.text("Claro, te ayudo con eso ahora.")],
        "spokePartial: entrega la frase ya cortada")
    expect(!chatHosts(transport).contains("api.groq.com"),
           "spokePartial: Groq no se llama")
}

@MainActor func testSkipOpenAIWithoutKey() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: SSEFixtures.chunks("NO-OPENAI")))
    transport.stub(.groq, ScriptedReply(lines: [SSEFixtures.groq, SSEFixtures.done]))
    let deltas = collectChat(
        makeChatClient(keys: [.groq: "gsk-test"], transport: transport))
    expectEq(deltas, [.text("Desde Groq")], "skip: Groq con llave contesta")
    expect(!chatHosts(transport).contains("api.openai.com"),
           "skip: sin llave OpenAI no hace el 401")
}

@MainActor func testNoProviderWhenNothingAvailable() {
    let transport = ScriptedTransport()
    expectChatError(
        makeChatClient(keys: [:], available: [], transport: transport),
        .noProvider, "sin llaves ni Ollama: noProvider")
    expectEq(transport.requests.count, 0, "sin llaves ni Ollama: cero red")
}

@MainActor func testOllamaProbeFalseNotAttempted() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(status: 500))
    transport.stub(.groq, ScriptedReply(status: 500))
    transport.stub(.ollama, ScriptedReply(lines: SSEFixtures.chunks("local")))
    expectChatError(
        makeChatClient(transport: transport),
        .httpStatus(500), "probe false: el último error concreto, no noProvider")
    expect(!chatHosts(transport).contains("localhost"),
           "probe false: Ollama no se intenta")
}

@MainActor func testFragmentedDelegateHandoff() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: SSEFixtures.delegateFragments))
    let deltas = collectChat(
        makeChatClient(transport: transport), tools: [.delegate])
    expectEq(deltas, [
        .handoff(Handoff(goal: "listar el escritorio", context: "workdir ~")),
    ], "tool: fragmentos arman delegate y emiten handoff")
}

@MainActor func testMalformedToolNoHandoff() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: SSEFixtures.malformedDelegate))
    let deltas = collectChat(
        makeChatClient(transport: transport), tools: [.delegate])
    expectEq(deltas, [.text("Puedo intentarlo")],
             "tool malformado: no delega, queda el texto")
    expect(!deltas.contains { if case .handoff = $0 { return true }; return false },
           "tool malformado: ningún handoff")
}

@MainActor func testEmptyToolsOmitsToolsKey() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    _ = collectChat(makeChatClient(transport: transport), tools: [])
    guard let req = transport.requests.first else {
        expect(false, "tools []: no hubo request")
        return
    }
    let body = chatBody(req)
    expect(body["tools"] == nil, "tools []: el body no trae tools")
    expect(body["tool_choice"] == nil, "tools []: el body no trae tool_choice")
    let system = chatSystem(body)
    expect(!system.contains("llama a delegate"),
           "tools []: el system no habilita delegate")
}

@MainActor func testToolsAttachedWhenNonEmpty() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    _ = collectChat(makeChatClient(transport: transport), tools: [.delegate])
    guard let req = transport.requests.first else {
        expect(false, "tools: no hubo request")
        return
    }
    let body = chatBody(req)
    expectEq(body["tool_choice"] as? String, "auto", "tools: tool_choice auto")
    let tools = body["tools"] as? [[String: Any]] ?? []
    expectEq(tools.count, 1, "tools: un objeto encodeChat")
    expectEq(tools.first?["type"] as? String, "function", "tools: type function")
    let fn = tools.first?["function"] as? [String: Any] ?? [:]
    expectEq(fn["name"] as? String, "delegate", "tools: function.name delegate")
    expect(chatSystem(body).contains("llama a delegate"),
           "tools: system con delegateEnabled")
}

@MainActor func testVerify200And401() {
    let ok = ScriptedTransport()
    ok.stubModels(.openAI, status: 200)
    let client = makeChatClient(transport: ok)
    do {
        try runAsync { try await client.verify("sk-live", provider: .openAI) }
        expect(true, "verify 200: no tira")
    } catch {
        expect(false, "verify 200: no debía tirar \(error)")
    }
    expectEq(ok.requests.count, 1, "verify 200: un GET")
    guard let req = ok.requests.first else { return }
    expectEq(req.httpMethod, "GET", "verify: GET")
    expectEq(
        req.url?.absoluteString,
        ProviderDescriptor.openAI.baseURL.absoluteString + "/models",
        "verify: {baseURL}/models")
    expectEq(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-live",
             "verify: Bearer de la clave pegada")
    expectEq(req.timeoutInterval, ChatSettings.default.inactivityTimeout,
             "verify: timeout de inactividad")

    let denied = ScriptedTransport()
    denied.stubModels(.openAI, status: 401)
    expectVerify(makeChatClient(transport: denied), "sk-x", .openAI,
                 .unauthorized, "verify 401")
}

@MainActor func testVerifyEmptyKey() {
    let transport = ScriptedTransport()
    transport.stubModels(.openAI, status: 200)
    for key in ["", "   ", "\n\t  ", " \n"] {
        expectVerify(makeChatClient(transport: transport), key, .openAI,
                     .invalidKey, "verify clave '\(key)'")
    }
    expectEq(transport.requests.count, 0, "verify: recortada vacía no pega red")
}

@MainActor func testRequestBodyAndAuth() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let history = [Turn(role: .user, content: "hola '; DROP — ñoño")]
    _ = collectChat(makeChatClient(transport: transport, owner: "Karen"),
                    history: history)
    guard let req = transport.requests.first else {
        expect(false, "body: no hubo request")
        return
    }
    expectEq(req.httpMethod, "POST", "body: POST")
    expectEq(req.value(forHTTPHeaderField: "Content-Type"), "application/json",
             "body: JSON")
    expectEq(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test",
             "body: Bearer solo con llave")
    expectEq(req.timeoutInterval, 15, "body: timeoutInterval = inactividad")
    let body = chatBody(req)
    expectEq(body["model"] as? String, "gpt-4o", "body: model del descriptor")
    expectEq(body["stream"] as? Bool, true, "body: stream true")
    let temp = (body["temperature"] as? NSNumber)?.doubleValue ?? -1
    expect(abs(temp - 0.7) < 0.0001, "body: temperature 0.7")
    let messages = body["messages"] as? [[String: Any]] ?? []
    expectEq(messages.count, 2, "body: system + historial")
    expectEq(messages[0]["role"] as? String, TurnRole.system.rawValue,
             "body: rol system")
    expectEq(messages[1]["role"] as? String, TurnRole.user.rawValue,
             "body: rol del turno")
    expectEq(messages[1]["content"] as? String, "hola '; DROP — ñoño",
             "body: unicode y SQL chars")
    expectEq(
        messages[0]["content"] as? String,
        ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false),
        "body: system prompt parametrizado")
}

@MainActor func testAttachmentsAreNumberedText() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let img = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    let doc = AttachmentRef(name: "n.txt", path: "/tmp/ñoño.txt", kind: .file)
    _ = collectChat(
        makeChatClient(transport: transport),
        history: [Turn(role: .user, content: "mira", attachments: [img, doc])])
    guard let req = transport.requests.first else {
        expect(false, "adjuntos: no hubo request")
        return
    }
    let content = (chatBody(req)["messages"] as? [[String: Any]])
        .flatMap { $0.last }?["content"]
    expectEq(content as? String, Turn.numbered("mira", [img, doc]),
             "adjuntos: Turn.numbered como texto")
    expect(!(content is [Any]), "adjuntos: no image_url ni parts")
}

@MainActor func testHistoryWindow() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let history = (0..<25).map { Turn(role: .user, content: "m\($0)") }
    _ = collectChat(
        makeChatClient(
            transport: transport,
            settings: ChatSettings(historyWindow: 20)),
        history: history)
    guard let req = transport.requests.first else {
        expect(false, "ventana: no hubo request")
        return
    }
    let messages = chatBody(req)["messages"] as? [[String: Any]] ?? []
    expectEq(messages.count, 21, "ventana: system + 20")
    expectEq(messages[1]["content"] as? String, "m5", "ventana: suffix recorta el frente")
    expectEq(messages[20]["content"] as? String, "m24", "ventana: el último entra")
}

@MainActor func testInactivityAndTurnTimeout() {
    let idle = ScriptedTransport()
    idle.stub(.openAI, ScriptedReply(hangNanoseconds: 30_000_000_000))
    expectChatError(
        makeChatClient(
            keys: [.openAI: "sk-test"], available: ["openai"],
            transport: idle, settings: ChatSettings(
                inactivityTimeout: 0.2, turnTimeout: 5),
            catalog: [.openAI]),
        .timeout, "inactividad: el primer timer gana", timeout: 2)

    let cap = ScriptedTransport()
    cap.stub(.openAI, ScriptedReply(hangNanoseconds: 30_000_000_000))
    expectChatError(
        makeChatClient(
            keys: [.openAI: "sk-test"], available: ["openai"],
            transport: cap, settings: ChatSettings(
                inactivityTimeout: 5, turnTimeout: 0.2),
            catalog: [.openAI]),
        .timeout, "tope de turno: el primer timer gana", timeout: 2)
}

@MainActor func testVerifyHTTPMapping() {
    let cases: [(Int, ChatError)] = [
        (403, .forbidden), (429, .rateLimited), (500, .httpStatus(500)),
        (404, .httpStatus(404)),
    ]
    for (status, want) in cases {
        let transport = ScriptedTransport()
        transport.stubModels(.openAI, status: status)
        expectVerify(makeChatClient(transport: transport), "sk-x", .openAI,
                     want, "verify HTTP \(status)")
    }
}

@MainActor func testOllamaWithoutKey() {
    let transport = ScriptedTransport()
    transport.stub(.ollama, ScriptedReply(lines: SSEFixtures.chunks("local")))
    let deltas = collectChat(
        makeChatClient(keys: [:], available: ["ollama"], transport: transport))
    expectEq(deltas, [.text("local")], "ollama: sin llave se intenta si el probe ve")
    expect(
        transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil,
        "ollama: sin Bearer")
}

@MainActor func testFailedPartialDoesNotLeakIntoFailover() {
    let transport = ScriptedTransport()
    transport.stub(
        .openAI,
        ScriptedReply(
            lines: [SSEFixtures.hello],
            streamError: URLError(.networkConnectionLost)))
    transport.stub(.groq, ScriptedReply(lines: [SSEFixtures.groq, SSEFixtures.done]))
    let deltas = collectChat(makeChatClient(transport: transport))
    expectEq(deltas, [.text("Desde Groq")],
             "leak: 'Hola' incompleto no se concatena con Groq")
    expectEq(chatHosts(transport), ["api.openai.com", "api.groq.com"],
             "leak: sí hubo failover")
}

@MainActor func makeChatClient(
    keys: [SecretKey: String] = [.openAI: "sk-test", .groq: "gsk-test"],
    available: Set<String> = ["openai", "groq"],
    transport: ScriptedTransport,
    settings: ChatSettings = .default,
    owner: String = "Karen",
    catalog: [ProviderDescriptor] = ProviderDescriptor.catalog
) -> ChatProviderClient {
    ChatProviderClient(
        secrets: TestSecretStore(keys),
        probe: TestProbe(available: available),
        transport: transport,
        settings: settings,
        ownerFirstName: owner,
        catalog: catalog)
}

@MainActor func collectChat(
    _ client: ChatProviderClient,
    history: [Turn] = [Turn(role: .user, content: "hola")],
    tools: [ToolSpec] = [],
    timeout: TimeInterval = 5
) -> [ChatDelta] {
    do {
        return try runAsync(timeout: timeout) {
            var out: [ChatDelta] = []
            for try await delta in client.stream(history, tools: tools) {
                out.append(delta)
            }
            return out
        }
    } catch {
        expect(false, "stream no debía tirar \(error)")
        return []
    }
}

@MainActor func expectChatError(
    _ client: ChatProviderClient,
    _ want: ChatError, _ label: String,
    history: [Turn] = [Turn(role: .user, content: "hola")],
    timeout: TimeInterval = 5
) {
    do {
        _ = try runAsync(timeout: timeout) {
            for try await _ in client.stream(history, tools: []) {}
        }
        expect(false, "\(label): debía tirar \(want)")
    } catch let error as ChatError {
        expectEq(error, want, label)
    } catch {
        expect(false, "\(label): \(error) no es ChatError")
    }
}

@MainActor func expectVerify(
    _ client: ChatProviderClient, _ key: String,
    _ provider: ProviderDescriptor, _ want: ChatError, _ label: String
) {
    do {
        try runAsync { try await client.verify(key, provider: provider) }
        expect(false, "\(label): debía tirar \(want)")
    } catch let error as ChatError {
        expectEq(error, want, label)
    } catch {
        expect(false, "\(label): \(error) no es ChatError")
    }
}

func chatHosts(_ transport: ScriptedTransport) -> [String] {
    transport.requests.compactMap { $0.url?.host }
}

func chatBody(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody else { return [:] }
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
        return [:]
    }
}

func chatSystem(_ body: [String: Any]) -> String {
    let messages = body["messages"] as? [[String: Any]] ?? []
    return messages.first?["content"] as? String ?? ""
}
