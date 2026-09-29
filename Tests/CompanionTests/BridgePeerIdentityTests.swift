import CompanionCore
@testable import CompanionServices
import Darwin
import Foundation
import Testing

// Wave 20c D5 (M2c). The bridge sheet headlines a name the client typed
// itself; next to it the user gets what the kernel knows about the peer: its
// pid and the executable behind it, so "claude-code" running from /tmp is
// visible as such.

@Test @MainActor func bridgePeerIdentityTests() async {
    testTheSheetShowsThePeerPidAndProcess()
    testTheSheetHasNoDetailWhenThePeerIsUnknown()
    testThePeerLineIsCleanedOfControlAndBidiCharacters()
    testAConnectionKnowsItsPeerPidAndExecutable()
    await testTheSessionSheetCarriesThePeer()
}

private func bridgeDisplay(_ json: String, _ language: AppLanguage = .en) -> ApprovalDisplay {
    ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "1", toolName: BridgePolicy.sessionApprovalTool, summary: "", inputJSON: json),
        language: language)
}

@MainActor func testTheSheetShowsThePeerPidAndProcess() {
    let display = bridgeDisplay(
        #"{"client":"claude-code","pid":4242,"process":"/Applications/Claude.app/Contents/MacOS/claude"}"#)
    let preview = display.preview ?? ""
    expect(preview.contains("4242"), "M2c: la hoja muestra el pid")
    expect(preview.contains("/Applications/Claude.app/Contents/MacOS/claude"), "M2c: y el ejecutable")
    expect(!display.showsRemember, "M2c: sigue sin recordar")
    expect((bridgeDisplay(#"{"client":"claude-code","pid":4242}"#, .es).preview ?? "").contains("4242"),
           "M2c: solo con pid tambien lo muestra")
}

@MainActor func testTheSheetHasNoDetailWhenThePeerIsUnknown() {
    expect(bridgeDisplay(#"{"client":"claude-code"}"#).preview == nil, "M2c: sin peer, sin caja (19-1c)")
}

@MainActor func testThePeerLineIsCleanedOfControlAndBidiCharacters() {
    let display = bridgeDisplay("{\"client\":\"x\",\"pid\":7,\"process\":\"/tmp/a\\nb\\u202Ec\"}")
    let preview = display.preview ?? ""
    expect(!preview.contains("\n") && !preview.contains("\u{202E}"), "M2c: el path no forja lineas ni invierte texto")
}

@MainActor func testAConnectionKnowsItsPeerPidAndExecutable() {
    let pair = BridgePair()
    expectEq(pair.connection.peer?.pid, getpid(), "M2c: el pid del par sale del kernel")
    expect(!(pair.connection.peer?.path ?? "").isEmpty, "M2c: y su ejecutable")
    pair.closeClient()
}

@MainActor func testTheSessionSheetCarriesThePeer() async {
    let approvals = ScriptedApprovals(answer: true)
    let session = makeSession(FakeParentTools(), approvals)
    let pair = BridgePair()
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2))
    _ = pair.readLine()
    let json = approvals.requests.first { $0.toolName == BridgePolicy.sessionApprovalTool }?.inputJSON ?? ""
    let arguments = ToolArguments.parse(json) ?? [:]
    expectEq(arguments["pid"] as? Int, Int(getpid()), "M2c: el inputJSON de la hoja lleva el pid del par")
    expect(!(arguments["process"] as? String ?? "").isEmpty, "M2c: y su ejecutable")
    pair.closeClient()
    await serving.value
}
