import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 20c D2 review closure: an MCP request is not a job's action, and the sheet
// must show what the click authorizes.

private func mcp(_ id: String, tool: String = "docs/search", args: String = "{}") -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "", inputJSON: args, isMCP: true)
}

// Tagged (16q-1): refusing a job's first action stops THAT job by its id, so
// the job and its requests carry the owner.
private let owner = JobID("j")

private func jobAction(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "", inputJSON: "{}")
}

@Test @MainActor func mcpDenyDoesNotStopTheUnrelatedJob() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x"), from: owner))
    _ = m.handle(.job(.approvalRequested(mcp("m1"))))
    let fx = m.handle(.approvalAnswered(requestId: "m1", approved: false, remember: false))
    expect(!fx.contains(.cancelJob) && !fx.contains(.cancelJobByID(owner)), "mcp no: el encargo ajeno no se cancela")
    expect(fx.contains(.resolveApproval(requestId: "m1", approved: false, remember: false)),
           "mcp no: solo esa peticion se niega")
    expect(m.projection.job != nil, "mcp no: el encargo sigue")
}

@Test @MainActor func mcpDenyDoesNotDenyTheRestOfTheQueue() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x"), from: owner))
    _ = m.handle(.job(.approvalRequested(mcp("m1"))))
    _ = m.handle(.job(.approvalRequested(jobAction("a1")), from: owner))
    _ = m.handle(.approvalAnswered(requestId: "m1", approved: false, remember: false))
    expectEq(m.projection.approvalQueue.map(\.requestId), ["a1"],
             "mcp no: la cola del encargo queda intacta")
}

@Test @MainActor func mcpApproveDoesNotWeakenTheJobsFirstDenyRule() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x"), from: owner))
    _ = m.handle(.job(.approvalRequested(mcp("m1"))))
    _ = m.handle(.approvalAnswered(requestId: "m1", approved: true, remember: false))
    _ = m.handle(.job(.approvalRequested(jobAction("a1")), from: owner))
    let fx = m.handle(.approvalAnswered(requestId: "a1", approved: false, remember: false))
    expect(fx.contains(.cancelJobByID(owner)), "mcp si: negar la 1a accion real del encargo aun lo para")
}

@Test func mcpSheetShowsTheFullArgumentsAndNoRemember() {
    let d = ApprovalCopy.display(
        for: mcp("m1", args: #"{"id":"42","body":"delete everything"}"#), language: .en)
    let preview = d.preview ?? ""
    expect(preview.contains("42") && preview.contains("delete everything"),
           "mcp hoja: se ven todos los argumentos, no solo una llave conocida")
    expect(!d.showsRemember, "mcp hoja: sin Recordar, no hay memoria para MCP")
}

@Test func mcpSheetStripsBidiAndControlFromTheNameAndArguments() {
    let evil = "docs/\u{202E}hcraes\u{0007}"
    let d = ApprovalCopy.display(
        for: mcp("m1", tool: evil, args: "{\"to\":\"a\u{202E}b\u{0000}c\"}"), language: .en)
    expect(!d.subject.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0x07 },
           "mcp hoja: el nombre no lleva bidi ni control")
    expect((d.preview ?? "").unicodeScalars.allSatisfy { $0.value != 0x202E && $0.value != 0 },
           "mcp hoja: los argumentos tampoco")
    expect(d.subject.contains("docs/"), "mcp hoja: el nombre sigue legible")
}

@Test func mcpSheetCapsALongName() {
    let d = ApprovalCopy.display(
        for: mcp("m1", tool: "docs/" + String(repeating: "a", count: 500)), language: .en)
    expect(d.subject.count <= 80, "mcp hoja: el nombre no empuja los botones")
}
