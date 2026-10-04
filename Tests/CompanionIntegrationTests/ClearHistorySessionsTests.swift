import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

/// Only a clear moves the sessions generation. Starting or switching a thread
/// must not stop a specialist that is mid-job from saving where it left off.
@Suite("ClearHistory")
struct ClearHistorySessionsTests {
    @Test @MainActor func jobHeldAcrossNewConversationAndSwitchStillWrites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-g12-threads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConversationStore(directory: root.appendingPathComponent("conversations"))
        let sessions = FileExecutorSessionStore(
            fileURL: root.appendingPathComponent("executor-sessions.json"))
        let vm = ChatViewModel(
            chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
            store: store, config: .default)
        vm.onAppear()
        await vm.appendUser("hola")
        let first = vm.conversationId

        let hold = HoldLauncher()
        let built = ExecutorFactory.createExecutor(
            descriptor: ExecutorDescriptor(
                id: .hermes, shortName: "hermes", title: "Hermes", kind: .detectedCLI),
            workdir: "/tmp/test", executablePath: "/stub/bin/hermes",
            processLauncher: hold, approvals: DenyingApprovals(),
            sessions: sessions)
        let executor = try #require(built)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        let run = Task {
            try await executor.run(JobRequest(id: "j-held", goal: "seguir", context: ""), events: sink)
        }
        await hold.waitUntilLaunched()

        vm.newConversation()
        vm.openConversation(first)
        hold.release()
        _ = try await run.value

        expectEq(sessions.currentGeneration(), 0, "starting and switching threads is not a clear")
        expectEq(
            sessions.session(for: ExecutorSessionKey(executor: .hermes, workdir: "/tmp/test")),
            ExecutorSessions.latest,
            "the job that outlived the thread switch still saved its thread")
    }
}
