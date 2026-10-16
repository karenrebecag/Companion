import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

@testable import CompanionUI

// Puente QA PR-2: a turn the bridge's agent types, and the one gate that
// replaces the sheets while QA mode is on.

private let lookCall = ToolCallRef(id: "c1", name: "look", arguments: "{}")

private func tools(
    outcome: ParentToolOutcome = ParentToolOutcome(ok: true, output: "saw Safari", target: "Safari")
) -> FakeParentTools {
    let tools = FakeParentTools(handledNames: ["look"], specNames: ["look"], scriptedOutcome: outcome)
    tools.setScriptedApproval(ApprovalRequest(
        requestId: "r1", toolName: "look", summary: "look", inputJSON: "{}"))
    return tools
}

@MainActor private func rig(
    gate: FakeQAGate?, tools: FakeParentTools, approvals: FakeApprovals = FakeApprovals()
) -> ChatViewModel {
    let chat = FakeChatProvider(replies: [.success([.toolCalls([lookCall])]), .success([.text("listo")])])
    let vm = primed(chat: chat, parentTools: tools, approvals: approvals)
    vm.qaGate = gate
    return vm
}

@MainActor private func started(_ start: QAAskStart) -> String {
    guard case .started(let id, _) = start else {
        Issue.record("expected a started turn, got \(start)")
        return ""
    }
    return id
}

@Test @MainActor func theAgentTurnCarriesHerWordsOnlyWhenAsked() async {
    for asWords in [true, false] {
        let fake = tools()
        let vm = rig(gate: FakeQAGate(.act), tools: fake)
        let id = started(vm.askAsAgent(text: "abre safari", newConversation: false, asUserWords: asWords))
        await pumpUntil("turno \(asWords)") { vm.turnRecord(id)?.status.isFinished == true }
        expectEq(fake.saidSeen, [asWords ? "abre safari" : ""], "said con as_user_words \(asWords)")
        expectEq(vm.messages.first?.origin, .agent, "el mensaje es del agente")
    }
}

@Test @MainActor func inQAAGrantedActionRunsWithoutASheetAndIsRecorded() async {
    let fake = tools()
    let approvals = FakeApprovals()
    let vm = rig(gate: FakeQAGate(.granted), tools: fake, approvals: approvals)
    let id = started(vm.askAsAgent(text: "x", newConversation: false, asUserWords: true))
    await pumpUntil("granted") { vm.turnRecord(id)?.status.isFinished == true }
    expect(await approvals.requested.isEmpty, "ninguna hoja")
    expectEq(fake.executeCalls.count, 1, "la tool corrio")
    expectEq(fake.grantedCalls.map(\.requestId), ["r1"], "el runner recibio el permiso")
    let record = vm.turnRecord(id)
    expectEq(record?.toolCalls.first?.ownerCheck, "confirmed", "con la prueba de dueña")
    expectEq(record?.toolCalls.first?.band, "critical", "banda critica")
    expectEq(record?.phases.map(\.phase), [.started, .acting, .streaming, .completed], "fases")
    expectEq(record?.reply?.text, "listo", "la respuesta")
}

@Test @MainActor func aRefusedOwnerCheckKeepsTheToolFromRunningAndTheTurnGoesOn() async {
    let fake = tools()
    let vm = rig(gate: FakeQAGate(.refused(code: BridgeCode.ownerRefused)), tools: fake)
    let id = started(vm.askAsAgent(text: "x", newConversation: false, asUserWords: true))
    await pumpUntil("refused") { vm.turnRecord(id)?.status.isFinished == true }
    expectEq(fake.executeCalls.count, 0, "no actua")
    let call = vm.turnRecord(id)?.toolCalls.first
    expectEq(call?.ok, false, "la tool fallo")
    expect(call?.output.hasPrefix(BridgeCode.ownerRefused) == true, "el modelo lee owner_refused")
    expectEq(call?.ownerCheck, "refused", "queda registrado")
    expectEq(vm.turnRecord(id)?.status, .completed, "el turno sigue y termina")
}

