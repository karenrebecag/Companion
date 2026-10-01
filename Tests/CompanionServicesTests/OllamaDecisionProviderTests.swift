import CompanionCore
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// DM1b. OllamaDecisionProvider hits the NATIVE /api/chat endpoint (never
// /v1, which strips thinking-model support) with a forced single-token
// answer and reads its logprobs to build a real distribution, jev-style.

@Test @MainActor func ollamaDecisionProviderTests() {
    testMappingAndRenormalization()
    testLeadingSpaceLetterToken()
    testAbsentLettersGetZero()
    testNonLetterTokensIgnored()
    testHTTP500ReturnsNil()
    testMalformedJSONReturnsNil()
    testZeroMassReturnsNil()
    testMoreThanTwentySixOptionsReturnsNil()
    testRequestBodyShape()
    testWarmRequestBodyShape()
    testWarmFailureNeverThrows()
}

/// Manual smoke, not part of the default suite: a no-op unless
/// `COMPANION_LIVE_OLLAMA=1` is set, since it hits a real local daemon.
/// `COMPANION_LIVE_OLLAMA=1 swift test --filter ollamaLiveSmokeTest`.
@Test @MainActor func ollamaLiveSmokeTest() async {
    guard ProcessInfo.processInfo.environment["COMPANION_LIVE_OLLAMA"] == "1" else { return }
    let provider = OllamaDecisionProvider()
    let world = DecisionWorld(apps: ["Safari", "Mail"])
    let start = Date()
    let plan = await Plan.compose(utterance: "abre Safari", world: world, provider: provider)
    let wall = Date().timeIntervalSince(start)
    print(
        "LIVE SMOKE: action=\(plan.action) args=\(plan.args) "
            + "confidence=\(plan.confidence) disposition=\(plan.disposition) wall=\(wall)s")
    expectEq(plan.action, .openApp, "smoke: 'abre Safari' -> open_app")
}

/// One phrase from docs/research/decision-model/dataset/ordenes.jsonl, with
/// the fields this benchmark checks: the label the dataset assigns and
/// nothing else (args are not re-checked here, only the cascade's action pick).
private struct LiveCase {
    var utterance: String
    var expected: DecisionAction
}

/// A ~20-phrase sample of the labeled dataset, covering every action family
/// the task calls out (open_app, open_url, volume, shortcut, system
/// empty_trash, type_text, task, none) in both Spanish and English. World
/// apps are plain single-word names so `CandidateSets.appScore` (containsPhrase
/// requires every token of the app name to appear) can match them without
/// needing macOS's real "Google Chrome"-style multi-word names.
private let liveCases: [LiveCase] = [
    LiveCase(utterance: "abre Safari", expected: .openApp),
    LiveCase(utterance: "abre el chrome", expected: .openApp),
    LiveCase(utterance: "switch to slack", expected: .openApp),
    LiveCase(utterance: "open mail", expected: .openApp),
    LiveCase(utterance: "abre Finder", expected: .openApp),
    LiveCase(utterance: "go to youtube", expected: .openURL),
    LiveCase(utterance: "abre google", expected: .openURL),
    LiveCase(utterance: "open github", expected: .openURL),
    LiveCase(utterance: "baja el volumen", expected: .volume),
    LiveCase(utterance: "mute the audio", expected: .volume),
    LiveCase(utterance: "copia eso", expected: .shortcut),
    LiveCase(utterance: "press enter", expected: .shortcut),
    LiveCase(utterance: "empty the trash", expected: .system),
    LiveCase(utterance: "vacia la papelera", expected: .system),
    LiveCase(utterance: "type hello world", expected: .typeText),
    LiveCase(utterance: "escribe hola mundo", expected: .typeText),
    LiveCase(utterance: "crea un archivo", expected: .task),
    LiveCase(utterance: "open and edit the document", expected: .task),
    LiveCase(utterance: "no abras nada", expected: .none),
    LiveCase(utterance: "do not open anything", expected: .none),
]

