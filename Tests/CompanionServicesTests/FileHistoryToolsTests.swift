import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// PR4c: list_file_history and restore_file_version over an injected, temp-root
// FileVersions (never .standard()). The model refers to a version by an opaque
// id and never sees the private store.

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

private func remove(_ url: URL) {
    // A test may leave a read-only folder behind.
    if let walker = FileManager.default.enumerator(atPath: url.path) {
        for case let entry as String in walker {
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url.appendingPathComponent(entry).path)
            } catch {}
        }
    }
    do { try FileManager.default.removeItem(at: url) } catch {}
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 1_790_000_000.0
    func now() -> Date {
        lock.lock()
        defer { lock.unlock(); }
        seconds += 1
        return Date(timeIntervalSince1970: seconds)
    }
}

private func store(
    _ root: URL, bytes: Int = FileVersions.defaultMaxBytes, maxVersions: Int = 20, clock: Clock = Clock()
) -> FileVersions {
    FileVersions(root: root, maxVersions: maxVersions, maxBytes: bytes, now: { clock.now() })
}

private func write(_ text: String, to path: String) throws {
    try FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

private func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

private func runner(_ dir: URL, versions: FileVersions?, language: AppLanguage = .en) -> NativeToolRunner {
    NativeToolRunner(workdir: dir.path, places: nil, language: language, versions: versions, home: dir)
}

/// The ids the model was given, newest first, read back from the tool's own output.
private func ids(in output: String) -> [String] {
    output.split(separator: "\n").compactMap { line in
        line.range(of: "^[0-9A-F]{8}", options: .regularExpression).map { String(line[$0]) }
    }
}

private struct Fixture {
    let dir: URL
    let root: URL
    let versions: FileVersions
    let file: String
    /// Two kept copies of `file` ("ONE" before the second save, "TWO" after it), then "NOW" on disk.
    static func make(name: String = "q3.pdf", maxVersions: Int = 20) throws -> Fixture {
        let dir = try scratch()
        let root = dir.appendingPathComponent("store")
        let versions = store(root, maxVersions: maxVersions)
        let file = dir.appendingPathComponent(name).path
        try write("ONE", to: file)
        _ = versions.snapshot(file, trigger: .preSave)
        try write("TWO", to: file)
        _ = versions.snapshot(file, trigger: .postSave)
        try write("NOW", to: file)
        return Fixture(dir: dir, root: root, versions: versions, file: file)
    }

    func id(forContent text: String) throws -> String {
        let kept = versions.versions(of: file)
        let match = try #require(kept.first { (try? read($0.url.path)) == text })
        return String(match.url.lastPathComponent.split(separator: "-", maxSplits: 3)[2])
    }
}

// MARK: - list_file_history

@Test func listShowsTheVersionsNewestFirstWithTheirTriggerAndNoStorePath() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "list_file_history", arguments: ["path": "q3.pdf"], approved: false)
    expect(result.ok, "list: runs without the sheet")
    let lines = result.output.split(separator: "\n").filter { $0.range(of: "^[0-9A-F]{8}", options: .regularExpression) != nil }
    expectEq(lines.count, 2, "list: both versions")
    expect(lines[0].contains("post-save") && lines[1].contains("pre-save"), "list: newest first, with the trigger")
    expectEq(Set(ids(in: result.output)).count, 2, "list: two distinct ids")
    expect(!result.output.contains(f.root.path)
        && !result.output.contains("file-versions"), "list: the private store is never shown")
    expect(result.output.contains("only an existing file can be restored"), "list: says what restore needs")
    expect(f.versions.versions(of: f.file).allSatisfy { $0.url.path.hasPrefix(f.root.path + "/") },
           "list: every snapshot landed under the temp root, never the real store")
    let wasTouched = try read(f.file)
    expectEq(wasTouched, "NOW", "list: read-only")
}

