import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

/// ExecutorProvider caches the claude executor for the app's life, so what a
/// clear erased on disk must also leave the executor's memory and process.
@Suite("ClearHistory")
struct ClearHistoryClaudeTests {
    private static let key = ExecutorSessionKey(
        executor: ExecutorID(rawValue: "claude-code"), workdir: "/tmp/test")
    private static let hello = #"{"type":"system","subtype":"init","session_id":"S1"}"#
    private static let done = #"{"type":"result","result":"ok","is_error":false}"#

    @Test func clearMakesALiveClaudeProcessGoAway() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let launcher = AliveLauncher([[Self.hello, Self.done], [Self.done]])
        let executor = try rig.executor(launcher)
        _ = try await executor.run(JobRequest(id: "j1", goal: "uno", context: ""), events: rig.sink())
        expectEq(rig.sessions.session(for: Self.key), "S1", "the first job saved its thread")

        try rig.store.clearHistory()
        _ = try await executor.run(JobRequest(id: "j2", goal: "dos", context: ""), events: rig.sink())

        expect(launcher.handles[0].wasTerminated, "the process holding the erased chat was ended")
        expectEq(launcher.launched.count, 2, "the next job got its own process")
        let args = launcher.launched[1]
        expect(args.contains("--input-format"), "the new process is a streaming one, not a batch retry")
        expect(!args.contains("--resume"), "it does not resume the erased thread")
        expect(
            rig.sessions.session(for: Self.key) != "S1", "the erased thread is not in the store")
    }

    @Test func clearMakesADeadClaudeProcessRelaunchWithoutTheOldThread() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let launcher = StubProcessLauncher()
        launcher.setNextTranscript([Self.hello, Self.done])
        launcher.setNextTranscript([Self.done])
        let executor = try rig.executor(launcher)
        _ = try await executor.run(JobRequest(id: "j1", goal: "uno", context: ""), events: rig.sink())

        try rig.store.clearHistory()
        _ = try await executor.run(JobRequest(id: "j2", goal: "dos", context: ""), events: rig.sink())

        expectEq(launcher.launched.count, 2, "the dead process was relaunched once")
        expect(
            !launcher.launched[1].arguments.contains("--resume"),
            "the relaunch does not carry the erased S1")
        expectEq(rig.sessions.session(for: Self.key), nil, "the store stays without S1")
    }

    @Test func claudeThreadAnnouncedAfterTheClearIsNotSaved() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let hold = HoldLauncher(lines: [Self.hello])
        let executor = try rig.executor(hold)
        let run = Task {
            try? await executor.run(JobRequest(id: "j1", goal: "uno", context: ""), events: rig.sink())
        }
        await hold.waitUntilLaunched()

        try rig.store.clearHistory()
        hold.release()
        _ = await run.value

        expect(
            !FileManager.default.fileExists(atPath: rig.sessionsURL.path),
            "the late hello wrote nothing")
    }

    @Test func claudeBatchFallbackAfterTheClearDoesNotResumeTheLateThread() async throws {
        let rig = try Rig()
        defer { rig.cleanup() }
        let hold = HoldLauncher(lines: [Self.hello])
        let executor = try rig.executor(hold)
        let run = Task {
            try? await executor.run(JobRequest(id: "j1", goal: "uno", context: ""), events: rig.sink())
        }
        await hold.waitUntilLaunched()

        try rig.store.clearHistory()
        hold.release()
        _ = await run.value

        // The stream closes after the hello, so the job falls back to batch.
        let batch = hold.launchedArguments.dropFirst().first ?? []
        expect(!batch.isEmpty, "the stream died and the batch ran")
        expect(!batch.contains("--resume"), "the batch does not resume what the clear erased")
    }
}

private struct Rig {
    let root: URL
    let sessionsURL: URL
    let sessions: FileExecutorSessionStore
    let store: ConversationStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-g12-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        sessionsURL = root.appendingPathComponent("executor-sessions.json")
        sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        store = ConversationStore(directory: root.appendingPathComponent("conversations"))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func sink() -> AsyncStream<JobEvent>.Continuation {
        let (events, continuation) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return continuation
    }

    /// Built by the factory, as the app does, so the generation pin is on.
    func executor(_ launcher: any ProcessLauncher) throws -> any Executor {
        let built = ExecutorFactory.createExecutor(
            descriptor: ExecutorDescriptor(
                id: .claudeCode, shortName: "claude", title: "Claude Code", kind: .detectedCLI),
            workdir: "/tmp/test",
            executablePath: "/stub/bin/claude",
            processLauncher: launcher,
            approvals: InstantApprovals(approved: false),
            sessions: sessions)
        guard let built else {
            struct Missing: Error {}
            throw Missing()
        }
        return built
    }
}

/// Handles that stay alive after their lines run out, as an idle claude does.
private final class AliveLauncher: ProcessLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [[String]]
    private var all: [AliveHandle] = []
    private var args: [[String]] = []

    init(_ transcripts: [[String]]) { queued = transcripts }

    var handles: [AliveHandle] { lock.withLock { all } }
    var launched: [[String]] { lock.withLock { args } }

    func launch(
        executable: String, arguments: [String], cwd: String?
    ) async -> (any ProcessHandle)? {
        lock.withLock {
            args.append(arguments)
            let handle = AliveHandle(lines: queued.isEmpty ? [] : queued.removeFirst())
            all.append(handle)
            return handle
        }
    }
}

private final class AliveHandle: ProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String]
    private var terminated = false

    init(lines: [String]) { self.lines = lines }

    var wasTerminated: Bool { lock.withLock { terminated } }
    func sendLine(_ line: String) async throws {}
    func readLine() async -> String? { lock.withLock { lines.isEmpty ? nil : lines.removeFirst() } }
    func terminate() async { lock.withLock { terminated = true } }
    var isRunning: Bool { lock.withLock { !terminated } }
}
