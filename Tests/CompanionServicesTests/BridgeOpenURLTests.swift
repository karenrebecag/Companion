import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The chat opens addresses without a sheet; the MCP bridge has no user words,
// so its open_url keeps asking.

private func openLine(_ id: Int, _ url: String) -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"open_url","arguments":{"url":"\#(url)"}}}"#
}

@Test @MainActor func bridgeOpenURLTests() async {
    await testABridgeOpenURLToAnUnsaidHostAsks()
    await testAParentOpenURLWithANonHTTPSchemeIsRefusedWithoutOpening()
}

@MainActor func testABridgeOpenURLToAnUnsaidHostAsks() async {
    let tools = FakeParentTools(handledNames: ["open_url"])
    let approvals = ScriptedApprovals(answer: true)
    let session = makeSession(tools, approvals)
    _ = await session.handle(line: hello(1))
    _ = await session.handle(line: openLine(2, "https://www.google.com/search?q=clima"))
    expect(approvals.requests.contains { $0.toolName == "open_url" }, "puente: open_url a un host que nadie dijo pide hoja")
}

@MainActor func testAParentOpenURLWithANonHTTPSchemeIsRefusedWithoutOpening() async {
    for target in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,x"] {
        let opener = FakeWorkspaceOpener()
        let runner = ParentToolRunner(workspace: opener)
        let call = ToolCallRef(id: "c", name: "open_url", arguments: #"{"url":"\#(target)"}"#)
        expect(runner.approval(for: call, said: "abre \(target)") == nil, "\(target): sin hoja")
        let out = await runner.execute(name: "open_url", argumentsJSON: call.arguments)
        expect(!out.ok, "\(target): rechazado")
        expect(opener.openedURLs.isEmpty, "\(target): nada se abrio")
    }
}