@Test func listOfAFileWithNoHistorySaysSo() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    try write("x", to: dir.appendingPathComponent("a.pdf").path)
    let result = try await runner(dir, versions: store(dir.appendingPathComponent("store")))
        .execute(tool: "list_file_history", arguments: ["path": "a.pdf"], approved: false)
    expect(result.ok && result.output.contains("No saved versions"), "list: no history is a plain answer")
    expectEq(ids(in: result.output), [], "list: no ids")
}

@Test func listRefusesAPathOutsideTheWorkingFolder() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let outside = try scratch()
    defer { remove(outside) }
    let result = try await runner(outside, versions: f.versions)
        .execute(tool: "list_file_history", arguments: ["path": f.file], approved: false)
    expect(!result.ok && !result.output.contains("ONE"), "list: outside the folder is refused")
}

// MARK: - restore_file_version

@Test func restoreWithoutApprovalDoesNothing() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let before = f.versions.versions(of: f.file).count
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: false)
    expect(!result.ok, "restore: denied")
    expectEq(try read(f.file), "NOW", "restore: the file is untouched")
    expectEq(f.versions.versions(of: f.file).count, before, "restore: not even a copy was made")
}

@Test func anApprovedRestoreWritesTheVersionAndKeepsWhatWasThere() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(result.ok, "restore: done, got «\(result.output)»")
    expectEq(try read(f.file), "ONE", "restore: the file has the version's bytes")
    let kept = try f.versions.versions(of: f.file).map { try read($0.url.path) }
    expect(kept.contains("NOW"), "restore: a copy of what was there is kept, so it can be undone")
    expect(!result.output.contains(f.root.path), "restore: no store path")
    expect(result.output.contains("a copy of the previous content was kept"), "restore: says the undo exists")
}

@Test func aRestoreThroughASymlinkWritesTheRealFileAndKeepsItsLocation() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let link = f.dir.appendingPathComponent("link.pdf").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: f.file)
    let id = try f.id(forContent: "TWO")
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "link.pdf", "version": id], approved: true)
    expect(result.ok, "symlink: restored")
    expectEq(try read(f.file), "TWO", "symlink: the real file has the bytes")
    expectEq(try FileManager.default.destinationOfSymbolicLink(atPath: link), f.file, "symlink: still a link to it")
}

@Test func restoreIsFailClosedWhenThePreRestoreCopyCannotBeMade() async throws {
    // Root ignores directory modes, so the copy would succeed.
    guard getuid() != 0 else { return }
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let folder = try #require(f.versions.versions(of: f.file).first).url.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!result.ok && result.output.contains("nothing was restored"), "fail-closed: refused and says why")
    expect(result.output.contains("copy"), "fail-closed: the reason is the missing copy")
    expectEq(try read(f.file), "NOW", "fail-closed: the file is untouched")
}

@Test func restoreIsFailClosedWhenTheCurrentFileIsTooLargeToCopy() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    try write("0123456789ABCDEF", to: f.file)
    let result = try await runner(f.dir, versions: store(f.root, bytes: 10))
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!result.ok && result.output.contains("nothing was restored") && result.output.contains("too large"),
           "too large: refused and says why, got «\(result.output)»")
    expectEq(try read(f.file), "0123456789ABCDEF", "too large: the file is untouched")
}

@Test func aForgedOrUnknownVersionIdIsRefused() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let runner = runner(f.dir, versions: f.versions)
    let real = try f.id(forContent: "ONE")
    let forged = ["", "deadbeef", "../../etc/passwd", "../\(real)", "\(real)-q3.pdf", String(real.prefix(4)),
                  f.versions.versions(of: f.file)[0].url.path]
    for id in forged {
        let result = try await runner.execute(
            tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
        expect(!result.ok, "forged: «\(id)» is refused")
        expectEq(try read(f.file), "NOW", "forged: the file is untouched for «\(id)»")
    }
    expectEq(f.versions.versions(of: f.file).count, 2, "forged: no copy was made either")
    let missing = try await runner.execute(tool: "restore_file_version", arguments: ["path": "q3.pdf"], approved: true)
    expect(!missing.ok, "missing: no version argument is refused")
}

