import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Suite("ClearHistory")
struct ClearHistoryStoreTests {
    @Test func clearHistoryRemovesChatsTasksAndTheirFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let notes = root.appendingPathComponent("notes.txt")
        try Data("user file".utf8).write(to: notes)
        let photo = root.appendingPathComponent("photo.png")
        try Data([0x89, 0x50]).write(to: photo)
        let store = ConversationStore(directory: conversations)
        try store.save(sample("chat-1", title: "Notes", text: "hello", attachments: [photo.path]))
        try store.save(sample(
            "task-1", title: "Send the report", text: "done", at: 1_700_000_100))
        let before = try store.list()
        expectEq(before.count, 2, "two records before clear")
        expectEq(
            HomeTasks.sections(before, now: Date(timeIntervalSince1970: 1_700_000_100), calendar: .current)
                .flatMap(\.rows).count,
            2,
            "home tasks are those records")
        try store.clearHistory()
        expect(try store.list().isEmpty, "list is empty")
        expect(
            HomeTasks.sections(try store.list(), now: Date(), calendar: .current).isEmpty,
            "home has no tasks")
        expect(try store.load("chat-1") == nil, "chat is gone")
        expect(try store.load("task-1") == nil, "task is gone")
        let json = try FileManager.default.contentsOfDirectory(
            at: conversations, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        expect(json.isEmpty, "conversation files are gone")
        expect(FileManager.default.fileExists(atPath: notes.path), "the user's file stays")
        expect(FileManager.default.fileExists(atPath: photo.path), "a cited attachment stays")
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".companion-history-clear-") }
        expect(leftovers.isEmpty, "clear does not leave the old directory beside the folder")
    }

    @Test func clearHistoryOnEmptyDirectory() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("conversations", isDirectory: true)
        let store = ConversationStore(directory: missing)
        try store.clearHistory()
        expect(try store.list().isEmpty, "clearing nothing stays empty")
    }

    @Test func recreatedConversationsDirectoryIsOwnerOnly() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let store = ConversationStore(directory: conversations)
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        try store.clearHistory()
        expectEq(try permissions(of: conversations), 0o700, "the new directory is as private as the old one")
        try store.save(sample("chat-2", title: "After", text: "new"))
        expectEq(try store.list().count, 1, "the store works in the new directory")
    }

    @Test func clearFailsWhenParentIsReadOnlyAndKeepsEveryChat() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let store = ConversationStore(directory: parent.appendingPathComponent("conversations"))
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        try store.save(sample("chat-2", title: "More", text: "again", at: 1_700_000_100))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }

        expectThrows(PersistenceError.io, "a clear that cannot move the folder says so") {
            try store.clearHistory()
        }
        expectEq(try store.list().count, 2, "every chat is still there")
        expect(try store.load("chat-1") != nil, "the first chat loads")
        expect(try store.load("chat-2") != nil, "the second chat loads")
    }

    @Test func leftoverTrashIsSweptOnNextClear() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let store = ConversationStore(directory: conversations)
        let leftover = try plantTrash(beside: conversations)
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        try store.clearHistory()
        expect(!FileManager.default.fileExists(atPath: leftover.path), "an old trash folder is removed")
    }

    @Test func leftoverTrashIsSweptWhenTheStoreOpens() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let leftover = try plantTrash(beside: conversations)
        _ = ConversationStore(directory: conversations)
        expect(!FileManager.default.fileExists(atPath: leftover.path), "launch removes what a crash left")
    }

    @Test func removalFailureAfterRenameStillCountsAsCleared() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let store = ConversationStore(directory: conversations)
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        // A folder that refuses deletions makes the trash removal fail after
        // the folder was already moved aside.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: conversations.path)
        defer { unlockTrash(beside: conversations, lockedAt: conversations) }

        try store.clearHistory()

        expect(try store.list().isEmpty, "the chats are cut from the live folder, so the clear worked")
        expect(try store.load("chat-1") == nil, "the chat is not served from a half-deleted folder")
        expectEq(try permissions(of: conversations), 0o700, "the live folder is the fresh private one")
        expectEq(trash(beside: conversations).count, 1, "the old folder waits for the sweep")
        unlockTrash(beside: conversations, lockedAt: conversations)
        try store.clearHistory()
        expect(trash(beside: conversations).isEmpty, "the next clear sweeps what was left")
    }

    @Test func failedRecreateKeepsEveryChatInTheOriginalFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let failing = FailSwitch()
        let store = ConversationStore(directory: conversations, makeDirectory: { url in
            if failing.isSet { throw PersistenceError.io }
            try ConversationStore.defaultMakeDirectory(url)
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        try store.save(sample("chat-2", title: "More", text: "again", at: 1_700_000_100))
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        let key = ExecutorSessionKey(executor: .hermes, workdir: "/tmp/test")
        sessions.set("s-keep", for: key)
        failing.set()

        expectThrows(PersistenceError.io, "a clear that cannot recreate the folder says so") {
            try store.clearHistory()
        }
        failing.clear()
        expectEq(sessions.session(for: key), "s-keep", "a failed recreate puts the sessions back too")
        expectEq(try store.list().count, 2, "every chat is back in the original folder")
        expect(try store.load("chat-1") != nil, "the first chat loads")
        expect(try store.load("chat-2") != nil, "the second chat loads")
        expect(trash(beside: conversations).isEmpty, "no trash is left")
    }

    @Test func clearHistoryDropsExecutorSessionsSoAnErasedTaskCannotResume() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        // Same folder makeHermes runs in, or the launch would skip --resume
        // even while the erased task's record is still on disk.
        let key = ExecutorSessionKey(executor: .hermes, workdir: "/tmp/test")
        sessions.set(ExecutorSessions.latest, for: key)
        let store = ConversationStore(directory: conversations)
        try store.save(sample("task-1", title: "Send the report", text: "done"))

        try store.clearHistory()

        expect(try store.list().isEmpty, "the task chat is gone")
        expect(
            FileExecutorSessionStore(fileURL: sessionsURL).session(for: key) == nil,
            "the erased task has no session to resume")
        let launcher = ImmediateLauncher(lines: ["ok"])
        let executor = try makeHermes(sessions: sessions, launcher: launcher)
        _ = try await executor.run(
            JobRequest(id: "j-after", goal: "nuevo", context: ""), events: sink())
        expect(
            !launcher.arguments.contains("--resume"),
            "a launch after the clear does not resume the erased task")
    }

    @Test func lateExecutorWriteDoesNotResurrectASession() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        let key = ExecutorSessionKey(executor: .hermes, workdir: "/tmp/test")
        sessions.set("s-erased", for: key)
        let store = ConversationStore(directory: conversations)
        try store.save(sample("task-1", title: "Send the report", text: "done"))
        let hold = HoldLauncher()
        let executor = try makeHermes(sessions: sessions, launcher: hold)
        let run = Task {
            try await executor.run(
                JobRequest(id: "j-late", goal: "seguir", context: ""), events: sink())
        }
        await hold.waitUntilLaunched()

        try store.clearHistory()
        hold.release()
        _ = try await run.value

        expect(
            !FileManager.default.fileExists(atPath: sessionsURL.path),
            "the executor that finishes after the clear does not write the session back")
        let again = ImmediateLauncher(lines: ["ok"])
        let next = try makeHermes(sessions: sessions, launcher: again)
        _ = try await next.run(
            JobRequest(id: "j-new", goal: "despues", context: ""), events: sink())
        expectEq(
            sessions.session(for: key), ExecutorSessions.latest,
            "a task that starts after the clear can be resumed later")
    }

    @Test func failedClearKeepsExecutorSessions() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        let key = ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work")
        sessions.set("s-keep", for: key)
        // The park itself fails: nothing moved, so nothing may be lost.
        let store = ConversationStore(directory: conversations, moveItem: { from, to in
            if from.lastPathComponent == "executor-sessions.json" { throw PersistenceError.io }
            try ConversationStore.defaultMoveItem(from, to)
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))

        expectThrows(PersistenceError.io, "a clear that cannot park the sessions says so") {
            try store.clearHistory()
        }
        expectEq(sessions.session(for: key), "s-keep", "a failed clear keeps the session")
        expect(try store.load("chat-1") != nil, "and keeps the chat")
        expectEq(sessions.currentGeneration(), 0, "a clear that failed is not a clear")
    }

    @Test func failedFolderRenameBringsTheParkedSessionsBack() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        let key = ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work")
        sessions.set("s-keep", for: key)
        // The park succeeds; only the cut of the folder fails.
        let store = ConversationStore(directory: conversations, moveItem: { from, to in
            if to.lastPathComponent.hasPrefix(".companion-history-clear-") { throw PersistenceError.io }
            try ConversationStore.defaultMoveItem(from, to)
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))

        expectThrows(PersistenceError.io, "a clear that cannot cut the folder says so") {
            try store.clearHistory()
        }
        expect(
            FileManager.default.fileExists(atPath: sessionsURL.path),
            "the sessions file is back beside the folder")
        expectEq(sessions.session(for: key), "s-keep", "and still readable")
        expect(
            !FileManager.default.fileExists(
                atPath: conversations.appendingPathComponent(".executor-sessions-clear").path),
            "no parked copy is left in the live folder")
        expect(try store.load("chat-1") != nil, "the chat still loads")
        expectEq(sessions.currentGeneration(), 0, "a clear that failed is not a clear")
    }
}

