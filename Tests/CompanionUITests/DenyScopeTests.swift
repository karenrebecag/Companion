import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func denyScopeTests() async {
    await testDenyingTheFirstActionStopsTheJob()
    await testDenyingALaterActionOnlyRefusesThatAction()
    await testApprovingNeverStops()
    await testDenyingTheFirstActionRemembersNothing()
    await testAnswerBoundToAnOlderRequestIsIgnored()
    await testAnswerBoundToThePendingRequestIsDelivered()
    await testStaleAnswerCannotRememberOnTheNewRequest()
    await testSheetClosureBuiltForAnOlderRequestLeavesTheNewOnePending()
    await testAnswerWithNothingPendingIsLoggedAndIgnored()
}

@MainActor private func awaiting(
    _ submitter: WatchfulSubmitter, log: @escaping @Sendable (String) -> Void = { _ in }
) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default,
        jobSubmitter: submitter, log: log)
    vm.onAppear()
    Task {
        await vm.runJob(
            preface: "Voy a mirar.",
            handoff: Handoff(goal: "revisar el disco", context: ""),
            submitter: submitter)
    }
    return vm
}

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(
        requestId: id, toolName: "run_shell", summary: "diskutil info",
        inputJSON: "{}")
}

@MainActor func testDenyingTheFirstActionStopsTheJob() async {
    // Lo que le paso a Karen: nego el permiso y el encargo siguio por otro
    // camino, con `df -h`, y le entrego un informe de disco que nunca pidio.
    // Un encargo cuyo PRIMER paso rechazas casi nunca es uno que quieras que
    // siga probando alternativas.
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(false, requestId: "a1")
    await pumpUntil("para de verdad") { submitter.cancelled }
    expect(submitter.cancelled, "negar el primer paso para el encargo entero")
}

@MainActor func testDenyingALaterActionOnlyRefusesThatAction() async {
    // Si ya autorizaste algo, el encargo va por donde tu quisiste: negar un
    // paso posterior es acotar, no abortar.
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true, requestId: "a1")
    vm.receiveJobEvent(.approvalRequested(request("a2")), from: vm.chatJobID)
    vm.answerApproval(false, requestId: "a2")
    await settle(0.15)
    expect(!submitter.cancelled,
           "negar un paso posterior no tira lo que ya autorizaste")
}

@MainActor func testApprovingNeverStops() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true, requestId: "a1")
    await settle(0.15)
    expect(!submitter.cancelled, "autorizar no para nada")
}

/// 23 (10c). Negar el primer paso cancela el encargo y no deja nada en la
/// memoria aunque el toggle estuviera marcado: no hubo encargo que recordar.
@MainActor func testDenyingTheFirstActionRemembersNothing() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("recuerda: arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(false, remember: true, requestId: "a1")
    await pumpUntil("recuerda: para") { submitter.cancelled }
    await pumpUntil("recuerda: resolvió") { !submitter.remembered.isEmpty }
    expectEq(submitter.remembered, [false], "recuerda: el primer no no se recuerda")
}

/// Security review: a late click on the sheet of request A, delivered after
/// request B took its place, used to answer B. The answer carries its own id.
@MainActor func testAnswerBoundToAnOlderRequestIsIgnored() async {
    let submitter = WatchfulSubmitter()
    let lines = LogLines()
    let vm = awaiting(submitter, log: lines.append)
    await pumpUntil("stale: arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true, requestId: "a1")
    vm.receiveJobEvent(.approvalRequested(request("b1")), from: vm.chatJobID)
    let before = vm.messages.count
    vm.answerApproval(false, requestId: "a1")
    expectEq(vm.pendingApproval?.requestId, "b1", "stale: la nueva sigue pendiente")
    expectEq(vm.messages.count, before, "stale: no se registra ninguna respuesta")
    await settle(0.15)
    expect(!submitter.cancelled, "stale: el clic viejo no niega la peticion nueva")
    expect(lines.all.contains { $0.contains("a1") && $0.contains("b1") },
           "stale: queda una linea de log con ambos ids")
}

@MainActor func testAnswerBoundToThePendingRequestIsDelivered() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("vigente: arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true, requestId: "a1")
    expect(vm.pendingApproval == nil, "vigente: la respuesta con su id cierra la hoja")
    await pumpUntil("vigente: llega al encargo") { !submitter.resolved.isEmpty }
    expectEq(submitter.resolved.map(\.requestId), ["a1"], "vigente: resuelve a1")
    expectEq(submitter.resolved.map(\.approved), [true], "vigente: aprobada")
}

/// The remember toggle rides the stale click too: it must not write a rule
/// for the request the user never saw.
@MainActor func testStaleAnswerCannotRememberOnTheNewRequest() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("recordar-stale: arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true, requestId: "a1")
    await pumpUntil("recordar-stale: a1 llega") { !submitter.remembered.isEmpty }
    vm.receiveJobEvent(.approvalRequested(request("b1")), from: vm.chatJobID)
    let before = vm.messages.count
    let resolvedBefore = submitter.resolved.count
    vm.answerApproval(true, remember: true, requestId: "a1")
    await settle(0.15)
    expectEq(submitter.remembered, [false], "recordar-stale: nada nuevo se recuerda")
    expectEq(submitter.resolved.count, resolvedBefore, "recordar-stale: nada nuevo se resuelve")
    expectEq(vm.pendingApproval?.requestId, "b1", "recordar-stale: b1 sigue pendiente")
    expectEq(vm.messages.count, before, "recordar-stale: ningun mensaje nuevo")
}

/// Pins the view wiring: the sheets build their closure with this method, so
/// a closure made for A and fired after B arrived must leave B pending.
@MainActor func testSheetClosureBuiltForAnOlderRequestLeavesTheNewOnePending() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("hoja: arranca") { vm.job != nil }
    let a1 = request("a1")
    vm.receiveJobEvent(.approvalRequested(a1), from: vm.chatJobID)
    let answerForA = vm.approvalAnswer(for: a1)
    vm.answerApproval(true, requestId: "a1")
    vm.receiveJobEvent(.approvalRequested(request("b1")), from: vm.chatJobID)
    answerForA(false, false)
    expectEq(vm.pendingApproval?.requestId, "b1", "hoja: la clausura de a1 no toca b1")
    await settle(0.15)
    expect(!submitter.cancelled, "hoja: nada se niega")
    let answerForB = vm.approvalAnswer(for: request("b1"))
    answerForB(true, false)
    expect(vm.pendingApproval == nil, "hoja: la clausura de b1 si la contesta")
}

@MainActor func testAnswerWithNothingPendingIsLoggedAndIgnored() async {
    let submitter = WatchfulSubmitter()
    let lines = LogLines()
    let vm = awaiting(submitter, log: lines.append)
    await pumpUntil("nada: arranca") { vm.job != nil }
    let before = vm.messages.count
    vm.answerApproval(true, requestId: "ghost")
    await settle(0.15)
    expectEq(vm.messages.count, before, "nada: ningun mensaje")
    expect(submitter.resolved.isEmpty, "nada: nada se resuelve")
    expect(lines.all.contains { $0.contains("ghost") && $0.contains("nothing is pending") },
           "nada: queda una linea de log")
}

private final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    func append(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
}
