import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// MARK: - RED Phase: ClaudeCodeExecutor Tests

@Test @MainActor
func claudeCodeExecutorDescriptorIdentifies() throws {
    let launcher = StubProcessLauncher()
    let approvals = InstantApprovals(approved: false)

    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test",
        processLauncher: launcher,
        approvals: approvals
    )

    expectEq(executor.descriptor.id.rawValue, "claude-code", "descriptor id")
    expectEq(executor.descriptor.shortName, "claude", "short name")
    expectEq(executor.descriptor.kind, .detectedCLI, "kind is detectedCLI")
}

@Test @MainActor
func claudeCodeExecutorRunsJobWithTranscript() throws {
    let result = try runAsync {
        let launcher = StubProcessLauncher()
        let approvals = InstantApprovals(approved: false)

        let executor = ClaudeCodeExecutor(
            workdir: "/tmp/test",
            processLauncher: launcher,
            approvals: approvals
        )

        let job = JobRequest(id: "job-1", goal: "list files", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()

        let transcript = [
            #"{"type":"system","subtype":"init","session_id":"claude-123"}"#,
            #"{"type":"result","result":"file1 file2 file3","is_error":false}"#
        ]
        launcher.setResponseTranscript(transcript)

        let jobResult = try await executor.run(job, events: sink)
        return jobResult
    }

    expectEq(result.output, "file1 file2 file3", "executor returns result")
    expect(!result.isError, "result is not error")
}

@Test @MainActor
func claudeCodeExecutorEmitsStepEvents() throws {
    let result = try runAsync {
        let launcher = StubProcessLauncher()
        let approvals = InstantApprovals(approved: false)

        let executor = ClaudeCodeExecutor(
            workdir: "/tmp/test",
            processLauncher: launcher,
            approvals: approvals
        )

        let job = JobRequest(id: "job-1", goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()

        let transcript = [
            #"{"type":"system","subtype":"init","session_id":"s-1"}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"test"}}]}}"#,
            #"{"type":"result","result":"ok","is_error":false}"#
        ]
        launcher.setResponseTranscript(transcript)

        let collector = Task {
            var collected: [JobEvent] = []
            for await event in events {
                collected.append(event)
            }
            return collected
        }

        _ = try await executor.run(job, events: sink)
        sink.finish()

        return await collector.value
    }

    let hasStepStarted = result.contains { event in
        if case .stepStarted = event { return true }
        return false
    }
    let hasStepFinished = result.contains { event in
        if case .stepFinished = event { return true }
        return false
    }

    expect(hasStepStarted, "emits stepStarted")
    expect(hasStepFinished, "emits stepFinished")
}

@Test @MainActor
func claudeCodeExecutorRequestsApprovalForRiskyTools() throws {
    let result = try runAsync {
        let launcher = StubProcessLauncher()
        // Answers at once: the real actor waits two minutes for a human, which
        // would hang the suite (and starve every other test on the main actor).
        let approvals = InstantApprovals(approved: false)

        let executor = ClaudeCodeExecutor(
            workdir: "/tmp/test",
            processLauncher: launcher,
            approvals: approvals
        )

        let job = JobRequest(id: "job-1", goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()

        let transcript = [
            #"{"type":"system","subtype":"init","session_id":"s-1"}"#,
            #"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm -rf /tmp/x"}}}"#,
            #"{"type":"result","result":"denied","is_error":true}"#
        ]
        launcher.setResponseTranscript(transcript)

        let collector = Task {
            var collected: [JobEvent] = []
            for await event in events {
                collected.append(event)
            }
            return collected
        }

        _ = try await executor.run(job, events: sink)
        sink.finish()

        return await collector.value
    }

    let hasApprovalRequest = result.contains { event in
        if case .approvalRequested = event { return true }
        return false
    }

    expect(hasApprovalRequest, "emits approvalRequested")
}

// MARK: - Stubs compartidos

/// Actor-backed so several tests can drive it without a global mutable var
/// (which strict concurrency rejects outright).
final class StubProcessLauncher: ProcessLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var transcript: [String]?
    /// One queued answer per launch: probing twice must be able to say "found"
    /// and then "gone", which a single shared transcript cannot express.
    private var queued: [[String]] = []
    private(set) var launched: [(executable: String, cwd: String?)] = []

    func setResponseTranscript(_ lines: [String]) {
        lock.withLock { transcript = lines }
    }

    func setNextResponse(_ response: String?) {
        lock.withLock { queued.append(response.map { [$0] } ?? []) }
    }

    func launch(
        executable: String,
        arguments: [String],
        cwd: String?
    ) async -> (any ProcessHandle)? {
        let lines: [String] = lock.withLock {
            launched.append((executable, cwd))
            if !queued.isEmpty { return queued.removeFirst() }
            return transcript ?? []
        }
        return StubProcessHandle(transcript: lines)
    }
}

/// Replays a recorded NDJSON transcript; records whether it was terminated so
/// cancellation can be asserted without spawning anything.
final class StubProcessHandle: ProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let transcript: [String]
    private var index = 0
    private var terminated = false

    init(transcript: [String]) {
        self.transcript = transcript
    }

    var wasTerminated: Bool { lock.withLock { terminated } }

    func sendLine(_ line: String) async throws {}

    func readLine() async -> String? {
        lock.withLock {
            guard index < transcript.count else { return nil }
            defer { index += 1 }
            return transcript[index]
        }
    }

    func terminate() async {
        lock.withLock { terminated = true }
    }

    var isRunning: Bool {
        lock.withLock { !terminated && index < transcript.count }
    }
}

/// Labelled alias kept for the suites that call it this way; the real
/// implementation lives in TestKit.
@MainActor func runAsync<T: Sendable>(
    body: @escaping @Sendable () async throws -> T
) throws -> T {
    try runAsync(body)
}


/// Resolves immediately; the timeout behaviour of the real actor has its own
/// tests in ApprovalsTests.
struct InstantApprovals: ApprovalsProvider {
    let approved: Bool
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        ApprovalResponse(requestId: approval.requestId, approved: approved)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { true }
}
