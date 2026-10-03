import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Review 16h-2 round 3 (SHOULD 1-2): the chat only ever speaks for its own
// job. A voice-born job shares the projection, not the chat's thread: the
// chat's end, brake and sheet never write a voice job's record, a voice
// reply never closes the chat's card, and the chat's job ends only after its
// last event reached the projection.

@Test @MainActor func chatJobOwnershipTests() async {
    await testAVoiceReplyDoesNotCloseTheChatsJob()
    testStoppingAVoiceJobFromTheChatWritesNoRecordOfIt()
    testDenyingAVoiceJobsFirstStepWritesNoRecordOfIt()
    testTheChatsOwnEndStillLeavesItsRecord()
    await testTheChatsJobEndsAfterItsLastStep()
}

private let voiceJob = JobID("voz")

@MainActor private func chatWithJobs(_ jobs: any JobSubmitter = WatchfulSubmitter()) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default, jobSubmitter: jobs)
    vm.onAppear()
    return vm
}

@MainActor private func recorded(_ vm: ChatViewModel, _ goal: String) -> Bool {
    vm.messages.contains { $0.isStatus && $0.text.contains(goal) }
}

/// The realtime voice's replies land in this thread too; one of them is not
/// the chat job's result.
@MainActor func testAVoiceReplyDoesNotCloseTheChatsJob() async {
    let vm = chatWithJobs()
    vm.startJob(goal: "ordenar Descargas")
    await vm.appendAssistant("Son las diez.")
    expectEq(vm.job?.goal, "ordenar Descargas", "dueño: una respuesta de voz no cierra la tarjeta del chat")
}

@MainActor func testStoppingAVoiceJobFromTheChatWritesNoRecordOfIt() {
    let vm = chatWithJobs()
    vm.receive(.job(.started(goal: "buscar vuelos"), from: voiceJob))
    vm.cancelJob()
    expect(vm.job == nil, "dueño: el freno para también el encargo de voz")
    expect(!recorded(vm, "buscar vuelos"), "dueño: el chat no escribe el registro de un encargo de voz")
    expect(!vm.cancelledJob, "dueño: y no marca como parado un encargo del chat que no existe")
}

@MainActor func testDenyingAVoiceJobsFirstStepWritesNoRecordOfIt() {
    let vm = chatWithJobs()
    vm.receive(.job(.started(goal: "buscar vuelos"), from: voiceJob))
    vm.receive(.job(.approvalRequested(ApprovalRequest(
        requestId: "v1", toolName: "run_shell", summary: "ls", inputJSON: "{}")), from: voiceJob))
    vm.answerPendingApproval(false)
    expect(vm.job == nil, "dueño: negar su primer paso para el encargo de voz")
    expect(!recorded(vm, "buscar vuelos"), "dueño: sin registro suyo en el hilo del chat")
    expect(!vm.cancelledJob, "dueño: ni marca parado al chat")
}

@MainActor func testTheChatsOwnEndStillLeavesItsRecord() {
    let vm = chatWithJobs()
    let id = vm.startJob(goal: "ordenar Descargas")
    vm.receiveJobEvent(.stepStarted(tool: "Bash", summary: "ls"), from: id)
    vm.finishJob(ok: true, id: id)
    expect(vm.job == nil, "dueño: su fin cierra su tarjeta")
    expect(recorded(vm, "ordenar Descargas"), "dueño: y deja su registro")
}

/// Many steps and an immediate return: the end must not overtake them, or
/// the late ones open a nameless row after the card closed.
@MainActor func testTheChatsJobEndsAfterItsLastStep() async {
    let jobs = BurstSubmitter(steps: 300)
    let vm = chatWithJobs(jobs)
    await vm.runJob(preface: "", handoff: Handoff(goal: "ordenar", context: ""), submitter: jobs)
    expect(vm.job == nil, "dueño: ningún paso tardío reabre la fila (\(String(describing: vm.job)))")
}

/// Yields a burst of steps and answers at once.
private struct BurstSubmitter: JobSubmitter {
    let steps: Int
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        for index in 0 ..< steps {
            events.yield(.stepStarted(tool: "Bash", summary: "paso \(index)"))
        }
        return JobResult(output: "hecho", isError: false)
    }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}