@Suite("ClearHistory")
struct ClearHistorySessionTests {
    @Test func storeAndClearShareTheEpochWhetherOrNotTheFileExists() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let sessions = FileExecutorSessionStore(fileURL: sessionsURL)
        let store = ConversationStore(directory: conversations)

        try store.clearHistory()
        expectEq(sessions.currentGeneration(), 1, "a clear before the file exists moves the epoch")

        sessions.set("s-1", for: ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work"))
        try store.clearHistory()
        expectEq(sessions.currentGeneration(), 2, "and so does one after the file exists")
        expectEq(
            FileExecutorSessionStore(fileURL: sessionsURL).currentGeneration(), 2,
            "a store opened later sees the same epoch")
    }

    @Test func epochDoesNotDependOnTheFileExisting() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("executor-sessions.json")
        let before = ExecutorSessionEpochs.shared(file: file)
        try Data("{}".utf8).write(to: file)
        let after = ExecutorSessionEpochs.shared(file: file)
        expect(before === after, "creating the file does not change which epoch the path maps to")

        // Fixed spellings: the alias must hold wherever TMPDIR points.
        let plain = URL(fileURLWithPath: "/var/folders/x/executor-sessions.json")
        let aliased = URL(fileURLWithPath: "/private/var/folders/x/executor-sessions.json")
        expect(
            ExecutorSessionEpochs.shared(file: plain) === ExecutorSessionEpochs.shared(file: aliased),
            "/var and /private/var are one epoch")
    }

    @Test func parkedSessionsFileIsErasedEvenWhenTheTrashFolderStays() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessions = FileExecutorSessionStore(
            fileURL: root.appendingPathComponent("executor-sessions.json"))
        sessions.set("s-erased", for: ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work"))
        let store = ConversationStore(directory: conversations, removeItem: { url in
            if url.lastPathComponent.hasPrefix(".companion-history-clear-") {
                throw PersistenceError.io
            }
            try ConversationStore.defaultRemoveItem(url)
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))

        try store.clearHistory()

        let left = trash(beside: conversations)
        expectEq(left.count, 1, "the trash folder is the one that stayed")
        expect(
            !FileManager.default.fileExists(
                atPath: left[0].appendingPathComponent(".executor-sessions-clear").path),
            "the erased sessions do not wait inside it for the next launch")
    }

    @Test func crashAfterParkingPutsTheSessionsBackOnLaunch() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let key = ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work")
        try parkSessions("s-parked", key: key, root: root, into: conversations)
        expect(!FileManager.default.fileExists(atPath: sessionsURL.path), "the only copy is parked")

        let store = ConversationStore(directory: conversations)

        expectEq(
            FileExecutorSessionStore(fileURL: sessionsURL).session(for: key), "s-parked",
            "a fresh store reads the restored session")
        expect(try store.list().isEmpty, "the parked file is not a chat")
    }

    @Test func liveSessionsWinOverAParkedLeftover() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let key = ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work")
        try parkSessions("s-parked", key: key, root: root, into: conversations)
        FileExecutorSessionStore(fileURL: sessionsURL).set("s-live", for: key)

        _ = ConversationStore(directory: conversations)

        expectEq(
            FileExecutorSessionStore(fileURL: sessionsURL).session(for: key), "s-live",
            "the live file is what a resume reads")
        expect(
            !FileManager.default.fileExists(
                atPath: conversations.appendingPathComponent(".executor-sessions-clear").path),
            "the parked leftover is removed")
    }

    @Test func parkedFileInsideOldTrashDoesNotComeBackOnLaunch() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessionsURL = root.appendingPathComponent("executor-sessions.json")
        let key = ExecutorSessionKey(executor: .claudeCode, workdir: "/tmp/work")
        FileExecutorSessionStore(fileURL: sessionsURL).set("s-erased", for: key)
        // Nothing can be removed, so the parked file is stranded in the trash.
        let store = ConversationStore(directory: conversations, removeItem: { _ in
            throw PersistenceError.io
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        try store.clearHistory()
        expectEq(trash(beside: conversations).count, 1, "the clear left its trash behind")

        _ = ConversationStore(directory: conversations)

        expect(
            !FileManager.default.fileExists(atPath: sessionsURL.path),
            "the erased sessions are not recreated by the next launch")
        expect(trash(beside: conversations).isEmpty, "the launch swept the trash")
    }

    @Test func failedClearLeavesTheGenerationAndALateJobStillWrites() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversations = root.appendingPathComponent("conversations", isDirectory: true)
        let sessions = FileExecutorSessionStore(
            fileURL: root.appendingPathComponent("executor-sessions.json"))
        let failing = FailSwitch()
        let store = ConversationStore(directory: conversations, makeDirectory: { url in
            if failing.isSet { throw PersistenceError.io }
            try ConversationStore.defaultMakeDirectory(url)
        })
        try store.save(sample("chat-1", title: "Notes", text: "hello"))
        let hold = HoldLauncher()
        let executor = try makeHermes(sessions: sessions, launcher: hold)
        let run = Task {
            try await executor.run(
                JobRequest(id: "j-held", goal: "seguir", context: ""), events: sink())
        }
        await hold.waitUntilLaunched()

        failing.set()
        expectThrows(PersistenceError.io, "the clear fails") { try store.clearHistory() }
        failing.clear()
        hold.release()
        _ = try await run.value

        expectEq(sessions.currentGeneration(), 0, "a failed clear does not move the generation")
        expectEq(
            sessions.session(for: ExecutorSessionKey(executor: .hermes, workdir: "/tmp/test")),
            ExecutorSessions.latest,
            "the job that was running still saves its thread")
    }
}

