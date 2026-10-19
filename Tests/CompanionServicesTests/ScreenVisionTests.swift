import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

/// Code review finding (MEDIUM): every catch in `summarize`/`content` swallowed
/// its error silently, unlike the sibling pattern in ArbiterClient. These pin
/// that an unexpected failure (network, decode) leaves a line in the log —
/// the "no key configured" early return is expected and stays silent.
@Test @MainActor func screenVisionLoggingTests() async {
    await testNetworkFailureIsLogged()
    await testMalformedResponseIsLogged()
}

@MainActor func testNetworkFailureIsLogged() async {
    let transport = ScriptedTransport()
    transport.stub(
        url: ProviderDescriptor.openRouter.endpoint!.absoluteString,
        ScriptedReply(error: URLError(.networkConnectionLost)))
    let vision = ScreenVision(secrets: TestSecretStore([.cerebras: "sk-test"]), transport: transport)
    let url = uniqueLogURL()

    let brief = await Log.capturing(to: url) {
        await vision.summarize(jpeg: Data([0xFF, 0xD8]), app: "Numbers")
    }

    expect(brief == nil, "network failure: sin brief")
    let text = readLog(url)
    expect(text.contains("[app]"), "network failure: queda una línea de log")
    expect(text.contains("sight"), "network failure: mensaje identificable")
}

@MainActor func testMalformedResponseIsLogged() async {
    let transport = ScriptedTransport()
    transport.stub(
        url: ProviderDescriptor.openRouter.endpoint!.absoluteString,
        ScriptedReply(status: 200, body: Data("not json".utf8)))
    let vision = ScreenVision(secrets: TestSecretStore([.cerebras: "sk-test"]), transport: transport)
    let url = uniqueLogURL()

    let brief = await Log.capturing(to: url) {
        await vision.summarize(jpeg: Data([0xFF, 0xD8]), app: "Numbers")
    }

    expect(brief == nil, "malformed: sin brief")
    let text = readLog(url)
    expect(text.contains("[app]"), "malformed: queda una línea de log")
    expect(text.contains("sight"), "malformed: mensaje identificable")
}

private func uniqueLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-log-\(UUID().uuidString).log")
}

private func readLog(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

@Test @MainActor func screenVisionProviderTests() async {
    await testCerebrasKeyOnlyReachesCerebras()
    await testCerebrasKeyReadsTheScreen()
}

@MainActor func testCerebrasKeyOnlyReachesCerebras() async {
    let transport = ScriptedTransport()
    transport.stub(.cerebrasVision, ScriptedReply(status: 200, body: visionReplyData))
    let vision = ScreenVision(secrets: TestSecretStore([.cerebras: "csk-test"]), transport: transport)

    let brief = await vision.summarize(jpeg: Data([0xFF, 0xD8]), app: "Numbers")

    expect(brief != nil, "cerebras: devuelve brief")
    let hosts = transport.requests.compactMap { $0.url?.host }
    expectEq(hosts, ["api.cerebras.ai"], "cerebras: la key solo viaja al host de Cerebras")
    expectEq(transport.requests.first?.value(forHTTPHeaderField: "Authorization"),
             "Bearer csk-test", "cerebras: Bearer de Cerebras")
    let body = visionBody(transport.requests.first)
    expectEq(body["model"] as? String, "qwen-3.8-27b", "cerebras: modelo qwen-3.8-27b")
    expectEq(body["reasoning_effort"] as? String, "none", "cerebras: sin razonamiento")
    expect(body["reasoning_format"] == nil, "cerebras: sin reasoning_format (qwen lo rechaza)")
}

@MainActor func testCerebrasKeyReadsTheScreen() async {
    let transport = ScriptedTransport()
    transport.stub(.cerebrasVision, ScriptedReply(status: 200, body: visionReplyData))
    let vision = ScreenVision(secrets: TestSecretStore([.cerebras: "sk-test"]), transport: transport)

    _ = await vision.summarize(jpeg: Data([0xFF, 0xD8]), app: "Numbers")

    let hosts = transport.requests.compactMap { $0.url?.host }
    expectEq(hosts, ["api.cerebras.ai"], "cerebras: la key solo viaja a Cerebras")
    expectEq(visionBody(transport.requests.first)["model"] as? String, "qwen-3.8-27b",
             "cerebras: modelo qwen-3.8-27b")
}

private let visionReplyData = Data(
    #"{"choices":[{"message":{"content":"SUMMARY: una ventana"}}]}"#.utf8)

private func visionBody(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}
