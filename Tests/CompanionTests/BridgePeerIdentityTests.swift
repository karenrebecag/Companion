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
    testThePeerLineDropsZeroWidthFormatAndLineSeparatorScalars()
    testAHugePeerPathIsCappedKeepingItsTail()
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

@MainActor func testThePeerLineDropsZeroWidthFormatAndLineSeparatorScalars() {
    let hidden = "/tmp/a\u{200B}b\u{200D}c\u{2028}d\u{2029}e\u{FEFF}f\u{00AD}g"
    let display = bridgeDisplay("{\"client\":\"x\",\"pid\":7,\"process\":\"\(hidden)\"}")
    expect((display.preview ?? "").contains("/tmp/abcdefg"),
           "M2c: cero-ancho, separadores de linea y formato salen del path: \(display.preview ?? "nil")")
}

@MainActor func testAHugePeerPathIsCappedKeepingItsTail() {
    let path = "/" + String(repeating: "a", count: 5000) + "/evil-tail"
    let line = BridgeCopy.peerLine(pid: 7, process: path)
    expect(line.count <= BridgeCopy.peerPathLimit + 40, "M2c: el path largo se acorta: \(line.count)")
    expect(line.hasSuffix("evil-tail"), "M2c: el corte es en el medio, el ejecutable real queda a la vista")
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