@Test func aVersionOfAnotherFileIsRefused() async throws {
    let a = try Fixture.make(name: "a.pdf")
    defer { remove(a.dir) }
    let b = dir(a.dir, "b.pdf")
    try write("B-NOW", to: b)
    _ = a.versions.snapshot(b, trigger: .preSave)
    try write("B-NOW", to: b)
    let foreign = try a.id(forContent: "ONE")
    let result = try await runner(a.dir, versions: a.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "b.pdf", "version": foreign], approved: true)
    expect(!result.ok, "foreign: another file's id is refused")
    expectEq(try read(b), "B-NOW", "foreign: the file is untouched")
    expectEq(try read(a.file), "NOW", "foreign: the other file is untouched too")
}

private func dir(_ base: URL, _ name: String) -> String { base.appendingPathComponent(name).path }

@Test func restoreRefusesWhatThePathPolicyRefuses() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let runner = runner(f.dir, versions: f.versions)

    let outside = try scratch()
    defer { remove(outside) }
    let elsewhere = dir(outside, "q3.pdf")
    try write("OUT", to: elsewhere)
    var result = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": elsewhere, "version": id], approved: true)
    expect(!result.ok, "policy: outside the working folder")
    expectEq(try read(elsewhere), "OUT", "policy: outside file untouched")

    let hidden = dir(f.dir, ".private/q3.pdf")
    try write("HIDDEN", to: hidden)
    _ = f.versions.snapshot(hidden, trigger: .preSave)
    let hiddenId = String(try #require(f.versions.versions(of: hidden).first).url.lastPathComponent
        .split(separator: "-", maxSplits: 3)[2])
    result = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": ".private/q3.pdf", "version": hiddenId], approved: true)
    expect(!result.ok && result.output.contains("hidden"), "policy: hidden entries are refused")
    expectEq(try read(hidden), "HIDDEN", "policy: the hidden file is untouched")

    result = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "q3\u{202E}.pdf", "version": id], approved: true)
    expect(!result.ok, "policy: invisible or control characters in the path")
}

@Test func restoreRefusesAMissingFileAndAFolder() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    try FileManager.default.removeItem(atPath: f.file)
    let runner = runner(f.dir, versions: f.versions)
    let gone = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!gone.ok && gone.output.contains("does not exist"), "missing: refused, nothing is recreated")
    expect(!FileManager.default.fileExists(atPath: f.file), "missing: still missing")
    try FileManager.default.createDirectory(atPath: f.file, withIntermediateDirectories: true)
    let folder = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!folder.ok, "folder: only a regular file can be restored")
}

@Test func theHistoryToolsNeedTheStore() async throws {
    let dir = try scratch()
    defer { remove(dir) }
    let bare = runner(dir, versions: nil)
    let names = Set(bare.availableTools.map(\.rawValue))
    expect(!names.contains("list_file_history") && !names.contains("restore_file_version"), "no store, not offered")
    let withStore = runner(dir, versions: store(dir.appendingPathComponent("store")))
    let offered = Set(withStore.availableTools.map(\.rawValue))
    expect(offered.contains("list_file_history") && offered.contains("restore_file_version"), "store, offered")
}

// MARK: - The parent's lane

@MainActor private func parent(_ dir: URL, versions: FileVersions) -> ParentToolRunner {
    ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []),
                     workdir: dir.path, versions: versions)
}

