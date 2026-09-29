import CompanionCore
import CompanionUI
@testable import CompanionServices
import Foundation
import Testing

// 9j-3: servidores MCP remotos como tools del realtime. OpenAI los ejecuta
// server-side; el cliente declara y aprueba. El wire es puro y se prueba sin red.

@Test @MainActor func mcpToolsTests() async {
    testConfigDecodeAndShape()
    testSessionUpdateCarriesServers()
    testApprovalRequestParsing()
    testApprovalResponseShape()
    testMCPRequestIsHighRisk()
    await testMCPRequestOpensTheSheetAndModelCannotSettleIt()
    await testSheetClickAnswersMCPApproval()
    await testSheetDenyAndDropAnswerNo()
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

@MainActor private func mcpHarness() async -> (VoiceHarness, SessionModel) {
    let model = SessionModel(jobs: nil, approvals: nil)
    let h = makeVoiceHarness(session: model)
    let session = h.session
    model.onApprovalClosed = { id, approved in
        Task { await session.approvalClosed(id, approved: approved) }
    }
    await h.session.start()
    await pumpUntil("mcp: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.mcpApprovalRequest(
        id: "req9", server: "docs", tool: "search", argumentsJSON: "{}"))
    await pumpUntil("mcp: la hoja lo tiene") {
        model.projection.approval?.requestId == "req9"
    }
    return (h, model)
}

private func mcpResponses(_ h: VoiceHarness) -> [String] {
    h.transport.sent.filter { $0.contains("mcp_approval_response") }
}

/// El booleano del modelo no aprueba un MCP propio: solo la hoja.
@MainActor func testMCPRequestOpensTheSheetAndModelCannotSettleIt() async {
    let (h, model) = await mcpHarness()
    expectEq(model.projection.approval?.toolName, "docs/search",
             "mcp: la hoja muestra server/tool")
    let landed = await h.session.answerPendingApproval(true)
    await settle(0.1)
    expect(!landed, "mcp: resolve_approval no aterriza en un MCP")
    expect(mcpResponses(h).isEmpty, "mcp: el modelo no manda mcp_approval_response")
    expect(model.projection.approval?.requestId == "req9",
           "mcp: la hoja sigue esperando el clic")
}

@MainActor func testSheetClickAnswersMCPApproval() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await pumpUntil("mcp: el clic viaja al server") { !mcpResponses(h).isEmpty }
    let sent = mcpResponses(h)
    expect(sent.count == 1 && sent.first?.contains("req9") == true
           && sent.first?.contains("true") == true,
           "mcp: el clic aprueba con su id")
}

@MainActor func testSheetDenyAndDropAnswerNo() async {
    let (h, model) = await mcpHarness()
    model.send(.approvalAnswered(requestId: "req9", approved: false, remember: false))
    await pumpUntil("mcp: el no viaja") { !mcpResponses(h).isEmpty }
    expect(mcpResponses(h).first?.contains("false") == true, "mcp: el clic en No niega")

    let (h2, model2) = await mcpHarness()
    model2.send(.approvalDropped(requestId: "req9"))
    await pumpUntil("mcp: la hoja caida niega") { !mcpResponses(h2).isEmpty }
    expect(mcpResponses(h2).first?.contains("false") == true, "mcp: sin clic no se aprueba")
}
