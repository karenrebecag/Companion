import CompanionCore
import CompanionUI
@testable import CompanionServices
import Foundation
import Testing

// 9j-3: servidores MCP remotos como tools del realtime. OpenAI los ejecuta
// server-side; el cliente declara y aprueba. El wire es puro y se prueba sin red.
// La aprobacion en voz (hoja, sin sí hablado) vive en Approvals16q1Tests.

@Test @MainActor func mcpToolsTests() async {
    testConfigDecodeAndShape()
    testSessionUpdateCarriesServers()
    testApprovalRequestParsing()
    testApprovalResponseShape()
    testMCPRequestIsHighRisk()
    await testMCPRequestOpensTheSheetAndModelCannotSettleIt()
    await testSheetClickAnswersMCPApproval()
    await testSheetDenyAnswersNo()
    await testDroppedSheetAnswersNo()
    await testStaleOrDuplicateCloseSendsNothing()
    await testQueuedMCPRequestsAnswerInOrder()
    await testStopWhileMCPQueuedAnswersNo()
    await testUnansweredMCPRequestTimesOut()
    await testTeardownClearsPendingMCPApprovals()
}

func testConfigDecodeAndShape() {
    let json = #"[{"label":"docs","url":"https://x/mcp","requireApproval":"never","allowedTools":["search"]}]"#
    let servers = MCPServerConfig.load(fromJSON: Data(json.utf8))
    expectEq(servers.count, 1, "config: decodifica el arreglo")
    let obj = servers[0].realtimeObject()
    expectEq(obj["type"] as? String, "mcp", "wire: tipo mcp")
    expectEq(obj["server_label"] as? String, "docs", "wire: label")
    expectEq(obj["server_url"] as? String, "https://x/mcp", "wire: url")
    expectEq(obj["require_approval"] as? String, "always",
             "wire: un never del archivo se ignora, la aprobación no se relaja")
    expectEq(obj["allowed_tools"] as? [String], ["search"], "wire: tool filter")

    // Default seguro: este producto pregunta antes de actuar sobre el mundo.
    let bare = MCPServerConfig(label: "x", url: "https://y")
    expectEq(bare.realtimeObject()["require_approval"] as? String, "always",
             "wire: sin decir nada, la aprobación es obligatoria")
    expect(MCPServerConfig.load(fromJSON: Data("basura".utf8)).isEmpty,
           "config: un archivo malformado no truena — cero servidores")
}

func testSessionUpdateCarriesServers() {
    let json = RealtimeCodec.sessionUpdate(
        instructions: "x", tools: [], voice: nil, speed: 1.0,
        turnDetection: .serverVAD(silenceMs: 700),
        mcpServers: [MCPServerConfig(label: "docs", url: "https://x/mcp")])
    expect(json.contains(#""type":"mcp""#) || json.contains(#""type" : "mcp""#),
           "update: el servidor MCP viaja en tools")
    expect(json.contains("server_label"), "update: con su label")
}

func testApprovalRequestParsing() {
    let event = #"{"type":"conversation.item.added","item":{"type":"mcp_approval_request","id":"req1","server_label":"docs","name":"search","arguments":"{\"q\":\"x\"}"}}"#
    guard case .mcpApprovalRequest(let id, let server, let tool, _)
        = RealtimeCodec.parse(event) else {
        expect(false, "parse: mcp_approval_request se reconoce")
        return
    }
    expectEq(id, "req1", "parse: id del request")
    expectEq(server, "docs", "parse: servidor")
    expectEq(tool, "search", "parse: tool")
    expect(RealtimeCodec.parse(
        #"{"type":"conversation.item.added","item":{"type":"message"}}"#)
        == .ignored, "parse: otros items no son approvals")
}

func testApprovalResponseShape() {
    let json = RealtimeCodec.mcpApprovalResponse(requestId: "req1", approve: true)
    expect(json.contains("mcp_approval_response"), "response: tipo")
    expect(json.contains("req1"), "response: apunta al request")
    expect(json.contains("true"), "response: la decisión viaja")
}

func testMCPRequestIsHighRisk() {
    expectEq(ApprovalRisk.of(toolName: "docs/search"), .high,
             "riesgo: server/tool de un MCP propio pide la hoja")
}

@MainActor private func mcpHarness(
    timeout: TimeInterval = ApprovalTiming.autoDeny
) async -> (VoiceHarness, SessionModel) {
    // The merge with 16q-1 routes the MCP sheet through the one approvals
    // actor (`ParentToolGuard.decide`): the click, the deadline and the
    // brakes reach the server through it, and without it the request fails
    // closed. The fixture injects it where 20c wired `onApprovalClosed`.
    let actor = Approvals(clock: RealtimeClock(), timeout: timeout)
    let model = SessionModel(jobs: nil, approvals: actor)
    let h = makeVoiceHarness(approvals: actor, session: model)
    await h.session.start()
    await pumpUntil("mcp: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.mcpApprovalRequest(
        id: "req9", server: "docs", tool: "search", argumentsJSON: "{}"))
    await pumpUntil("mcp: la hoja lo tiene") {
        model.projection.approval?.requestId == "req9"
    }
    return (h, model)
}

/// (request id, approve) of every mcp_approval_response frame, decoded: a
/// substring test on the raw frame would pass on the id "true-1".
private func mcpVerdicts(_ h: VoiceHarness) -> [(id: String, approve: Bool)] {
    h.transport.sent.compactMap { frame in
        guard let data = frame.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = root["item"] as? [String: Any],
              item["type"] as? String == "mcp_approval_response",
              let id = item["approval_request_id"] as? String,
              let approve = item["approve"] as? Bool
        else { return nil }
        return (id, approve)
    }
}

/// El booleano del modelo no aprueba un MCP propio: solo la hoja.
@MainActor func testMCPRequestOpensTheSheetAndModelCannotSettleIt() async {
    let (h, model) = await mcpHarness()
    expectEq(model.projection.approval?.toolName, "docs/search",
             "mcp: la hoja muestra server/tool")
    let landed = await h.session.answerPendingApproval(true)
    await settle(0.1)
    expect(landed != .resolved, "mcp: resolve_approval no aterriza en un MCP")
    expect(mcpVerdicts(h).isEmpty, "mcp: el modelo no manda mcp_approval_response")
    expect(model.projection.approval?.requestId == "req9",
           "mcp: la hoja sigue esperando el clic")
}

@MainActor func testSheetClickAnswersMCPApproval() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await pumpUntil("mcp: el clic viaja al server") { !mcpVerdicts(h).isEmpty }
    let sent = mcpVerdicts(h)
    expectEq(sent.count, 1, "mcp: una sola respuesta")
    expectEq(sent.first?.id, "req9", "mcp: el clic apunta a su id")
    expectEq(sent.first?.approve, true, "mcp: el clic aprueba")
}

