import CompanionCore
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
    await testMCPApprovalsKeepTheirPreviousSpokenPathUntilTheyHaveASheet()
}

func testConfigDecodeAndShape() {
    let json = #"[{"label":"docs","url":"https://x/mcp","requireApproval":"never","allowedTools":["search"]}]"#
    let servers = MCPServerConfig.load(fromJSON: Data(json.utf8))
    expectEq(servers.count, 1, "config: decodifica el arreglo")
    let obj = servers[0].realtimeObject()
    expectEq(obj["type"] as? String, "mcp", "wire: tipo mcp")
    expectEq(obj["server_label"] as? String, "docs", "wire: label")
    expectEq(obj["server_url"] as? String, "https://x/mcp", "wire: url")
    expectEq(obj["require_approval"] as? String, "never",
             "wire: el archivo puede relajar la aprobación por servidor")
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

/// Provisional (review 16h-2, final adjustment): an MCP approval only exists
/// in realtime, where there is no sheet for it. Until Karen chooses between
/// a sheet of its own and an explicit "no", it keeps the spoken path it had
/// before 16h-2: the yes resolves it and travels to the server.
@MainActor func testMCPApprovalsKeepTheirPreviousSpokenPathUntilTheyHaveASheet() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("mcp: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.mcpApprovalRequest(
        id: "req9", server: "docs", tool: "search", argumentsJSON: "{}"))
    await pumpUntilAsync("mcp: la sesión la tiene") { await h.session.pendingMCPApproval != nil }
    let before = h.transport.sent.count
    let landed = await h.session.answerPendingApproval(true)
    expectEq(landed, .resolved, "mcp (provisional): el sí hablado la resuelve como antes de 16h-2")
    let added = Array(h.transport.sent.dropFirst(before))
    expect(added.contains { $0.contains("mcp_approval_response") && $0.contains("req9") },
           "mcp (provisional): la aprobación viaja al server con su id")
}