@Test @MainActor func outsideQAAnActionKeepsItsSheet() async {
    let fake = tools()
    let approvals = FakeApprovals()
    let vm = rig(gate: FakeQAGate(.notInQA), tools: fake, approvals: approvals)
    _ = vm.askAsAgent(text: "x", newConversation: false, asUserWords: true)
    await pumpUntil("hoja") { vm.pendingApproval != nil }
    expectEq(vm.pendingApproval?.toolName, "look", "la hoja de siempre")
    vm.abandonTurn()
}

@Test @MainActor func cuttingAnAgentTurnMarksItCancelledAndInterrupted() async {
    let fake = tools()
    let vm = rig(gate: FakeQAGate(.act, hold: true), tools: fake)
    let id = started(vm.askAsAgent(text: "x", newConversation: false, asUserWords: true))
    await pumpUntil("en la puerta") { vm.turnRecord(id)?.phases.contains { $0.phase == .acting } == true }
    var events: [TurnSignal] = []
    vm.onTurnEvent = { _, signal in events.append(signal) }
    vm.abandonTurn()
    expectEq(vm.turnRecord(id)?.status, .cancelled, "cancelado")
    expectEq(vm.turnRecord(id)?.error?.code, BridgeCode.interrupted, "con el codigo interrupted")
    expectEq(events, [.finished], "el que espera se entera")
}

@Test @MainActor func askWhileATurnRunsIsBusyAndNeverQueues() async {
    let vm = rig(gate: FakeQAGate(.act, hold: true), tools: tools())
    let first = started(vm.askAsAgent(text: "uno", newConversation: false, asUserWords: true))
    await pumpUntil("en vuelo") { vm.busy }
    expectEq(vm.askAsAgent(text: "dos", newConversation: false, asUserWords: true), .busy(turnId: first),
             "busy con el id del turno en vuelo")
    vm.abandonTurn()
}

@Test @MainActor func askWhileHerOwnTurnRunsIsBusyWithoutHerTurnId() async {
    let vm = rig(gate: FakeQAGate(.act, hold: true), tools: tools())
    vm.draft = "hola"
    vm.send()
    await pumpUntil("su turno") { vm.busy }
    expectEq(vm.askAsAgent(text: "x", newConversation: false, asUserWords: true), .busy(turnId: nil),
             "no se le da el id de un turno que no es suyo")
    vm.abandonTurn()
}

@Test @MainActor func askingForANewConversationStartsItBeforeTheTurn() async {
    let vm = rig(gate: FakeQAGate(.act), tools: tools())
    let before = vm.conversationId
    guard case .started(_, let conversation) = vm.askAsAgent(text: "x", newConversation: true, asUserWords: true)
    else {
        Issue.record("no arranco")
        return
    }
    expect(conversation != before, "conversacion nueva")
    expectEq(vm.messages.first?.text, "x", "el mensaje abre la conversacion limpia")
    vm.abandonTurn()
}

@Test @MainActor func anOpenOwnerCheckPutsTheTurnAwaitingTheOwner() async {
    let vm = rig(gate: FakeQAGate(.act, hold: true), tools: tools())
    let id = started(vm.askAsAgent(text: "x", newConversation: false, asUserWords: true))
    await pumpUntil("en vuelo") { vm.busy }
    var events: [TurnSignal] = []
    vm.onTurnEvent = { _, signal in events.append(signal) }
    vm.ownerCheckChanged(open: true, tool: "type_text")
    expectEq(vm.turnRecord(id)?.status, .awaitingOwner, "espera el dedo")
    expectEq(vm.turnRecord(id)?.pendingOwner?.tool, "type_text", "dice que accion")
    expect(vm.session.projection.ownerCheck, "la isla lo sabe")
    vm.ownerCheckChanged(open: false, tool: "type_text")
    expectEq(vm.turnRecord(id)?.status, .running, "al cerrar vuelve a correr")
    expectEq(events, [.ownerCheckOpened, .ownerCheckClosed], "avisos en orden")
    vm.abandonTurn()
}