@MainActor func testSheetDenyAnswersNo() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalAnswered(requestId: "req9", approved: false, remember: false))
    await pumpUntil("mcp: el no viaja") { !mcpVerdicts(h).isEmpty }
    expectEq(mcpVerdicts(h).first?.approve, false, "mcp: el clic en No niega")
}

@MainActor func testDroppedSheetAnswersNo() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalDropped(requestId: "req9"))
    await pumpUntil("mcp: la hoja caida niega") { !mcpVerdicts(h).isEmpty }
    expectEq(mcpVerdicts(h).first?.approve, false, "mcp: sin clic no se aprueba")
}

@MainActor func testStaleOrDuplicateCloseSendsNothing() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await pumpUntil("mcp: primera respuesta") { mcpVerdicts(h).count == 1 }
    await h.session.approvalClosed(requestId: "req9")
    await h.session.approvalClosed(requestId: "nadie")
    await settle(0.1)
    expectEq(mcpVerdicts(h).count, 1, "mcp: un segundo cierre del mismo id no manda nada")
}

@MainActor func testQueuedMCPRequestsAnswerInOrder() async {
    let (h, model) = await mcpHarness()
    h.transport.yield(.mcpApprovalRequest(
        id: "req10", server: "docs", tool: "write", argumentsJSON: "{}"))
    await pumpUntil("mcp: la segunda queda en cola") { model.projection.approvalQueue.count == 2 }
    model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await pumpUntil("mcp: la segunda pasa al frente") {
        model.projection.approval?.requestId == "req10"
    }
    model.send(.approvalAnswered(requestId: "req10", approved: false, remember: false))
    await pumpUntil("mcp: ambas contestadas") { mcpVerdicts(h).count == 2 }
    let sent = mcpVerdicts(h)
    expectEq(sent.map(\.id), ["req9", "req10"], "mcp: en orden y con su id")
    expectEq(sent.map(\.approve), [true, false], "mcp: cada una con su verdad")
}

@MainActor func testStopWhileMCPQueuedAnswersNo() async {
    let (h, model) = await mcpHarness()
    // The harness does not pump snapshots into the model; Stop is a no-op at
    // idle, and the live app is never idle with a session open.
    model.send(.voice(h.watch.latest))
    model.send(.stop)
    await pumpUntil("mcp: Stop niega lo encolado") { !mcpVerdicts(h).isEmpty }
    expectEq(mcpVerdicts(h).first?.id, "req9", "mcp: Stop niega ese id")
    expectEq(mcpVerdicts(h).first?.approve, false, "mcp: Stop es un no")
}

@MainActor func testUnansweredMCPRequestTimesOut() async {
    let (h, model) = await mcpHarness(timeout: 0.05)
    await pumpUntil("mcp: sin clic, el plazo niega") { !mcpVerdicts(h).isEmpty }
    expectEq(mcpVerdicts(h).first?.approve, false, "mcp: vencer es un no")
    await pumpUntil("mcp: la hoja se cierra") { model.projection.approval == nil }
    await settle(0.1)
    expectEq(mcpVerdicts(h).count, 1, "mcp: el plazo y el cierre no duplican la respuesta")
}

@MainActor func testTeardownClearsPendingMCPApprovals() async {
    let (h, model) = await mcpHarness()
    await h.session.hangUp()
    await pumpUntil("mcp: colgar cierra la hoja") { model.projection.approval == nil }
    model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await settle(0.1)
    expect(!mcpVerdicts(h).contains { $0.approve },
           "mcp: tras colgar, un clic tardio no aprueba nada")
}