@Test @MainActor func theParentListsWithoutTheSheetAndRestoresOnlyWithItsTicket() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let r = parent(f.dir, versions: f.versions)
    expect(r.handles("list_file_history") && r.handles("restore_file_version"), "parent: both offered with a store")
    let args = #"{"path":"q3.pdf","version":"\#(id)"}"#

    let listCall = ToolCallRef(id: "1", name: "list_file_history", arguments: #"{"path":"q3.pdf"}"#)
    expect(r.approval(for: listCall, said: "") == nil, "parent: listing never asks")
    let listed = await r.execute(name: "list_file_history", argumentsJSON: #"{"path":"q3.pdf"}"#)
    expect(listed.ok && listed.output.contains(id), "parent: lists the versions")

    let skipped = await r.execute(name: "restore_file_version", argumentsJSON: args)
    expect(!skipped.ok, "parent: no ticket, no restore")
    expectEq(try read(f.file), "NOW", "parent: untouched without the sheet")

    let call = ToolCallRef(id: "2", name: "restore_file_version", arguments: args)
    guard let request = r.approval(for: call, said: "restaura la primera versión") else {
        return expect(false, "parent: a restore asks, even when the user said it")
    }
    expectEq(request.toolName, "restore_file_version", "parent: the sheet carries the tool name")
    let pending = await r.execute(name: "restore_file_version", argumentsJSON: args)
    expect(!pending.ok, "parent: asked but not granted, nothing is written")
    guard let again = r.approval(for: call, said: "") else { return expect(false, "parent: sheet again") }
    r.granted(again)
    let done = await r.execute(name: "restore_file_version", argumentsJSON: args)
    expect(done.ok, "parent: with the yes, restores")
    expectEq(try read(f.file), "ONE", "parent: the bytes are back")
    try write("EDITED AFTER", to: f.file)
    let replay = await r.execute(name: "restore_file_version", argumentsJSON: args)
    expect(!replay.ok, "parent: the ticket is spent once")
    expectEq(try read(f.file), "EDITED AFTER", "parent: a replay does not overwrite again")
}

@Test @MainActor func theParentOffersTheHistoryToolsOnlyWithAStore() {
    let bare = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: [], running: []))
    expect(!bare.handles("list_file_history") && !bare.handles("restore_file_version"), "parent: no store, no tools")
    let names = Set(bare.specs(.en).map(\.name))
    expect(!names.contains("list_file_history") && !names.contains("restore_file_version"), "parent: not advertised")
}

// MARK: - Review round

@Test func restoringTheOldestVersionSurvivesTheCapThatEvictsIt() async throws {
    let f = try Fixture.make(maxVersions: 2)
    defer { remove(f.dir) }
    let oldest = try f.id(forContent: "ONE")
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": oldest], approved: true)
    expect(result.ok, "oldest: restored even though the pre-restore copy pushes it out, got «\(result.output)»")
    expectEq(try read(f.file), "ONE", "oldest: the file holds the old bytes")
}

@Test func aVersionThatIsNoLongerThereIsRefusedAndTheFileIsKept() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let url = try #require(f.versions.versions(of: f.file).first { (try? read($0.url.path)) == "ONE" }).url
    // Same name, no longer a file: it is listed but cannot be read back.
    try FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    let swapped = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!swapped.ok && swapped.output.contains("no longer available"), "swapped: says so, got «\(swapped.output)»")
    try FileManager.default.removeItem(at: url)
    let gone = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expect(!gone.ok, "deleted: refused")
    expectEq(try read(f.file), "NOW", "deleted: the file is untouched")
}

@Test func theSuccessNamesTheCopyThatUndoesIt() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let runner = runner(f.dir, versions: f.versions)
    let done = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    let listed = try await runner.execute(tool: "list_file_history", arguments: ["path": "q3.pdf"], approved: false)
    let undo = try #require(ids(in: listed.output).first)
    expect(done.output.contains("to undo, restore version \(undo)"), "undo: names the new copy, got «\(done.output)»")
    let back = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": undo], approved: true)
    expect(back.ok, "undo: the named id works")
    expectEq(try read(f.file), "NOW", "undo: the file is as it was before the restore")
}

