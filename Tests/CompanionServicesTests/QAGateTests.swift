import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore
@testable import CompanionServices

private let sheetRequest = ApprovalRequest(requestId: "r1", toolName: "run_shell", summary: "", inputJSON: "{}")

private func call(_ name: String = "run_shell") -> ToolCallRef {
    ToolCallRef(id: "c1", name: name, arguments: "{}")
}

private func gate(
    _ owner: (any OwnerVerifying)?, on: Bool = true, band: ActionBand = .critical,
    disabled: LockedBox<Int> = LockedBox(0)
) -> QAGate {
    QAGate(
        enabled: { on }, owner: owner, disableQA: { disabled.withLock { $0 += 1 } },
        language: { .en }, classify: { _, _, _ in band })
}

@Test func outsideQAKeepsTheUsualSheet() async {
    let owner = FakeOwnerCheck()
    let verdict = await gate(owner, on: false).decide(sheetRequest, call: call(), said: "")
    expectEq(verdict, .notInQA, "fuera de QA")
    expectEq(owner.calls.count, 0, "no se pide prueba")
}

@Test func actAndConfirmBandsActWithoutTheOwner() async {
    let owner = FakeOwnerCheck()
    for band in [ActionBand.act, .confirm] {
        let verdict = await gate(owner, band: band).decide(sheetRequest, call: call("look"), said: "")
        expectEq(verdict, .act, "\(band)")
    }
    expectEq(owner.calls.count, 0, "nunca llama al puerto")
}

@Test func criticalActionIsGrantedOnlyWhenTheOwnerConfirms() async {
    let owner = FakeOwnerCheck(result: .confirmed)
    let verdict = await gate(owner).decide(sheetRequest, call: call(), said: "")
    expectEq(verdict, .granted, "confirmed")
    expectEq(owner.calls, ["approve a critical action: run_shell"], "una llamada, con la tool en la razon")
}

@Test func aRefusedOwnerCheckDeniesAndKeepsQAOn() async {
    let disabled = LockedBox(0)
    let verdict = await gate(FakeOwnerCheck(result: .refused), disabled: disabled)
        .decide(sheetRequest, call: call(), said: "")
    expectEq(verdict, .refused(code: "owner_refused"), "refused")
    expectEq(disabled.value, 0, "el modo QA sigue")
}

@Test func anUnavailableOwnerCheckDeniesAndTurnsQAOff() async {
    let disabled = LockedBox(0)
    let verdict = await gate(FakeOwnerCheck(result: .unavailable), disabled: disabled)
        .decide(sheetRequest, call: call(), said: "")
    expectEq(verdict, .unavailable(code: "owner_unavailable"), "unavailable")
    expectEq(disabled.value, 1, "apaga el modo QA")
}

@Test func withoutAPortCriticalFailsClosed() async {
    let disabled = LockedBox(0)
    let verdict = await gate(nil, disabled: disabled).decide(sheetRequest, call: call(), said: "")
    expectEq(verdict, .unavailable(code: "owner_unavailable"), "sin puerto no actua")
    expectEq(disabled.value, 1, "QA ya no cumple su precondicion")
}

@Test func theSessionSheetNeverGoesThroughTheGate() async {
    let owner = FakeOwnerCheck()
    let request = ApprovalRequest(
        requestId: "r2", toolName: BridgePolicy.sessionApprovalTool, summary: "", inputJSON: "{}")
    let verdict = await gate(owner).decide(request, call: call(BridgePolicy.sessionApprovalTool), said: "")
    expectEq(verdict, .notInQA, "conserva su hoja")
    expectEq(owner.calls.count, 0, "el agente no la contesta")
}

@Test func aSecondCriticalWhileOneIsOnScreenIsBusy() async {
    let owner = FakeOwnerCheck(result: .confirmed, hold: true)
    let qa = gate(owner)
    let first = Task { await qa.decide(sheetRequest, call: call(), said: "") }
    while !owner.isWaiting { await Task.yield() }
    expectEq(await qa.decide(sheetRequest, call: call(), said: ""), .busy, "segunda")
    owner.release()
    expectEq(await first.value, .granted, "la primera termina")
    expectEq(owner.calls.count, 1, "un solo dialogo")
}

@Test func cancellingTheCallClosesTheDialogAndNeverActs() async {
    let owner = FakeOwnerCheck(result: .confirmed, hold: true)
    let task = Task { await gate(owner).decide(sheetRequest, call: call(), said: "") }
    while !owner.isWaiting { await Task.yield() }
    task.cancel()
    expectEq(await task.value, .refused(code: "owner_refused"), "cancelada")
    expectEq(owner.cancellations, 1, "el fake registra la cancelacion")
}

@Test func handsWithoutRealFactsNeedTheOwnerCheck() async {
    for tool in ["click", "type_text", "press_key", "menu", "scroll", "focus_window", "open_app"] {
        let owner = FakeOwnerCheck(result: .confirmed)
        let qa = QAGate(
            enabled: { true }, owner: owner, disableQA: {}, language: { .en },
            classify: { _, call, _ in QAApprovalPolicy.bandWithoutFacts(toolName: call.name, arguments: [:]) })
        let request = ApprovalRequest(requestId: "r", toolName: tool, summary: "", inputJSON: "{}")
        let verdict = await qa.decide(request, call: call(tool), said: "")
        expectEq(verdict, .granted, "\(tool) pasa por la prueba")
        expectEq(owner.calls.count, 1, "\(tool) llama al puerto")
    }
}

@Test func theSessionSheetIsKeptWhicheverNameCarriesIt() async {
    let session = BridgePolicy.sessionApprovalTool
    let byRequest = ApprovalRequest(requestId: "r", toolName: session, summary: "", inputJSON: "{}")
    let byCall = ApprovalRequest(requestId: "r", toolName: "look", summary: "", inputJSON: "{}")
    let owner = FakeOwnerCheck()
    let qa = gate(owner, band: .act)
    expectEq(await qa.decide(byRequest, call: call("look"), said: ""), .notInQA, "request dice session")
    expectEq(await qa.decide(byCall, call: call(session), said: ""), .notInQA, "call dice session")
    expectEq(owner.calls.count, 0, "el agente no la contesta")
}
