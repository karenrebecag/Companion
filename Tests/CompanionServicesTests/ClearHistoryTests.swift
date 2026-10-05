import CompanionCore
import CompanionServices
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
        failing.set()

        expectThrows(PersistenceError.io, "a clear that cannot recreate the folder says so") {
            try store.clearHistory()
        }
        failing.clear()
        expectEq(try store.list().count, 2, "every chat is back in the original folder")
        expect(try store.load("chat-1") != nil, "the first chat loads")
        expect(try store.load("chat-2") != nil, "the second chat loads")
        expect(trash(beside: conversations).isEmpty, "no trash is left")
    }
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

private final class FailSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
    func clear() { lock.withLock { value = false } }
}
