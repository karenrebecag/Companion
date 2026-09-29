import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20c D5 (M2b). Every denied request is a chance for a mistaken yes, so
// a caller that keeps asking after N denials in a window is cooled down:
// no sheet, a code that says why, and the connection closed. The memory is
// per process, not per connection, or reconnecting would launder it.

@Test @MainActor func bridgeCooldownTests() async {
    testPolicyCoolsDownAfterTheMaxDenialsInTheWindow()
    testDenialsOutsideTheWindowDoNotCount()
    await testRepeatedSessionDenialsAcrossReconnectsCoolDownWithoutANewSheet()
    await testRepeatedPerCallDenialsShutTheSessionOff()
}

private let t0 = Date(timeIntervalSince1970: 2_000_000)

@MainActor func testPolicyCoolsDownAfterTheMaxDenialsInTheWindow() {
    var policy = BridgePolicy()
    for i in 0 ..< BridgePolicy.maxDenials {
        expect(!policy.isCoolingDown(now: t0), "M2b: \(i) denegaciones: aun se puede preguntar")
        policy.recordDenial(now: t0.addingTimeInterval(Double(i)))
    }
    let now = t0.addingTimeInterval(Double(BridgePolicy.maxDenials))
    expect(policy.isCoolingDown(now: now), "M2b: tras N denegaciones, enfriamiento")
    expectEq(policy.helloReceived(now: now), .reject(code: BridgeCode.coolingDown), "M2b: hello rechazado")
    expectEq(policy.admit(tool: "look", now: now), .reject(code: BridgeCode.coolingDown), "M2b: call rechazada")
    let later = t0.addingTimeInterval(BridgePolicy.denialWindow + Double(BridgePolicy.maxDenials))
    expect(!policy.isCoolingDown(now: later), "M2b: el enfriamiento termina cuando la ventana pasa")
}

@MainActor func testDenialsOutsideTheWindowDoNotCount() {
    var policy = BridgePolicy()
    for i in 0 ..< BridgePolicy.maxDenials {
        policy.recordDenial(now: t0.addingTimeInterval(Double(i) * (BridgePolicy.denialWindow + 1)))
    }
    let now = t0.addingTimeInterval(Double(BridgePolicy.maxDenials) * (BridgePolicy.denialWindow + 1))
    expect(!policy.isCoolingDown(now: now), "M2b: denegaciones espaciadas no enfrian")
}

@MainActor func testRepeatedSessionDenialsAcrossReconnectsCoolDownWithoutANewSheet() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(answer: false)
    let session = makeSession(tools, approvals)
    for attempt in 0 ..< BridgePolicy.maxDenials {
        _ = await session.handle(line: hello(attempt * 10 + 1))
        let denied = await session.handle(line: call(attempt * 10 + 2))
        expect(denied.reply.contains(BridgeCode.deniedByUser) || denied.reply.contains(BridgeCode.coolingDown),
               "M2b: intento \(attempt) denegado")
        await session.connectionClosed()
    }
    expectEq(approvals.requests.count, BridgePolicy.maxDenials, "M2b: una hoja por intento hasta el tope")

    let next = await session.handle(line: hello(100))
    expect(next.reply.contains(BridgeCode.coolingDown), "M2b: el siguiente hello se enfria")
    expect(next.close, "M2b: y se cierra la conexion")
    let late = await session.handle(line: call(101))
    expect(!late.reply.contains(#""ok":true"#), "M2b: ninguna llamada pasa")
    expectEq(approvals.requests.count, BridgePolicy.maxDenials, "M2b: el intento N+1 no abre hoja")
    expectEq(tools.executeCalls.count, 0, "M2b: nada ejecutado")
}

@MainActor func testRepeatedPerCallDenialsShutTheSessionOff() async {
    let tools = FakeParentTools()
    tools.setScriptedApproval(ApprovalRequest(
        requestId: "click-1", toolName: "click", summary: "delete", inputJSON: "{}"))
    let approvals = ScriptedApprovals(answer: true)
    approvals.setAnswer(false, forTool: "click")
    let session = makeSession(tools, approvals)
    _ = await session.handle(line: hello(1))
    var last = (reply: "", close: false)
    for i in 0 ..< BridgePolicy.maxDenials {
        last = await session.handle(line: call(10 + i, "click"))
        expect(last.reply.contains("denied_by_user"), "M2b: click \(i) denegado")
    }
    expect(last.close, "M2b: la ultima denegacion apaga la sesion y cierra la conexion")
    let after = await session.handle(line: call(99, "look"))
    expect(!after.reply.contains(#""ok":true"#), "M2b: tras apagarse, nada pasa")
    expectEq(tools.executeCalls.count, 0, "M2b: ningun click se ejecuto")
}
