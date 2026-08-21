import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func capabilityProbeTests() {
    testRemoteProvidersSkipTransport()
    testKeyedCustomProviderSkipsTransport()
    testOllamaAvailableWhenModelsReturns200()
    testOllamaUnavailableWhenModelsReturnsNon200()
    testOllamaUnavailableWhenTransportThrows()
    testOllamaProbeRequestShape()
    testLocalProviderUsesOwnBaseURL()
    testOllama200EmptyAndLargeBody()
    testOllamaNeverThrowsFromIsAvailable()
    testProbeTimeoutIsCopiedToRequest()
    testConcurrentRemoteAndLocal()
    testURLSessionChatTransportInstantiates()
}

@MainActor private func probeAvailable(
    _ probe: LiveCapabilityProbe, _ provider: ProviderDescriptor
) -> Bool {
    do {
        return try runAsync { await probe.isAvailable(provider) }
    } catch {
        expect(false, "probe: isAvailable no debía tirar \(error)")
        return false
    }
}

@MainActor func testRemoteProvidersSkipTransport() {
    let fake = FakeChatTransport()
    fake.error = URLError(.cannotConnectToHost)
    let probe = LiveCapabilityProbe(transport: fake)

    expect(probeAvailable(probe, .openAI),
           "probe: OpenAI es true sin llamar transporte")
    expect(probeAvailable(probe, .groq),
           "probe: Groq es true sin llamar transporte")
    expectEq(fake.requests.count, 0,
             "probe: OpenAI/Groq no tocan la red")
}

@MainActor func testKeyedCustomProviderSkipsTransport() {
    let fake = FakeChatTransport()
    fake.status = 500
    let probe = LiveCapabilityProbe(transport: fake)
    let custom = ProviderDescriptor(
        id: "openrouter",
        name: "OpenRouter",
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        model: "x",
        secretKey: .openRouter
    )

    expect(probeAvailable(probe, custom),
           "probe: secretKey distinta de nil es true")
    expectEq(fake.requests.count, 0,
             "probe: proveedor con llave no llama transporte")
}

@MainActor func testOllamaAvailableWhenModelsReturns200() {
    let fake = FakeChatTransport()
    fake.status = 200
    fake.body = Data("{\"data\":[]}".utf8)
    let probe = LiveCapabilityProbe(transport: fake)

    expect(probeAvailable(probe, .ollama),
           "probe: Ollama 200 en /models es true")
    expectEq(fake.requests.count, 1,
             "probe: Ollama llama transporte una vez")
}

@MainActor func testOllamaUnavailableWhenModelsReturnsNon200() {
    let codes = [0, 100, 201, 204, 301, 400, 401, 403, 404, 429, 500, 502, 503]
    for code in codes {
        let fake = FakeChatTransport()
        fake.status = code
        let probe = LiveCapabilityProbe(transport: fake)
        expect(!probeAvailable(probe, .ollama),
               "probe: Ollama HTTP \(code) es false")
    }
}

@MainActor func testOllamaUnavailableWhenTransportThrows() {
    let errors: [Error] = [
        URLError(.timedOut),
        URLError(.cannotConnectToHost),
        URLError(.notConnectedToInternet),
        CancellationError(),
        ChatError.unreachable,
        ChatError.timeout,
    ]
    for error in errors {
        let fake = FakeChatTransport()
        fake.error = error
        let probe = LiveCapabilityProbe(transport: fake)
        expect(!probeAvailable(probe, .ollama),
               "probe: transporte tira \(error) → false")
    }
}

