import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// The real entry point: NativeExecutor builds the ApprovalRequest and asks.
// Disposal is faked so an approved delete never reaches the real Trash.

private final class CallsDeleteProvider: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var round = 0
    private var _histories: [[Turn]] = []
    private let rounds: Int
    private let path: String

    init(path: String, rounds: Int = 1) { self.path = path; self.rounds = rounds }

    var histories: [[Turn]] { lock.withLock { _histories } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let n = lock.withLock { () -> Int in round += 1; _histories.append(history); return round }
        let path = path, rounds = rounds
        return AsyncThrowingStream { continuation in
            if n <= rounds {
                continuation.yield(.toolCalls([ToolCallRef(
                    id: "call_\(n)", name: "delete_file", arguments: "{\"path\":\"\(path)\"}")]))
            } else {
                continuation.yield(.text("done"))
            }
            continuation.finish()
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

@MainActor private func runJob(
    _ sandbox: DeleteSandbox, path: String, rounds: Int = 1, approvals: any ApprovalsProvider, recorder: DeleteRecorder
) async throws -> CallsDeleteProvider {
    let provider = CallsDeleteProvider(path: path, rounds: rounds)
    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native, chatProvider: provider,
        config: Config(workdir: sandbox.work), approvals: approvals, disposal: recorder.disposal)
    let (stream, continuation) = AsyncStream<JobEvent>.makeStream()
    stream.ignore()
    _ = try await executor.run(JobRequest(id: "job", goal: "Delete", context: ""), events: continuation)
    continuation.finish()
    return provider
}

@Test(.timeLimit(.minutes(1))) @MainActor
func approvedDeleteIsAskedOnceWithTheToolAndPathThenTrashed() async throws {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let approvals = ScriptedApprovals(answer: true)
    let recorder = DeleteRecorder()
    _ = try await runJob(sandbox, path: file, approvals: approvals, recorder: recorder)
    expectEq(approvals.requests.count, 1, "asked exactly once")
    expectEq(approvals.requests.first?.toolName, "delete_file", "asked about delete_file")
    expect(approvals.requests.first?.inputJSON.contains(file) == true, "the sheet input carries the path")
    expectEq(recorder.calls.trashed, [resolvedPath(file)], "approved: it went to the Trash")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func deniedDeleteLeavesTheFileAndTheModelReadsTheDenial() async throws {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let approvals = ScriptedApprovals(answer: false)
    let recorder = DeleteRecorder()
    let provider = try await runJob(sandbox, path: file, approvals: approvals, recorder: recorder)
    expectEq(approvals.requests.count, 1, "denied: asked once")
    expectEq(recorder.calls, DeleteDisposed(), "denied: nothing disposed")
    expect(sandbox.exists(file), "denied: the file is still there")
    let answer = provider.histories.last?.last(where: { $0.role == .tool })?.content
    expectEq(answer, Escalation.deniedByUser(Config(workdir: sandbox.work).language), "denied: the model gets the denial text")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func aSecondIdenticalDeleteAsksAgainEvenAfterARememberedYes() async throws {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    // `remembered: true` is what a ticked "remember" would leave behind for a
    // tool that had a key; the real actor and the fake both answer nil for no key.
    let approvals = ScriptedApprovals(answer: true, remembered: true)
    let recorder = DeleteRecorder()
    _ = try await runJob(sandbox, path: file, rounds: 2, approvals: approvals, recorder: recorder)
    expectEq(approvals.requests.count, 2, "two identical requests, two sheets")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func noYesIsEverRememberedOrSpokenForDeleteFile() async throws {
    let approvals = Approvals(clock: MockClock())
    let request = ApprovalRequest(
        requestId: "r1", toolName: "delete_file", summary: "", inputJSON: #"{"path":"/tmp/a.md"}"#)
    let asked = Task { await approvals.request(request) }
    try await Task.sleep(nanoseconds: 20_000_000)
    _ = await approvals.resolve(requestId: "r1", approved: true, remember: true)
    let response = await asked.value
    expect(response.approved, "the click approves this one")
    let remembered = await approvals.remembered(request)
    expect(remembered == nil, "nothing remembered: the next delete asks again")
    expectEq(ApprovalRisk.of(toolName: "delete_file"), .high, "a spoken yes cannot settle it, only the sheet's click")
}
