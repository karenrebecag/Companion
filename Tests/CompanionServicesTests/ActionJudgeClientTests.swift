import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// The judge's adapter: one request per step, verdicts read by id, and every
// failure (no provider, a bad status, a bad reply, the deadline) fails closed.

private let words = UserWords(heard: "sube el informe a drive")!

private func request() -> ActionJudgeRequest {
    let candidates = [
        JudgeCandidate(id: "1", tool: "browser_set_files", argumentsJSON: #"{"host":"drive.google.com"}"#),
        JudgeCandidate(id: "2", tool: "write_file", argumentsJSON: #"{"path":"notas.md"}"#),
    ]
    return ActionJudgeRequest(words: words, candidates: candidates)!
}

private func reply(_ verdicts: String) -> Data {
    let arguments = #"{"verdicts":\#(verdicts)}"#
    let object: [String: Any] = [
        "choices": [[
            "message": [
                "role": "assistant",
                "tool_calls": [["id": "c1", "type": "function",
                                "function": ["name": "judge_actions", "arguments": arguments]]],
            ],
        ]],
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

private let goodVerdicts = #"[{"id":"2","effect":"undoable","covered":false},{"id":"1","effect":"reaches_someone","covered":true}]"#

@MainActor private func judge(
    _ transport: ChatTransport, keys: [SecretKey: String] = [.cerebras: "sk-test"],
    ollamaModel: String? = nil, timeout: TimeInterval = 4
) -> [JudgeOpinion?] {
    let client = ActionJudgeClient(
        transport: transport, secrets: TestSecretStore(keys), ollamaModel: { ollamaModel },
        settings: ActionJudgeSettings(enabled: true, timeout: timeout))
    let judged = request()
    return try! runAsync { await client.judge(judged) }
}

@Test @MainActor func oneRequestReadsEachVerdictByItsIdInTheRequestOrder() {
    let transport = ScriptedTransport()
    transport.enqueue(ScriptedReply(status: 200, body: reply(goodVerdicts)))
    let opinions = judge(transport)
    expectEq(opinions, [JudgeOpinion(effect: .reachesSomeone, covered: true),
                        JudgeOpinion(effect: .undoable, covered: false)],
             "judge adapter: los veredictos siguen el orden de la peticion")
    expectEq(transport.requests.count, 1, "judge adapter: un solo pedido para todo el lote")
}

@Test @MainActor func noProviderMeansNoRequestAndNoLowering() {
    let transport = ScriptedTransport()
    expectEq(judge(transport, keys: [:], ollamaModel: nil), [nil, nil], "judge adapter: sin proveedor, sin veredicto")
    expect(transport.requests.isEmpty, "judge adapter: sin proveedor no sale ningun pedido")
}

@Test @MainActor func aBadStatusOrAMalformedReplyFailsEveryActionClosed() {
    let badStatus = ScriptedTransport()
    badStatus.enqueue(ScriptedReply(status: 500, body: reply(goodVerdicts)))
    expectEq(judge(badStatus), [nil, nil], "judge adapter: un 500 no baja nada")

    let malformed = ScriptedTransport()
    malformed.enqueue(ScriptedReply(status: 200, body: reply(#"[{"id":"1","effect":"undoable","covered":true}]"#)))
    expectEq(judge(malformed), [nil, nil], "judge adapter: una respuesta incompleta falla el lote")
}

@Test @MainActor func aModelPastTheDeadlineFailsClosed() {
    let slow = ScriptedTransport()
    slow.enqueue(ScriptedReply(status: 200, body: reply(goodVerdicts), hangNanoseconds: 5_000_000_000))
    expectEq(judge(slow, timeout: 0.05), [nil, nil], "judge adapter: pasado el presupuesto, las hojas se quedan")
}