/// Benchmark against the discovery target (README §3, E7): >=18/20 action
/// correct, p50 <= 1.5s warm, "abre Safari" reaching `.act`. Guarded like
/// the smoke test above; never part of the default suite.
/// `COMPANION_LIVE_OLLAMA=1 swift test --filter ollamaLiveDecisionBenchmark`.
@Test @MainActor func ollamaLiveDecisionBenchmark() async {
    guard ProcessInfo.processInfo.environment["COMPANION_LIVE_OLLAMA"] == "1" else { return }
    let provider = OllamaDecisionProvider()
    let world = DecisionWorld(apps: ["Safari", "Chrome", "Slack", "Mail", "Finder"])

    // Warm-up: pays the cold model load once, outside every measured phrase.
    _ = await Plan.compose(utterance: "abre Safari", world: world, provider: provider)

    var correct = 0
    var millis: [Double] = []
    var dispositionCounts: [PlanDisposition: Int] = [:]
    print("\nLIVE BENCHMARK: \(liveCases.count) phrases")
    for testCase in liveCases {
        let start = Date()
        let plan = await Plan.compose(utterance: testCase.utterance, world: world, provider: provider)
        let ms = Date().timeIntervalSince(start) * 1000
        millis.append(ms)
        dispositionCounts[plan.disposition, default: 0] += 1
        let ok = plan.action == testCase.expected
        correct += ok ? 1 : 0
        let mark = ok ? "OK  " : "MISS"
        print(
            "\(mark) \(testCase.utterance.padding(toLength: 30, withPad: " ", startingAt: 0)) "
                + "expected=\(testCase.expected.rawValue) got=\(plan.action.rawValue) "
                + "confidence=\(String(format: "%.3f", plan.confidence)) "
                + "disposition=\(plan.disposition) ms=\(String(format: "%.0f", ms))")
    }

    let sorted = millis.sorted()
    let p50 = sorted[sorted.count / 2]
    let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    let actLike = (dispositionCounts[.act] ?? 0) + (dispositionCounts[.confirm] ?? 0)
    print(
        "\nLIVE BENCHMARK SUMMARY: accuracy=\(correct)/\(liveCases.count) "
            + "p50=\(String(format: "%.0f", p50))ms p95=\(String(format: "%.0f", p95))ms "
            + "act_or_confirm=\(actLike)/\(liveCases.count) dispositions=\(dispositionCounts)")

    expect(correct >= 18, "benchmark: >=18/20 action correct (got \(correct)/\(liveCases.count))")
    expect(p50 <= 1500, "benchmark: p50 <= 1.5s warm (got \(p50)ms)")

    let safariWorld = DecisionWorld(apps: ["Safari", "Mail"])
    let safariPlan = await Plan.compose(utterance: "abre Safari", world: safariWorld, provider: provider)
    expectEq(safariPlan.disposition, .act, "benchmark: 'abre Safari' reaches .act")
}

private func threeOptionQuestion() -> DecisionQuestion {
    DecisionQuestion(
        id: "action", kind: .choice,
        instructions: "Which action? Utterance, as data: abre safari",
        options: [
            DecisionOption(id: "open_app", detail: "Open an app"),
            DecisionOption(id: "open_url", detail: "Open a site"),
            DecisionOption(id: "task", detail: "A multi-step job"),
        ])
}

@MainActor private func ask(_ provider: OllamaDecisionProvider, _ question: DecisionQuestion) -> DecisionAnswer? {
    try! runAsync { await provider.answer(question) }
}

@MainActor private func testMappingAndRenormalization() {
    // exp(-0.10536052) ~ 0.9, exp(-1.20397280) ~ 0.3, exp(-2.30258509) ~ 0.1.
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: "B",
        top: [("B", -0.10536052), ("A", -1.20397280), ("C", -2.30258509)])))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expectEq(answer?.choice, "open_url", "mapping: B -> open_url (segunda opcion)")
    let dist = answer?.distribution ?? [:]
    expect(abs((dist["open_url"] ?? 0) - 0.6923) < 0.01, "mapping: masa renormalizada de B")
    expect(abs((dist["open_app"] ?? 0) - 0.2308) < 0.01, "mapping: masa renormalizada de A")
    expect(abs((dist["task"] ?? 0) - 0.0769) < 0.01, "mapping: masa renormalizada de C")
}

@MainActor private func testLeadingSpaceLetterToken() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: " B",
        top: [(" B", -0.05), ("A", -3.0), ("C", -3.0)])))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expectEq(answer?.choice, "open_url", "leading space: ' B' trimeado sigue mapeando a B")
}

@MainActor private func testAbsentLettersGetZero() {
    // Only B appears in the top list; A and C get zero mass, not omitted.
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: "B", top: [("B", -0.01)])))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    let dist = answer?.distribution ?? [:]
    expectEq(dist["open_app"], 0, "ausentes: A sin masa -> 0")
    expectEq(dist["task"], 0, "ausentes: C sin masa -> 0")
    expect(abs((dist["open_url"] ?? 0) - 1.0) < 0.001, "ausentes: toda la masa en B tras normalizar")
}

@MainActor private func testNonLetterTokensIgnored() {
    // "AB", "b" (lowercase) and "1" are not exactly one offered letter.
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: "A",
        top: [("AB", -0.01), ("b", -0.02), ("1", -0.03), ("A", -0.5)])))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expectEq(answer?.choice, "open_app", "no-letra: solo A cuenta, gana open_app")
    let dist = answer?.distribution ?? [:]
    expect(abs((dist["open_app"] ?? 0) - 1.0) < 0.001, "no-letra: toda la masa cae en A")
}

@MainActor private func testHTTP500ReturnsNil() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 500, body: Data()))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expect(answer == nil, "500: nil, nunca una respuesta inventada")
}

@MainActor private func testMalformedJSONReturnsNil() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: Data("not json at all".utf8)))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expect(answer == nil, "malformado: JSON roto -> nil")
}