/// What a clear parks inside the conversations folder before the cut.
private func parkSessions(
    _ id: String, key: ExecutorSessionKey, root: URL, into conversations: URL
) throws {
    let scratch = root.appendingPathComponent("scratch-sessions.json")
    FileExecutorSessionStore(fileURL: scratch).set(id, for: key)
    try FileManager.default.createDirectory(at: conversations, withIntermediateDirectories: true)
    try FileManager.default.moveItem(
        at: scratch, to: conversations.appendingPathComponent(".executor-sessions-clear"))
}

private func permissions(of url: URL) throws -> Int {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private func trash(beside directory: URL) -> [URL] {
    let siblings = (try? FileManager.default.contentsOfDirectory(
        at: directory.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
    return siblings.filter { $0.lastPathComponent.hasPrefix(".companion-history-clear-") }
}

private func plantTrash(beside directory: URL) throws -> URL {
    let leftover = directory.deletingLastPathComponent()
        .appendingPathComponent(".companion-history-clear-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
    try Data("old chat".utf8).write(to: leftover.appendingPathComponent("chat-old.json"))
    return leftover
}

/// The trash is the folder that was moved, so it carries the read-only mode.
private func unlockTrash(beside directory: URL, lockedAt: URL) {
    for url in trash(beside: directory) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedAt.path)
}

private func makeRoot() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-g12-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func sample(
    _ id: String,
    title: String,
    text: String,
    attachments: [String] = [],
    at stamp: TimeInterval = 1_700_000_000
) -> ConversationRecord {
    ConversationRecord(
        id: id,
        title: title,
        updatedAt: Date(timeIntervalSince1970: stamp),
        messages: [ConversationMessage(role: "user", text: text, attachmentPaths: attachments)])
}

private func expectThrows(
    _ expected: PersistenceError, _ label: String, _ body: () throws -> Void
) {
    do {
        try body()
        expect(false, "\(label): nothing was thrown")
    } catch let error as PersistenceError {
        expectEq(error, expected, label)
    } catch {
        expect(false, "\(label): threw \(error)")
    }
}

private func sink() -> AsyncStream<JobEvent>.Continuation {
    let (events, continuation) = AsyncStream<JobEvent>.makeStream()
    events.ignore()
    return continuation
}

private func makeHermes(
    sessions: FileExecutorSessionStore, launcher: any ProcessLauncher
) throws -> any Executor {
    let built = ExecutorFactory.createExecutor(
        descriptor: ExecutorDescriptor(
            id: .hermes, shortName: "hermes", title: "Hermes", kind: .detectedCLI),
        workdir: "/tmp/test",
        executablePath: "/stub/bin/hermes",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false),
        sessions: sessions)
    guard let built else {
        struct Missing: Error {}
        throw Missing()
    }
    return built
}

private final class ImmediateLauncher: ProcessLauncher, @unchecked Sendable {
    private let lines: [String]
    private let lock = NSLock()
    private var recorded: [String] = []
    var arguments: [String] { lock.withLock { recorded } }

    init(lines: [String]) { self.lines = lines }

    func launch(
        executable: String, arguments: [String], cwd: String?
    ) async -> (any ProcessHandle)? {
        lock.withLock { recorded = arguments }
        return LineHandle(lines: lines)
    }
}

private final class LineHandle: ProcessHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String]
    init(lines: [String]) { self.lines = lines }
    func sendLine(_ line: String) async throws {}
    func readLine() async -> String? { lock.withLock { lines.isEmpty ? nil : lines.removeFirst() } }
    func terminate() async {}
    var isRunning: Bool { lock.withLock { !lines.isEmpty } }
}

private final class FailSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
    func clear() { lock.withLock { value = false } }
}