@MainActor func testOllamaProbeRequestShape() {
    let fake = FakeChatTransport()
    fake.status = 200
    let probe = LiveCapabilityProbe(transport: fake)
    _ = probeAvailable(probe, .ollama)

    expectEq(fake.requests.count, 1, "probe: un GET por isAvailable")
    let req = fake.requests[0]
    expectEq(req.httpMethod, "GET", "probe: método GET")
    expectEq(
        req.url?.absoluteString ?? "",
        ProviderDescriptor.ollama.baseURL.absoluteString + "/models",
        "probe: URL es {baseURL}/models (concat, no appendingPath)")
    expectEq(req.timeoutInterval, 1, "probe: timeout default 1s")
    expect(req.httpBody == nil, "probe: GET sin body")
    expect(req.value(forHTTPHeaderField: "Authorization") == nil,
           "probe: Ollama no manda Authorization")
}

@MainActor func testLocalProviderUsesOwnBaseURL() {
    let fake = FakeChatTransport()
    fake.status = 200
    let probe = LiveCapabilityProbe(transport: fake)
    let local = ProviderDescriptor(
        id: "lmstudio",
        name: "LM Studio",
        baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
        model: "local",
        secretKey: nil
    )

    expect(probeAvailable(probe, local),
           "probe: local sin llave también pega /models")
    expectEq(
        fake.requests.first?.url?.absoluteString ?? "",
        "http://127.0.0.1:1234/v1/models",
        "probe: usa la base del descriptor, no la de Ollama")
}

@MainActor func testOllama200EmptyAndLargeBody() {
    let empty = FakeChatTransport()
    empty.status = 200
    empty.body = Data()
    expect(probeAvailable(LiveCapabilityProbe(transport: empty), .ollama),
           "probe: 200 con body vacío sigue true")

    let large = FakeChatTransport()
    large.status = 200
    large.body = Data(repeating: 0x61, count: 10_000)
    expect(probeAvailable(LiveCapabilityProbe(transport: large), .ollama),
           "probe: 200 con 10k bytes sigue true")
}

@MainActor func testOllamaNeverThrowsFromIsAvailable() {
    let fake = FakeChatTransport()
    fake.error = URLError(.badServerResponse)
    let probe = LiveCapabilityProbe(transport: fake)
    var threw = false
    do {
        _ = try runAsync { await probe.isAvailable(.ollama) }
    } catch {
        threw = true
        expect(false, "probe: isAvailable no debe propagar \(error)")
    }
    expect(!threw, "probe: isAvailable nunca tira")
}

@MainActor func testProbeTimeoutIsCopiedToRequest() {
    let fake = FakeChatTransport()
    fake.status = 200
    let probe = LiveCapabilityProbe(transport: fake, timeout: 0.25)
    _ = probeAvailable(probe, .ollama)
    expectEq(fake.requests.first?.timeoutInterval ?? -1, 0.25,
             "probe: timeout inyectado viaja en URLRequest")
}

@MainActor func testConcurrentRemoteAndLocal() {
    let fake = FakeChatTransport()
    fake.status = 200
    let probe = LiveCapabilityProbe(transport: fake)
    let pair: (Bool, Bool)
    do {
        pair = try runAsync {
            async let local = probe.isAvailable(.ollama)
            async let remote = probe.isAvailable(.openAI)
            return await (local, remote)
        }
    } catch {
        expect(false, "probe: concurrente no debía tirar \(error)")
        return
    }
    expect(pair.0, "probe: Ollama concurrente 200 es true")
    expect(pair.1, "probe: OpenAI concurrente es true")
    expectEq(fake.requests.count, 1,
             "probe: el remoto no suma llamadas")
}

@MainActor func testURLSessionChatTransportInstantiates() {
    let transport: any ChatTransport = URLSessionChatTransport()
    let custom = URLSessionChatTransport(session: .shared)
    _ = (transport, custom)
    expect(true, "transport: URLSessionChatTransport es ChatTransport")
}

final class FakeChatTransport: ChatTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status: Int = 200
    var body: Data = Data()
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let error { throw error }
        let url = request.url ?? URL(string: "http://127.0.0.1")!
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    ) {
        _ = request
        return (status, AsyncThrowingStream { $0.finish() })
    }
}
