import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionServices

private let clickCall = ToolCallRef(id: "c1", name: "click", arguments: #"{"id":1}"#)

private func clickRequest() -> ApprovalRequest {
    ApprovalRequest(
        requestId: "r-click", toolName: "click", summary: "click Delete in Mail",
        inputJSON: #"{"label":"Delete","app":"Mail"}"#)
}

private func gate(
    _ owner: FakeOwnerCheck?, on: Bool = true, disabled: LockedBox<Int> = LockedBox(0)
) -> QAGate {
    QAGate(
        enabled: { on }, owner: owner, disableQA: { disabled.withLock { $0 += 1 } }, language: { .en },
        classify: { request, call, said in QALiveBand.band(request: request, call: call, said: said) })
}

private func tools() -> FakeParentTools {
    let tools = FakeParentTools(handledNames: ["click", "look"], specNames: ["click", "look"])
    tools.setScriptedApproval(clickRequest())
    return tools
}

private func verdict(
    _ guardian: ParentToolGuard, _ tools: FakeParentTools
) async -> ParentToolGuard.Verdict {
    await guardian.verdict(clickCall, said: "", language: .en, tools: tools, parked: nil)
}

@Test func inQAADestructiveClickAsksTheOwnerAndNeverOpensASheet() async {
    let approvals = ScriptedApprovals(answer: true)
    let owner = FakeOwnerCheck(result: .confirmed)
    let fake = tools()
    let result = await verdict(ParentToolGuard(approvals: approvals, qaGate: gate(owner)), fake)
    expect(result.denial == nil, "con el dedo, actua")
    expectEq(owner.calls.count, 1, "una prueba de dueña")
    expectEq(approvals.requests.count, 0, "ninguna hoja")
    expectEq(fake.grantedCalls.map(\.requestId), ["r-click"], "el runner recibe el permiso (su ticket)")
}

@Test func aRefusedOwnerCheckAnswersOwnerRefusedAndCountsAsADenial() async {
    let result = await verdict(
        ParentToolGuard(approvals: ScriptedApprovals(answer: true), qaGate: gate(FakeOwnerCheck(result: .refused))),
        tools())
    expect(result.denial?.output.hasPrefix(BridgeCode.ownerRefused) == true, "owner_refused, no denied_by_user")
    expectEq(result.answer, .denied, "cuenta para el enfriamiento")
}

@Test func anUnavailableOwnerCheckDoesNotCountAsADenialAndTurnsQAOff() async {
    let disabled = LockedBox(0)
    let result = await verdict(
        ParentToolGuard(
            approvals: ScriptedApprovals(answer: true),
            qaGate: gate(FakeOwnerCheck(result: .unavailable), disabled: disabled)),
        tools())
    expect(result.denial?.output.hasPrefix(BridgeCode.ownerUnavailable) == true, "owner_unavailable")
    expectEq(result.answer, .ownerUnavailable, "nadie dijo que no")
    expectEq(disabled.value, 1, "el modo QA se apaga")
}

@Test func outsideQATheSheetIsTheUsualOne() async {
    let approvals = ScriptedApprovals(answer: true)
    let owner = FakeOwnerCheck()
    let result = await verdict(ParentToolGuard(approvals: approvals, qaGate: gate(owner, on: false)), tools())
    expect(result.denial == nil, "la hoja contesto que si")
    expectEq(approvals.requests.map(\.toolName), ["click"], "se pidio la hoja de siempre")
    expectEq(owner.calls.count, 0, "sin prueba de dueña")
}

@Test func aRememberedNoOutranksQAMode() async {
    // open_url is the rememberable one, and QA would let it act: only the "no" stops it.
    let url = ToolCallRef(id: "c2", name: "open_url", arguments: #"{"url":"https://example.com"}"#)
    let fake = FakeParentTools(handledNames: ["open_url"], specNames: ["open_url"])
    fake.setScriptedApproval(ApprovalRequest(
        requestId: "r-url", toolName: "open_url", summary: "open example.com", inputJSON: url.arguments))
    let guardian = ParentToolGuard(
        approvals: ScriptedApprovals(answer: true, remembered: false), qaGate: gate(FakeOwnerCheck()))
    let result = await guardian.verdict(url, said: "", language: .en, tools: fake, parked: nil)
    expect(result.denial != nil, "lo que ella pidio recordar como no sigue siendo no")
}

@Test func theLiveBandKeepsTerminalsAndDestructiveTargetsCriticalAndSafeCallsFree() {
    func band(_ tool: String, _ args: String, input: String = "{}", mcp: Bool = false) -> ActionBand {
        let request = ApprovalRequest(
            requestId: "r", toolName: tool, summary: "", inputJSON: input, isMCP: mcp)
        return QALiveBand.band(
            request: request, call: ToolCallRef(id: "c", name: tool, arguments: args), said: "")
    }
    expectEq(band("type_text", #"{"text":"ls"}"#, input: #"{"terminal":true}"#), .critical, "terminal")
    expectEq(band("type_text", #"{"text":"hola"}"#, input: #"{"terminal":false}"#), .act, "campo normal")
    expectEq(band("click", #"{"id":1}"#), .critical, "el runner solo pregunta por clics destructivos")
    expectEq(band("open_url", #"{"url":"https://example.com"}"#), .act, "abrir una URL es navegar")
    expectEq(band("anything", "{}", mcp: true), .critical, "todo MCP")
    expectEq(band("tool_nobody_classified", "{}"), .critical, "sin clasificar sube")
}

// MARK: - the bridge in QA mode

private func helloLine(_ id: Int) -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
}

private func callLine(_ id: Int, _ name: String, _ arguments: String = "{}") -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
}

@Test func helloListsTheQAToolsOnlyWhileTheScopeIsOn() async {
    for on in [false, true] {
        let session = BridgeSession(
            tools: QARunner(
                driving: FakeQADriving(), waiter: TurnWaiter(limit: { _ in }), scope: { on }, language: { .en }),
            guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
            token: { "tok" }, language: { .en }, accessibility: { true }, qaScope: { on })
        let hello = await session.handle(line: helloLine(1))
        expectEq(hello.reply.contains("companion_ask"), on, "scope \(on)")
        let call = await session.handle(line: callLine(2, "companion_ask", #"{"text":"x"}"#))
        expectEq(call.reply.contains(BridgeCode.unknownTool), !on, "scope \(on): unknown_tool sin QA")
    }
}

@Test func theSessionSheetStaysAClickAndNamesTheQAGrant() async {
    let approvals = ScriptedApprovals(answer: true)
    let owner = FakeOwnerCheck()
    let session = BridgeSession(
        tools: tools(), guard: ParentToolGuard(approvals: approvals, qaGate: gate(owner)),
        token: { "tok" }, language: { .en }, accessibility: { true }, qaScope: { true })
    _ = await session.handle(line: helloLine(1))
    _ = await session.handle(line: callLine(2, "look"))
    let sheet = approvals.requests.first
    expectEq(sheet?.toolName, BridgePolicy.sessionApprovalTool, "la hoja de sesion se pide")
    expectEq(sheet?.summary, BridgeCopy.sheetTitle(.en, qa: true), "dice el alcance")
    expect(sheet?.inputJSON.contains(#""qa":true"#) == true, "la hoja la pinta con el titulo de QA")
    expectEq(owner.calls.count, 0, "el agente no la contesta con un dedo")
}

@Test func aCriticalDirectCallInQAAnswersOwnerRefusedOverTheWire() async {
    let approvals = ScriptedApprovals(answer: true)
    let session = BridgeSession(
        tools: tools(),
        guard: ParentToolGuard(approvals: approvals, qaGate: gate(FakeOwnerCheck(result: .refused))),
        token: { "tok" }, language: { .en }, accessibility: { true }, qaScope: { true })
    _ = await session.handle(line: helloLine(1))
    let reply = await session.handle(line: callLine(2, "click"))
    expect(reply.reply.contains(BridgeCode.ownerRefused), "owner_refused")
    expectEq(approvals.requests.map(\.toolName), [BridgePolicy.sessionApprovalTool], "solo la hoja de sesion")
}

@Test func theQAIdleCeilingKeepsALongQASessionAliveUntilItsOwnLimit() async {
    let clock = IdleClock()
    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true }, now: { clock.now },
        idleTimeout: 60, idleCheckInterval: 3600, qaScope: { true })
    let pair = BridgePair()
    let serving = await openSession(session, pair)
    clock.advance(BridgePolicy.idleTimeoutQA - 1)
    expect(await session.expireIfIdle() == false, "una hora de QA no es idle")
    clock.advance(2)
    expect(await session.expireIfIdle(), "pasado el tope de QA se cierra")
    await serving.value
}