@Test func theIdIsTheThirdSegmentOfAStoredName() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let file = dir.appendingPathComponent("a.pdf").path
    try write("x", to: file)
    let versions = store(dir.appendingPathComponent("store"))
    guard case .saved(let url) = versions.snapshot(file, trigger: .preSave) else {
        return expect(false, "snapshot: saved")
    }
    let third = String(url.lastPathComponent.split(separator: "-", maxSplits: 3)[2])
    let listed = runner(dir, versions: versions).listFileHistory(arguments: ["path": "a.pdf"])
    expectEq(ids(in: listed.output), [third], "id: the list shows the third segment of the stored name")
}

@Test func overwritingNeverFollowsALinkSwappedInAfterTheChecks() throws {
    let dir = try scratch()
    defer { remove(dir) }
    let target = dir.appendingPathComponent("target.txt").path
    try write("PRECIOUS", to: target)
    let link = dir.appendingPathComponent("link.txt").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    var refused = false
    do { try NativeToolRunner.overwriteInPlace(link, with: Data("EVIL".utf8)) } catch { refused = true }
    expect(refused, "swap: a link at the path is refused")
    expectEq(try read(target), "PRECIOUS", "swap: what the link points at is untouched")
    let plain = dir.appendingPathComponent("plain.txt").path
    try write("LONGER OLD CONTENT", to: plain)
    try NativeToolRunner.overwriteInPlace(plain, with: Data("new".utf8))
    expectEq(try read(plain), "new", "overwrite: truncated, then written")
    let folder = dir.appendingPathComponent("folder").path
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    var folderRefused = false
    do { try NativeToolRunner.overwriteInPlace(folder, with: Data("x".utf8)) } catch { folderRefused = true }
    expect(folderRefused, "overwrite: not a regular file")
}

@Test func aLinkInsideTheFolderPointingOutsideIsRefusedByBothTools() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let outside = try scratch()
    defer { remove(outside) }
    let secret = dir(outside, "secret.pdf")
    try write("OLD SECRET", to: secret)
    // Its own history exists, so only the path barrier can be what refuses.
    _ = f.versions.snapshot(secret, trigger: .preSave)
    try write("SECRET", to: secret)
    try FileManager.default.createSymbolicLink(
        atPath: dir(f.dir, "escape.pdf"), withDestinationPath: secret)
    let kept = try #require(f.versions.versions(of: secret).first)
    let id = String(kept.url.lastPathComponent.split(separator: "-", maxSplits: 3)[2])
    let runner = runner(f.dir, versions: f.versions)
    let listed = try await runner.execute(tool: "list_file_history", arguments: ["path": "escape.pdf"], approved: false)
    expect(!listed.ok, "escape: list refuses")
    let restored = try await runner.execute(
        tool: "restore_file_version", arguments: ["path": "escape.pdf", "version": id], approved: true)
    expect(!restored.ok && restored.output.contains("outside working directory"),
           "escape: the path barrier refuses, got «\(restored.output)»")
    expect(!restored.output.contains("Unknown version"), "escape: not an unknown-version refusal")
    expectEq(try read(secret), "SECRET", "escape: the outside file is untouched")
}

@Test func aFailedWriteIsPutBackFromTheCopyAndSaysSo() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let file = f.file
    let result = runner(f.dir, versions: f.versions).restoreFileVersion(
        arguments: ["path": "q3.pdf", "version": id],
        write: { path, _ in
            // What a write that dies halfway leaves behind.
            try Data("PA".utf8).write(to: URL(fileURLWithPath: path))
            throw CocoaError(.fileWriteUnknown)
        })
    expectEq(result.output, "The restore failed while writing; the file was put back and is intact",
             "failed write: says it was put back")
    expect(!result.ok, "failed write: refused")
    expectEq(try read(file), "NOW", "failed write: rewritten from the pre-restore copy")
}

