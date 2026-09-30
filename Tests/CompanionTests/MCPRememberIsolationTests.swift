import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Integration fix round 1, item 1 (C3): the merge routes the realtime MCP
// request through `ParentToolGuard.answer`, which consults the remembered
// decisions keyed by tool name. An MCP server names its own tools, so a
// remote `run_shell` must never inherit what the user remembered for the
// local one, in either direction, and must never be remembered itself.

@Test @MainActor func mcpRememberIsolationTests() async {
    testAnMCPRequestHasNoApprovalKey()
    await testTheGuardNeverAnswersAnMCPRequestFromMemory()
    await testRememberingAnMCPAnswerStoresNothing()
    await testARememberedLocalYesDoesNotReachAnMCPToolOfTheSameName()
    await testARememberedLocalNoDoesNotReachAnMCPToolOfTheSameName()
}

private let lsArgs = #"{"command":"ls"}"#

private func localShell(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: #"{"command":"ls -la"}"#)
}

private func mcpShell(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "run_shell", inputJSON: lsArgs, isMCP: true)
}

/// A provider that remembers "yes" for anything it is asked about: only the
/// guard's own check can keep an MCP request away from it.
private final class RemembersEverything: ApprovalsProvider, @unchecked Sendable {
    var asked: [String] = []
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        asked.append(approval.requestId)
        return ApprovalResponse(requestId: approval.requestId, approved: false)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { false }
    func remembered(_ approval: ApprovalRequest) async -> Bool? { true }
}

@MainActor func testAnMCPRequestHasNoApprovalKey() {
    expect(ApprovalKey.from(localShell("l")) != nil, "mcp recordar: el run_shell local si tiene clave")
    expect(ApprovalKey.from(mcpShell("m")) == nil, "mcp recordar: un MCP llamado run_shell no tiene clave")
    let write = ApprovalRequest(requestId: "w", toolName: "write_file", summary: "",
                                inputJSON: #"{"path":"/tmp/a"}"#, isMCP: true)
    expect(ApprovalKey.from(write) == nil, "mcp recordar: ni un MCP llamado write_file")
}

@MainActor func testTheGuardNeverAnswersAnMCPRequestFromMemory() async {
    let provider = RemembersEverything()
    let guardian = ParentToolGuard(approvals: provider)
    let answer = await guardian.answer(mcpShell("m1"), parked: nil)
    expectEq(answer, .denied, "mcp recordar: la hoja (que niega) contesta, no la memoria")
    expectEq(provider.asked, ["m1"], "mcp recordar: la peticion MCP llega a la hoja")
}

@MainActor func testRememberingAnMCPAnswerStoresNothing() async {
    let actor = Approvals(clock: RealtimeClock())
    let parked = Task.detached { await actor.request(mcpShell("m1")) }
    await resolveWhenParked(actor, "m1", approved: true, "mcp recordar: la hoja espera")
    let response = await parked.value
    expect(!response.remember, "mcp recordar: la respuesta no dice que se recordo")
    expect(await actor.remembered(localShell("l1")) == nil,
           "mcp recordar: un si con recordar a un MCP no autoriza el run_shell local")
}

/// `pumpUntilAsync` re-checks its predicate once more at the end, so the
/// resolve that must happen exactly once lives outside it.
private func resolveWhenParked(
    _ actor: Approvals, _ id: String, approved: Bool, _ label: String
) async {
    var done = false
    await pumpUntilAsync(label) {
        if !done { done = await actor.resolve(requestId: id, approved: approved, remember: true) }
        return done
    }
}

/// Remembers `run_shell(ls *)` for the local tool with `approved`.
private func actorRememberingLocalShell(_ approved: Bool) async -> Approvals {
    let actor = Approvals(clock: RealtimeClock())
    let parked = Task.detached { await actor.request(localShell("local")) }
    await resolveWhenParked(actor, "local", approved: approved, "mcp recordar: la local espera")
    _ = await parked.value
    expectEq(await actor.remembered(localShell("again")), approved, "mcp recordar: previo, la regla local existe")
    return actor
}

private func mcpVerdictCount(_ h: VoiceHarness) -> Int {
    h.transport.sent.filter { $0.contains("mcp_approval_response") }.count
}

@MainActor private func anMCPShellParksDespiteMemory(_ approved: Bool, _ label: String) async {
    let actor = await actorRememberingLocalShell(approved)
    let model = SessionModel(jobs: nil, approvals: actor)
    let h = makeVoiceHarness(approvals: actor, session: model)
    await h.session.start()
    await pumpUntil("\(label): escuchando") { h.watch.latest.state == .listening }
    let deciding = Task { await h.session.noteMCPApproval(mcpShell("m1")) }
    await pumpUntil("\(label): la hoja muestra el MCP") { model.projection.approval?.requestId == "m1" }
    await settle(0.1)
    expectEq(mcpVerdictCount(h), 0, "\(label): nada se contesto solo")
    expectEq(model.projection.approval?.requestId, "m1", "\(label): sigue esperando su clic")
    model.send(.approvalAnswered(requestId: "m1", approved: false, remember: false))
    await deciding.value
    await h.session.hangUp()
}

@MainActor func testARememberedLocalYesDoesNotReachAnMCPToolOfTheSameName() async {
    await anMCPShellParksDespiteMemory(true, "mcp recordar si")
}

@MainActor func testARememberedLocalNoDoesNotReachAnMCPToolOfTheSameName() async {
    await anMCPShellParksDespiteMemory(false, "mcp recordar no")
}
