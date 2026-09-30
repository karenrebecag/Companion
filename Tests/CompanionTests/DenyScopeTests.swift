import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

@Test @MainActor func denyScopeTests() async {
    await testDenyingTheFirstActionStopsTheJob()
    await testDenyingALaterActionOnlyRefusesThatAction()
    await testApprovingNeverStops()
    await testDenyingTheFirstActionRemembersNothing()
}

@MainActor private func awaiting(_ submitter: WatchfulSubmitter) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default,
        jobSubmitter: submitter)
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
    vm.answerApproval(false)
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
    vm.answerApproval(true)
    vm.receiveJobEvent(.approvalRequested(request("a2")), from: vm.chatJobID)
    vm.answerApproval(false)
    await settle(0.15)
    expect(!submitter.cancelled,
           "negar un paso posterior no tira lo que ya autorizaste")
}

@MainActor func testApprovingNeverStops() async {
    let submitter = WatchfulSubmitter()
    let vm = awaiting(submitter)
    await pumpUntil("arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(true)
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
    vm.answerApproval(false, remember: true)
    await pumpUntil("recuerda: para") { submitter.cancelled }
    await pumpUntil("recuerda: resolvió") { !submitter.remembered.isEmpty }
    expectEq(submitter.remembered, [false], "recuerda: el primer no no se recuerda")
}