@Test func aFailedWriteOnAReadOnlyFileLeavesItUntouchedAndSaysSo() async throws {
    guard getuid() != 0 else { return }
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: f.file)
    let result = try await runner(f.dir, versions: f.versions)
        .execute(tool: "restore_file_version", arguments: ["path": "q3.pdf", "version": id], approved: true)
    expectEq(result.output, "The restore failed while writing; the file is intact",
             "read-only: untouched and intact, not 'put back'")
    expect(!result.ok, "read-only: refused")
    expectEq(try read(f.file), "NOW", "read-only: untouched")
}

// MARK: - Ticket bound to the version

@Test @MainActor func aTicketCoversOnlyThePathAndVersionTheSheetShowed() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    try write("OTHER", to: dir(f.dir, "other.pdf"))
    let one = try f.id(forContent: "ONE")
    let two = try f.id(forContent: "TWO")
    let r = parent(f.dir, versions: f.versions)
    let args = #"{"path":"q3.pdf","version":"\#(one)"}"#
    guard let request = r.approval(
        for: ToolCallRef(id: "1", name: "restore_file_version", arguments: args), said: "") else {
        return expect(false, "ticket: the restore asks")
    }
    r.granted(request)
    let otherVersion = await r.execute(
        name: "restore_file_version", argumentsJSON: #"{"path":"q3.pdf","version":"\#(two)"}"#)
    expect(!otherVersion.ok, "ticket: another version is refused")
    expectEq(try read(f.file), "NOW", "ticket: file unchanged after the other version")
    let otherPath = await r.execute(
        name: "restore_file_version", argumentsJSON: #"{"path":"other.pdf","version":"\#(one)"}"#)
    expect(!otherPath.ok, "ticket: another path is refused")
    expectEq(try read(dir(f.dir, "other.pdf")), "OTHER", "ticket: the other file is untouched")
    expectEq(try read(f.file), "NOW", "ticket: file unchanged after the other path")
    let exact = await r.execute(name: "restore_file_version", argumentsJSON: args)
    expect(exact.ok, "ticket: the exact call still works after refusals, got «\(exact.output)»")
    expectEq(try read(f.file), "ONE", "ticket: and restores")
}

// MARK: - The sheet says which version

@Test @MainActor func theSheetNamesTheVersionTheRunnerResolvedAndTheRealFile() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    try FileManager.default.createSymbolicLink(atPath: dir(f.dir, "link.pdf"), withDestinationPath: f.file)
    let id = try f.id(forContent: "ONE")
    let r = parent(f.dir, versions: f.versions)
    // A model that writes the resolved keys itself must not get them onto the sheet.
    let args = #"{"path":"link.pdf","version":"\#(id)","restore_when":"FORGED","restore_real":"/etc/passwd"}"#
    let request = try #require(r.approval(
        for: ToolCallRef(id: "1", name: "restore_file_version", arguments: args), said: ""))
    expect(!request.inputJSON.contains("FORGED") && !request.inputJSON.contains("passwd"), "sheet: forged keys dropped")
    let shown = ApprovalCopy.display(for: request, language: .en)
    expectEq(shown.subject, "q3.pdf", "sheet: the real file name, not the link's")
    expect((shown.preview ?? "").contains(f.file), "sheet: the real path is shown")
    expect((shown.trail ?? "").contains("pre-save"), "sheet: the trigger of the chosen version, got «\(shown.trail ?? "")»")
    expect((shown.trail ?? "").contains("20"), "sheet: its time")
    let es = ApprovalCopy.display(for: request, language: .es)
    expect((es.trail ?? "").contains("pre-save") || (es.trail ?? "").contains("antes de guardar"), "sheet es: the trigger")
    let unknown = try #require(r.approval(
        for: ToolCallRef(id: "2", name: "restore_file_version", arguments: #"{"path":"q3.pdf","version":"zzzzzzzz"}"#),
        said: ""))
    expect(!unknown.inputJSON.contains("restore_when"), "sheet: nothing resolved, nothing claimed")
}

