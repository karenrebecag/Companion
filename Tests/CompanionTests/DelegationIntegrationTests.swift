import CompanionCore
import CompanionUI
@testable import CompanionServices
import Foundation
import Testing

/// End-to-end delegation: handoff → executor → result
@Test @MainActor
func delegationHandoffToResult() throws {
    let result = try runAsync {
        // Setup
        let executor = TestExecutor(output: "Archivo leído: 42 líneas")
        let provider = TestExecutorProvider(executor: executor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: provider,
            queue: queue,
            approvals: approvals
        )

        // Create handoff from user intent
        let handoff = Handoff(goal: "leer config.json", context: "en el directorio raíz")

        // Submit for execution
        let (eventStream, sink) = AsyncStream<JobEvent>.makeStream()
        let collector = Task {
            var collected: [JobEvent] = []
            for await event in eventStream { collected.append(event) }
            return collected
        }

        let result = try await runner.submit(handoff, events: sink)
        sink.finish()
        let collectedEvents = await collector.value

        return (result: result, events: collectedEvents)
    }

    let (jobResult, events) = result
    expectEq(jobResult.output, "Archivo leído: 42 líneas", "delegación: resultado vuelve del ejecutor")
    expect(!jobResult.isError, "delegación: sin error")
    expect(!events.isEmpty, "delegación: eventos emitidos")
}

@Test @MainActor
func delegationFailureIsReported() throws {
    let result = try runAsync {
        let executor = FailureExecutor()
        let provider = TestExecutorProvider(executor: executor)
        let approvals = Approvals(clock: RealtimeClock())
        let queue = JobQueue()
        let runner = JobRunner(
            executorProvider: provider,
            queue: queue,
            approvals: approvals
        )

        let handoff = Handoff(goal: "hacer algo imposible", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()

        let result = try await runner.submit(handoff, events: sink)
        return result
    }

    expect(result.isError, "delegación: fallo del ejecutor reportado")
    expect(!result.output.contains("Job failed"),
           "delegación: nada de errores internos hacia la usuaria")
    expect(!result.output.isEmpty && !result.output.contains("Error"),
           "delegación: el fallo se cuenta en humano")
}


// MARK: - Fakes

private struct TestExecutorProvider: ExecutorProviderProtocol {
    let executor: any Executor

    func selectExecutor(for _: Handoff) -> any Executor {
        executor
    }
}

private struct TestExecutor: Executor {
    let descriptor = ExecutorCatalog.native
    let output: String

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "read_file", summary: "Leyendo archivo"))
        events.yield(.stepFinished(tool: "read_file", ok: true))
        return JobResult(output: output, isError: false)
    }
}

private struct FailureExecutor: Executor {
    let descriptor = ExecutorCatalog.native

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        throw ChatError.unreachable
    }
}

private struct SlowExecutor: Executor {
    let descriptor = ExecutorCatalog.native

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await Task.sleep(for: .seconds(30))
        return JobResult(output: "done", isError: false)
    }
}


// MARK: - Cableado real (el punto donde este repo falla una y otra vez)

@Test @MainActor func delegationWiringTests() async {
    testApprovalReachesTheUser()
    await testAnsweringApprovalResolvesIt()
    testVoiceDelegatesInsteadOfRefusing()
    testStepsPaintInTheThread()
}

/// Voice-delegated jobs feed the same seam: their steps must land in the
/// thread as status lines, not vanish into a drained stream.
@MainActor func testStepsPaintInTheThread() {
    let vm = wiredViewModel(RecordingSubmitter())
    vm.receiveJobEvent(.stepStarted(tool: "write_file", summary: "prueba1.md"))
    expect(vm.messages.contains { $0.isStatus && $0.text.contains("prueba1.md") },
           "pasos: el encargo por voz pinta su linea de tiempo")
}

@MainActor private func wiredViewModel(_ submitter: RecordingSubmitter) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(replies: []),
        secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(),
        config: .default,
        jobSubmitter: submitter)
    vm.onAppear()
    return vm
}

/// The request must land in observable state; printing a line and waiting for
/// the 120s auto-deny is the failure this guards.
@MainActor func testApprovalReachesTheUser() {
    let vm = wiredViewModel(RecordingSubmitter())
    let request = ApprovalRequest(
        requestId: "r1", toolName: "run_shell",
        summary: "", inputJSON: "{\"command\":\"ls\"}")
    vm.receiveJobEvent(JobEvent.approvalRequested(request))
    expectEq(vm.pendingApproval?.requestId, "r1",
             "permiso: llega al estado que la hoja observa")
}

@MainActor func testAnsweringApprovalResolvesIt() async {
    let submitter = RecordingSubmitter()
    let vm = wiredViewModel(submitter)
    let request = ApprovalRequest(
        requestId: "r2", toolName: "write_file",
        summary: "", inputJSON: "{\"path\":\"a.txt\"}")
    vm.receiveJobEvent(JobEvent.approvalRequested(request))
    vm.answerApproval(true)
    expect(vm.pendingApproval == nil, "permiso: la hoja se cierra al responder")
    await pumpUntil("permiso: la respuesta llega al especialista") {
        submitter.resolved == [ResolvedCall(id: "r2", approved: true)]
    }
}

/// The voice used to answer "delegation is not available yet".
@MainActor func testVoiceDelegatesInsteadOfRefusing() {
    let readable = ChatCopy.approvalDetail(
        tool: "run_shell", inputJSON: "{\"command\":\"rm -rf /tmp/x\"}")
    expectEq(readable, "rm -rf /tmp/x",
             "permiso: se muestra el comando, no el JSON crudo")
}

struct ResolvedCall: Equatable {
    let id: String
    let approved: Bool
}

final class RecordingSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [ResolvedCall] = []
    var resolved: [ResolvedCall] { lock.withLock { calls } }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        JobResult(output: "ok", isError: false)
    }
    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {
        lock.withLock { calls.append(ResolvedCall(id: requestId, approved: approved)) }
    }
    var isBusy: Bool { get async { false } }
}
