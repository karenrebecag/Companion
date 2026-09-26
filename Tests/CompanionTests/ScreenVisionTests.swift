import CompanionCore
@testable import CompanionServices
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
        url: ProviderDescriptor.openAI.endpoint!.absoluteString,
        ScriptedReply(error: URLError(.networkConnectionLost)))
    let vision = ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport)
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
        url: ProviderDescriptor.openAI.endpoint!.absoluteString,
        ScriptedReply(status: 200, body: Data("not json".utf8)))
    let vision = ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport)
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