@Test func aVersionThatCannotBeReadAfterItResolvedChangesNothing() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let before = f.versions.versions(of: f.file).count
    let result = runner(f.dir, versions: f.versions).restoreFileVersion(
        arguments: ["path": "q3.pdf", "version": id],
        read: { _ in throw CocoaError(.fileReadNoSuchFile) })
    expect(!result.ok && result.output.contains("no longer available"), "read: says so, got «\(result.output)»")
    expectEq(try read(f.file), "NOW", "read: the file is untouched")
    expectEq(f.versions.versions(of: f.file).count, before, "read: no copy was made before the read")
}

// MARK: - One binder for the sheet, on both lanes

@Test @MainActor func theSheetJSONCarriesTheRunnersValuesNeverTheModels() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let forged = #"{"path":"q3.pdf","version":"\#(id)","restore_when":"FORGED","restore_real":"/etc/passwd"}"#
    let shown = await runner(f.dir, versions: f.versions).approvalArguments(tool: "restore_file_version", json: forged)
    let object = try #require(ToolArguments.parse(shown))
    expect(!shown.contains("FORGED") && !shown.contains("passwd"), "bind: forged values gone")
    expect((object["restore_when"] as? String)?.contains("pre-save") == true, "bind: the runner's time and trigger")
    expectEq(object["restore_real"] as? String, f.file, "bind: the runner's real path")
    let unknown = await runner(f.dir, versions: f.versions).approvalArguments(
        tool: "restore_file_version",
        json: #"{"path":"q3.pdf","version":"zzzzzzzz","restore_when":"FORGED"}"#)
    expect(!unknown.contains("FORGED") && !unknown.contains("restore_when"), "bind: unresolved claims nothing")
}

@Test func restoreIgnoresTheSheetKeysTheModelSends() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let other = dir(f.dir, "other.pdf")
    try write("OTHER", to: other)
    let id = try f.id(forContent: "ONE")
    let result = try await runner(f.dir, versions: f.versions).execute(
        tool: "restore_file_version",
        arguments: ["path": "q3.pdf", "version": id, "restore_real": other, "restore_when": "yesterday"],
        approved: true)
    expect(result.ok, "ignore: restored")
    expectEq(try read(f.file), "ONE", "ignore: the named path got the named version")
    expectEq(try read(other), "OTHER", "ignore: the forged real path was not written")
}

private actor CapturingApprovals: ApprovalsProvider {
    private(set) var seen: [ApprovalRequest] = []
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        seen.append(approval)
        return ApprovalResponse(requestId: approval.requestId, approved: false)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { false }
}

@Test @MainActor func theSpecialistLaneShowsTheRunnersValuesOnTheSheet() async throws {
    let f = try Fixture.make()
    defer { remove(f.dir) }
    let id = try f.id(forContent: "ONE")
    let args = #"{"path":"q3.pdf","version":"\#(id)","restore_when":"FORGED","restore_real":"/etc/passwd"}"#
    let provider = RoundsProvider(rounds: [
        [.toolCalls([ToolCallRef(id: "a", name: "restore_file_version", arguments: args)])],
        [.text("ok")],
    ])
    let approvals = CapturingApprovals()
    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native, chatProvider: provider,
        config: Config(workdir: f.dir.path), approvals: approvals, versions: f.versions)
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    stream.ignore()
    _ = try? await executor.run(JobRequest(id: "j", goal: "x", context: ""), events: sink)
    sink.finish()
    let seen = await approvals.seen
    let sheet = try #require(seen.first { $0.toolName == "restore_file_version" })
    expect(!sheet.inputJSON.contains("FORGED") && !sheet.inputJSON.contains("passwd"), "executor: forged keys never reach the sheet")
    expect(sheet.inputJSON.contains("restore_when"), "executor: the runner's own resolution does")
    expectEq(try read(f.file), "NOW", "executor: denied, so nothing was written")
}
