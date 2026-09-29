import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

/// 20c D6 (M9, criterion 9): the bridge serves an explicit allowlist. Adding
/// a tool to the runner used to expose it over MCP automatically (only the
/// deliverables were fenced off by name); now a new tool is out of the bridge
/// until someone decides to put it in, and a test forces that decision.

private struct NoDocuments: DocumentRendering {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt {
        DocumentReceipt(pages: 1, bytes: 1)
    }
}

private struct NoSheets: SpreadsheetDriving {
    func active() async -> SheetApp? { nil }
    func workbook(_ app: SheetApp) async throws -> String { "" }
    func read(_ app: SheetApp, range: SheetRange) async throws -> [[String]] { [] }
    func write(_ app: SheetApp, range: SheetRange, cells: [[SheetCell]], workbook: String) async throws -> SheetWriteReceipt {
        SheetWriteReceipt(backupPath: "", readBack: [])
    }
}

/// A runner with every backing present, so it offers everything it can.
@MainActor private func fullRunner() -> ParentToolRunner {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    return ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        places: FakePlaces(found: []),
        skills: FakeSkillReader(cards: [], bodies: [:]),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
            screen: FakeScreen([]), see: { _ in nil }),
        workdir: NSTemporaryDirectory(), documents: NoDocuments(), sheets: NoSheets())
}

private func helloLine(_ id: Int) -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
}

private func callLine(_ id: Int, _ name: String) -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":{}}}"#
}

private func bridge(_ tools: FakeParentTools) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true })
}

/// The guard. When it fails, a tool was added to the runner without a
/// decision about the bridge: put it in `BridgeScope.allowedTools` if an
/// outside agent may drive it, or in `BridgeScope.localOnly` if not.
@Test @MainActor func everyToolTheRunnerOffersHasABridgeDecision() {
    let offered = Set(fullRunner().specs(.en).map(\.name))
        .union(ParentTool.allCases.map(\.rawValue))
        .union(NativeTool.parentDeliverables.map(\.rawValue))
    let undecided = offered.filter { !BridgeScope.decided($0) }
    expect(undecided.isEmpty,
           "tools with no bridge decision (allowlist or local-only): \(undecided.sorted())")
    expect(Set(fullRunner().specs(.en).map(\.name)).isSuperset(of: BridgeScope.allowedTools),
           "a fully backed runner offers every allowlisted tool (the guard is not vacuous)")
}

@Test func theAllowlistAndTheLocalOnlySetNeverOverlap() {
    let both = BridgeScope.allowedTools.filter { BridgeScope.isLocalOnly($0) }
    expect(both.isEmpty, "a tool is either driven over the bridge or local only: \(both.sorted())")
}

/// Everything the bridge supported before the allowlist keeps working.
@Test @MainActor func everyToolTheBridgeAlreadySupportedStaysSupported() async {
    let expected: Set<String> = [
        "open_app", "open_url", "open_file", "list_apps", "read_skill", "find_places",
        "type_text", "press_key", "focus_window", "read_focused",
        "look", "click", "scroll", "menu", "see",
    ]
    expectEq(BridgeScope.allowedTools, expected, "the allowlist is exactly the tools the bridge served")
    for name in expected.sorted() {
        let tools = FakeParentTools(handledNames: [name], specNames: [name])
        let session = bridge(tools)
        let hello = await session.handle(line: helloLine(1))
        expect(hello.reply.contains("\"\(name)\""), "\(name): hello still lists it")
        let result = await session.handle(line: callLine(2, name))
        expect(result.reply.contains(#""ok":true"#), "\(name): a call still runs")
        expectEq(tools.executeCalls.count, 1, "\(name): executed once")
    }
}

@Test @MainActor func aNewRunnerToolIsNotOfferedOrRunnableOverTheBridge() async {
    let names = Array(BridgeScope.allowedTools) + ["brand_new_tool"]
    let tools = FakeParentTools(handledNames: Set(names), specNames: names)
    let session = bridge(tools)
    let hello = await session.handle(line: helloLine(1))
    expect(!hello.reply.contains("brand_new_tool"), "hello does not list a tool nobody allowed")
    let result = await session.handle(line: callLine(2, "brand_new_tool"))
    expect(result.reply.contains(BridgeCode.unknownTool), "a call to it is unknown_tool, as if it did not exist")
    expect(tools.executeCalls.isEmpty, "and nothing ran")
}