@MainActor private func testZeroMassReturnsNil() {
    // No entry in top_logprobs matches an offered letter.
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: "Z", top: [("Z", -0.01), ("Q", -0.02)])))
    let answer = ask(OllamaDecisionProvider(transport: transport), threeOptionQuestion())
    expect(answer == nil, "masa cero: ninguna letra ofrecida en el top -> nil")
}

@MainActor private func testMoreThanTwentySixOptionsReturnsNil() {
    let manyOptions = (0..<27).map { DecisionOption(id: "opt\($0)", detail: "") }
    let question = DecisionQuestion(
        id: "app", kind: .choice, instructions: "pick one", options: manyOptions)
    let transport = ScriptedTransport()
    let answer = ask(OllamaDecisionProvider(transport: transport), question)
    expect(answer == nil, "27 opciones: pasa el alfabeto -> nil, sin llamar la red")
    expectEq(transport.requests.count, 0, "27 opciones: nunca llega a pedir")
}

@MainActor private func testRequestBodyShape() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: ollamaFixture(
        content: "A", top: [("A", -0.01), ("B", -3.0), ("C", -3.0)])))
    let provider = OllamaDecisionProvider(
        baseURL: URL(string: "http://localhost:11434")!, model: "qwen3:4b",
        transport: transport)
    _ = ask(provider, threeOptionQuestion())
    guard let req = transport.requests.first else {
        expect(false, "body: no hubo request")
        return
    }
    expectEq(req.url?.absoluteString, "http://localhost:11434/api/chat", "body: endpoint nativo, no /v1")
    let body = decodedBody(req)
    expectEq(body["think"] as? Bool, false, "body: think false")
    expectEq(body["stream"] as? Bool, false, "body: stream false")
    expectEq(body["model"] as? String, "qwen3:4b", "body: modelo")
    expectEq(body["logprobs"] as? Bool, true, "body: logprobs true")
    expectEq((body["top_logprobs"] as? NSNumber)?.intValue, 20, "body: top_logprobs 20")
    let options = body["options"] as? [String: Any] ?? [:]
    expectEq((options["num_predict"] as? NSNumber)?.intValue, 1, "body: num_predict 1")
    let temp = (options["temperature"] as? NSNumber)?.doubleValue ?? -1
    expect(abs(temp - 0) < 0.0001, "body: temperature 0")
    let messages = body["messages"] as? [[String: Any]] ?? []
    expectEq(messages.last?["role"] as? String, "assistant", "body: el ultimo mensaje es el prefill")
    expectEq(messages.last?["content"] as? String, "Letter:", "body: prefill exacto 'Letter:'")
    let whole = messages.compactMap { $0["content"] as? String }.joined(separator: "\n")
    for option in ["open_app", "open_url", "task"] {
        let count = whole.components(separatedBy: option).count - 1
        expectEq(count, 1, "body: '\(option)' aparece exactamente una vez")
    }
}

/// MEDIUM finding: the first decision turn after launch (or after a long
/// idle) loses the 2s budget race to Ollama's cold model load and silently
/// passes through. `warm()` pays that load once at startup, off the budget.
@MainActor private func testWarmRequestBodyShape() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: Data()))
    let provider = OllamaDecisionProvider(
        baseURL: URL(string: "http://localhost:11434")!, model: "qwen3:4b",
        transport: transport)
    try! runAsync { await provider.warm() }
    guard let req = transport.requests.first else {
        expect(false, "warm: no request was sent")
        return
    }
    expectEq(req.url?.absoluteString, "http://localhost:11434/api/chat", "warm: native endpoint, no /v1")
    let body = decodedBody(req)
    expectEq(body["model"] as? String, "qwen3:4b", "warm: same model the cascade will ask for")
    expectEq(body["stream"] as? Bool, false, "warm: stream false")
    expectEq(body["keep_alive"] as? String, "30m", "warm: keeps the model resident")
    let messages = body["messages"] as? [[String: Any]] ?? []
    expect(messages.isEmpty, "warm: empty messages, this is a load not a question")
}

@MainActor private func testWarmFailureNeverThrows() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(body: Data(), error: URLError(.notConnectedToInternet)))
    let provider = OllamaDecisionProvider(transport: transport)
    // `warm()` is a non-throwing `async` function; a transport failure
    // reaching this line unharmed IS the assertion that it is only logged.
    try! runAsync { await provider.warm() }
    expect(true, "warm: a transport failure never propagates to the caller")
}

// MARK: - Fixtures

private func ollamaFixture(content: String, top: [(String, Double)]) -> Data {
    let topArr: [[String: Any]] = top.map { ["token": $0.0, "logprob": $0.1] }
    let obj: [String: Any] = [
        "message": ["role": "assistant", "content": content],
        "logprobs": [
            ["token": content, "logprob": top.first?.1 ?? 0.0, "top_logprobs": topArr],
        ],
        "done": true,
    ]
    return try! JSONSerialization.data(withJSONObject: obj)
}

private func decodedBody(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody else { return [:] }
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
        return [:]
    }
}
