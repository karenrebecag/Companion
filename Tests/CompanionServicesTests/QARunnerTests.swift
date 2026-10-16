import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionServices

private func runner(
    _ driving: FakeQADriving, scope: @escaping @Sendable () -> Bool = { true },
    waiter: TurnWaiter = TurnWaiter(limit: { _ in })
) -> QARunner {
    QARunner(driving: driving, waiter: waiter, scope: scope, language: { .en })
}

private func record(_ id: String = "t1", status: TurnStatus = .completed) -> TurnRecord {
    var record = TurnRecord(turnId: id, conversationId: "c1", origin: "agent")
    record.status = status
    record.reply = TurnReply(text: "hola", isFailure: false)
    return record
}

@Test func withoutTheScopeTheToolsAreNeitherListedNorServed() async {
    let qa = runner(FakeQADriving(), scope: { false })
    expect(qa.specs(.en).isEmpty, "no se listan")
    expect(!qa.handles("companion_ask"), "no se atienden: unknown_tool")
    let outcome = await qa.execute(name: "companion_ask", argumentsJSON: #"{"text":"hi"}"#)
    expect(outcome.output.hasPrefix(BridgeCode.qaScopeOff), "una llamada que se cuela recibe qa_scope_off")
}

@Test func askStartsTheTurnAndReturnsTheFinishedResult() async {
    let driving = FakeQADriving()
    driving.set(record())
    let outcome = await runner(driving).execute(name: "companion_ask", argumentsJSON: #"{"text":"di hola"}"#)
    expect(outcome.ok, "ok")
    expect(outcome.output.contains(#""status":"completed""#), "estado")
    expect(outcome.output.contains(#""turn_id":"t1""#), "turn_id")
    expect(outcome.output.hasSuffix(BridgeCopy.toolDataSuffix(.en)), "enmarcado como datos")
    expectEq(driving.asks, [.init(text: "di hola", newConversation: false, asUserWords: true)],
             "por defecto: conversacion actual y como palabras de la usuaria")
}

@Test func askPassesNewConversationAndAsUserWordsFalseThrough() async {
    let driving = FakeQADriving()
    driving.set(record())
    _ = await runner(driving).execute(
        name: "companion_ask",
        argumentsJSON: #"{"text":"hola","conversation":"new","as_user_words":false}"#)
    expectEq(driving.asks, [.init(text: "hola", newConversation: true, asUserWords: false)], "se respetan")
}

@Test func askWhileATurnIsRunningIsBusyTurnWithItsId() async {
    let driving = FakeQADriving(start: .busy(turnId: "running-1"))
    let outcome = await runner(driving).execute(name: "companion_ask", argumentsJSON: #"{"text":"otra"}"#)
    expect(!outcome.ok, "falla")
    expect(outcome.output.hasPrefix(BridgeCode.busyTurn), "busy_turn")
    expect(outcome.output.contains("running-1"), "con el id del turno en vuelo")
}

@Test func askRefusesArgumentsThatAreNotWhatTheySay() async {
    let driving = FakeQADriving()
    let qa = runner(driving)
    for json in [
        #"{"text":""}"#, #"{"text":"a","wait_seconds":101}"#, #"{"text":"a","wait_seconds":true}"#,
        #"{"text":"a","as_user_words":"yes"}"#, #"{"text":"a","conversation":"old"}"#, #"{"wait_seconds":1}"#,
    ] {
        let outcome = await qa.execute(name: "companion_ask", argumentsJSON: json)
        expect(outcome.output.hasPrefix("invalid_args"), "\(json)")
    }
    expect(driving.asks.isEmpty, "ninguna llego a escribir en la conversacion")
}

@Test func waitTurnOnATurnThatIsNotTheAgentsIsNotFound() async {
    let driving = FakeQADriving()
    var hers = record("hers")
    hers.origin = "typed"
    driving.set(hers)
    let outcome = await runner(driving).execute(
        name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"hers"}"#)
    expect(outcome.output.hasPrefix(BridgeCode.notFound), "los turnos de la usuaria no se leen")
    expect(!outcome.output.contains("hola"), "ni su texto")
}

@Test func busyTurnNeverNamesATurnThatIsNotTheAgents() async {
    let driving = FakeQADriving(start: .busy(turnId: nil))
    let outcome = await runner(driving).execute(name: "companion_ask", argumentsJSON: #"{"text":"otra"}"#)
    expect(outcome.output.hasPrefix(BridgeCode.busyTurn), "busy_turn")
    expect(!outcome.output.contains("turn_id"), "sin id")
}

@Test func waitTurnOnAnUnknownIdIsNotFound() async {
    let outcome = await runner(FakeQADriving()).execute(
        name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"nope"}"#)
    expect(outcome.output.hasPrefix(BridgeCode.notFound), "not_found")
}

@Test func waitTurnOnAFinishedTurnAnswersWithoutWaiting() async {
    let driving = FakeQADriving()
    driving.set(record("t9", status: .cancelled))
    let outcome = await runner(driving).execute(
        name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"t9","wait_seconds":100}"#)
    expect(outcome.ok && outcome.output.contains(#""status":"cancelled""#), "cancelado, al instante")
}

@Test func aTurnWaitingOnTheOwnerReturnsAwaitingOwnerWithThePendingCheck() async {
    let driving = FakeQADriving()
    var waiting = record("t2", status: .awaitingOwner)
    waiting.pendingOwner = TurnPendingOwner(tool: "type_text", band: "critical", reason: "approve")
    driving.set(waiting)
    let waiter = TurnWaiter(limit: { _ in })
    await waiter.signal(turnId: "t2", .ownerCheckOpened)
    let outcome = await runner(driving, waiter: waiter).execute(
        name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"t2"}"#)
    expect(outcome.output.contains(#""status":"awaiting_owner""#), "awaiting_owner")
    expect(outcome.output.contains(#""pending_owner_check""#), "dice que Touch ID esta pendiente")
}

@Test func theResultCarriesNoWordsWhenTheScopeWentOffMidCall() async {
    let on = LockedBox(true)
    let driving = FakeQADriving()
    driving.set(record())
    let qa = runner(driving, scope: { on.value })
    on.withLock { $0 = true }
    let withText = await qa.execute(name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"t1"}"#)
    expect(withText.output.contains(#""text":"hola""#), "con QA, el texto")
    let off = LockedBox(false)
    let without = await runner(driving, scope: { off.value }).execute(
        name: "companion_wait_turn", argumentsJSON: #"{"turn_id":"t1"}"#)
    expect(!without.output.contains("hola"), "sin QA nada de texto")
}
