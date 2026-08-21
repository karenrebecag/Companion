import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func nativeExecutorTests() {
    testSimpleReadFileExecution()
    testToolExecutionWithApproval()
}

// MARK: - Fake Chat Provider for testing

final class TestChatProvider: ChatProvider, @unchecked Sendable {
    var scriptedResponses: [String] = []
    var capturedHistory: [Turn]?
    var capturedTools: [ToolSpec]?

    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        self.capturedHistory = history
        self.capturedTools = tools
        return AsyncThrowingStream { continuation in
            Task {
                for response in scriptedResponses {
                    continuation.yield(.text(response))
                }
                continuation.finish()
            }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

// MARK: - Simple Executor Test

@MainActor func testSimpleReadFileExecution() {
    let tempDir = FileManager.default.temporaryDirectory.path
    let testFile = (tempDir as NSString).appendingPathComponent("test.txt")
    try! "content".write(toFile: testFile, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: testFile) }

    let chatProvider = TestChatProvider()
    chatProvider.scriptedResponses = ["I will read the file."]

    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native,
        chatProvider: chatProvider,
        config: Config(workdir: tempDir))

    let job = JobRequest(
        id: "job-1",
        goal: "Read test.txt",
        context: "")

    let result = try! runAsync {
        let (stream, continuation) = AsyncStream<JobEvent>.makeStream()

        // Spawn task to drain the stream but don't cancel it
        let drainTask = Task {
            for await _ in stream {}
        }

        let output = try await executor.run(job, events: continuation)
        continuation.finish()

        // Wait briefly for drain task to finish
        try? await drainTask.value

        return output
    }

    expectEq(result.isError, false, "executor: completes successfully")
}

// MARK: - Tool Execution Test

@MainActor func testToolExecutionWithApproval() {
    let tempDir = FileManager.default.temporaryDirectory.path
    defer { try? FileManager.default.removeItem(atPath: tempDir) }

    let chatProvider = TestChatProvider()
    chatProvider.scriptedResponses = ["Done with work."]

    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native,
        chatProvider: chatProvider,
        config: Config(workdir: tempDir))

    let job = JobRequest(
        id: "job-2",
        goal: "Do something",
        context: "")

    let result = try! runAsync {
        let (stream, continuation) = AsyncStream<JobEvent>.makeStream()

        let drainTask = Task {
            for await _ in stream {}
        }

        let output = try await executor.run(job, events: continuation)
        continuation.finish()
        try? await drainTask.value

        return output
    }

    expect(!result.isError, "executor: completes without error")
}
