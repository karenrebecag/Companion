import CompanionCore
import CompanionServices
import Foundation
import Testing

// DM1b. N2: one forced function call over ArbitrationShortlist.choiceSchema().
// No logprobs on a Chat function call, so confidence is never invented —
// see ArbiterClient's own comment on the WHY.

@Test @MainActor func arbiterClientTests() {
    testInventedIdReturnsNil()
    testValidIdReturnsEntry()
    testEmptyShortlistReturnsNilWithoutCallingProvider()
    testLowFastConfidenceEscalatesToStrongModel()
}

private let fastProvider = ProviderDescriptor(
    id: "fast", name: "Fast", baseURL: URL(string: "http://fast.test/v1")!,
    model: "haiku-class", secretKey: nil)
private let strongProvider = ProviderDescriptor(
    id: "strong", name: "Strong", baseURL: URL(string: "http://strong.test/v1")!,
    model: "big-brain", secretKey: nil)

private func twoEntryShortlist(topMass: Double, otherMass: Double) -> ArbitrationShortlist {
    ArbitrationShortlist(entries: [
        ShortlistEntry(
            id: "open_app:Safari", action: .openApp, args: ["app": .text("Safari")],
            mass: topMass),
        ShortlistEntry(
            id: "task:c0", action: .task, args: ["goal": .text("abre safari")],
            mass: otherMass),
    ])
}

private func makeClient(_ transport: ChatTransport) -> ArbiterClient {
    ArbiterClient(
        transport: transport, secrets: TestSecretStore(),
        fastModel: fastProvider, strongModel: strongProvider)
}

@MainActor private func arbitrate(
    _ client: ArbiterClient, utterance: String, shortlist: ArbitrationShortlist
) -> (entry: ShortlistEntry, confidence: Double)? {
    try! runAsync { await client.arbitrate(utterance: utterance, shortlist: shortlist) }
}

@MainActor private func testInventedIdReturnsNil() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: toolCallFixture(choice: "not_on_the_list")))
    let shortlist = twoEntryShortlist(topMass: 0.6, otherMass: 0.4)
    let result = arbitrate(makeClient(transport), utterance: "abre safari", shortlist: shortlist)
    expect(result == nil, "id inventado: nunca un id fuera de la shortlist")
}

@MainActor private func testValidIdReturnsEntry() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: toolCallFixture(choice: "open_app:Safari")))
    let shortlist = twoEntryShortlist(topMass: 0.6, otherMass: 0.4)
    guard let result = arbitrate(makeClient(transport), utterance: "abre safari", shortlist: shortlist)
    else {
        expect(false, "id valido: no debia ser nil")
        return
    }
    expectEq(result.entry.id, "open_app:Safari", "id valido: entry devuelta")
    // Agrees with the shortlist's own top-mass pick: confidence = that mass.
    expect(abs(result.confidence - 0.6) < 0.0001, "id valido: confianza = masa del top")
    expectEq(transport.requests.count, 1, "id valido: 0.6 no escala, un solo tiro")
}

@MainActor private func testEmptyShortlistReturnsNilWithoutCallingProvider() {
    let transport = ScriptedTransport()
    let empty = ArbitrationShortlist(entries: [])
    let result = arbitrate(makeClient(transport), utterance: "abre safari", shortlist: empty)
    expect(result == nil, "shortlist vacia: nil")
    expectEq(transport.requests.count, 0, "shortlist vacia: el proveedor nunca se llama")
}

@MainActor private func testLowFastConfidenceEscalatesToStrongModel() {
    let transport = ScriptedTransport()
    // Fast tier picks the top-mass entry, but its mass (0.3) is itself doubtful:
    // confidence inherits that 0.3 and falls under ArbitrationTier.fastDoubt.
    transport.enqueue(ScriptedReply(status: 200, body: toolCallFixture(choice: "open_app:Safari")))
    // Strong tier overrides with the other entry: a flat 0.6, not an invented number.
    transport.enqueue(ScriptedReply(status: 200, body: toolCallFixture(choice: "task:c0")))
    let shortlist = twoEntryShortlist(topMass: 0.3, otherMass: 0.2)
    guard let result = arbitrate(makeClient(transport), utterance: "abre safari", shortlist: shortlist)
    else {
        expect(false, "escala: no debia ser nil")
        return
    }
    expectEq(transport.requests.count, 2, "escala: rapido y luego fuerte")
    expectEq(
        transport.requests.first?.url?.absoluteString, fastProvider.endpoint?.absoluteString,
        "escala: primero pega al modelo rapido")
    expectEq(
        transport.requests.last?.url?.absoluteString, strongProvider.endpoint?.absoluteString,
        "escala: el segundo tiro pega al modelo fuerte")
    expectEq(result.entry.id, "task:c0", "escala: la decision final es la del modelo fuerte")
    expect(abs(result.confidence - 0.6) < 0.0001, "escala: el fuerte revierte el top -> 0.6 plano")
}

// MARK: - Fixtures

private func toolCallFixture(choice: String) -> Data {
    let args = "{\"choice\":\"\(choice)\"}"
    let obj: [String: Any] = [
        "choices": [
            [
                "message": [
                    "role": "assistant",
                    "tool_calls": [
                        [
                            "id": "call_1",
                            "type": "function",
                            "function": ["name": "arbitrate", "arguments": args],
                        ],
                    ],
                ],
            ],
        ],
    ]
    return try! JSONSerialization.data(withJSONObject: obj)
}
