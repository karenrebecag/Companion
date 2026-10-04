import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 18-3 (§8 criterion 5, X4, X5). The bridge publishes the browser tools
// by an explicit decision, budgets them, and the approval queue does not
// mistake their sheets for a job's.

private let browserWrites: Set<String> = [
    "browser_click", "browser_type", "browser_select", "browser_navigate", "browser_open", "browser_take",
    "browser_release", "browser_double_click", "browser_right_click",
]
private let browserReads: Set<String> = ["browser_tabs", "browser_read"]

@Test func theBridgeAllowlistNamesTheBrowserTools() {
    for name in browserWrites.union(browserReads) {
        expect(BridgeScope.allows(name), "\(name) is a decided bridge tool")
    }
    expect(BridgePolicy.writeTools.isSuperset(of: browserWrites), "click, type and navigate are writes")
    expect(BridgePolicy.readTools.isSuperset(of: browserReads), "tabs and read are reads")
    expect(BridgePolicy.unbucketed(BridgeScope.bridgeTools).isEmpty, "every allowlisted tool is bucketed")
}

@Test func thirtyFirstBrowserWriteInAMinuteIsRateLimited() {
    let now = Date()
    var policy = BridgePolicy()
    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.approved(until: nil, now: now)
    let tools = ["browser_click", "browser_type", "browser_navigate"]
    for i in 0 ..< BridgePolicy.budgetPerMinute {
        expectEq(policy.admit(tool: tools[i % 3], now: now.addingTimeInterval(Double(i) / 10)), .proceed,
                 "write \(i + 1) is inside the budget")
    }
    let verdict = policy.admit(tool: "browser_click", now: now.addingTimeInterval(5))
    guard case .reject(let code) = verdict else { Issue.record("the 31st write was admitted"); return }
    expectEq(code, BridgeCode.rateLimited, "criterio 5: la 31.a es rate_limited")
}

@Test func browserReadsDrawFromTheReadBudgetNotTheWriteOne() {
    let now = Date()
    var policy = BridgePolicy()
    _ = policy.helloReceived(now: now)
    _ = policy.admit(tool: "look", now: now)
    policy.approved(until: nil, now: now)
    for _ in 0 ..< BridgePolicy.budgetPerMinute { _ = policy.admit(tool: "browser_click", now: now) }
    expectEq(policy.admit(tool: "browser_read", now: now), .proceed, "reads still run with the write budget spent")
    expectEq(policy.admit(tool: "browser_tabs", now: now), .proceed, "and so do tabs")
}

@Test func browserSheetsBelongToTheParentNotToAJob() {
    for tool in BrowserTool.allCases {
        expect(ParentTool.ownsRequest(tool.rawValue), "\(tool.rawValue): dropped with its conversation like any parent sheet")
    }
}

@MainActor @Test func denyingABrowserSheetDuringAJobDoesNotStopTheJob() {
    var machine = SessionMachine()
    _ = machine.handle(.job(.started(goal: "x")))
    _ = machine.handle(.job(.approvalRequested(
        ApprovalRequest(requestId: "b1", toolName: "browser_click", summary: "click", inputJSON: "{}"))))
    let effects = machine.handle(.approvalAnswered(requestId: "b1", approved: false, remember: false))
    expect(effects.contains(.resolveApproval(requestId: "b1", approved: false, remember: false)),
           "the answer resolves the sheet")
    expect(!effects.contains(.cancelJob), "a browser denial is not the job's: the job keeps running")
    expect(machine.projection.job != nil, "the job is still there")
}

// MARK: - through the bridge session, the way an outside agent reaches it

private func bridgeLine(_ id: Int, _ name: String, _ arguments: String) -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
}

@MainActor @Test func anAgentOnTheBridgeSeesTheBrowserToolsAndADeniedClickSendsNoFrame() async {
    let rig = makeToolRig()
    let approvals = ScriptedApprovals(answer: true)
    approvals.setAnswer(false, forTool: "browser_click")
    let session = BridgeSession(
        tools: CompositeParentTools([rig.runner]), guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true })
    let hello = await session.handle(
        line: #"{"id":1,"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#)
    for tool in BrowserTool.allCases { expect(hello.reply.contains(tool.rawValue), "hello lists \(tool.rawValue)") }

    let read = await session.handle(line: bridgeLine(2, "browser_read", #"{"tab":12}"#))
    expect(read.reply.contains(#""ok":true"#), "the read runs")
    let denied = await session.handle(line: bridgeLine(3, "browser_click", #"{"tab":12,"element":2}"#))
    expect(denied.reply.contains("denied_by_user"), "criterio 3 por el puente: la hoja denegada se le dice al agente")
    expect(rig.channel.writes.isEmpty, "y la extension no recibio ninguna escritura")

    approvals.setAnswer(true, forTool: "browser_click")
    let allowed = await session.handle(line: bridgeLine(4, "browser_click", #"{"tab":12,"element":2}"#))
    expect(allowed.reply.contains(#""ok":true"#), "con un si, corre")
    expectEq(rig.channel.writes.count, 1, "una escritura")
}
