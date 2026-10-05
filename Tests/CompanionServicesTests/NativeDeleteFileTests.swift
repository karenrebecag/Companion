import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// delete_file after approval: the file goes to the Trash; on ANY Trash error
// it goes for good, and the model is told which happened. The disposal is
// faked: these tests must never fill the real Trash. Results for the model
// are English whatever the user's language (house convention; only the
// denial instruction is localized, by Escalation).

struct DeleteDisposed: Sendable, Equatable {
    var trashed: [String] = []
    var removed: [String] = []
}

final class DeleteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = DeleteDisposed()
    var calls: DeleteDisposed { lock.lock(); defer { lock.unlock() }; return value }
    func trashed(_ url: URL) { lock.lock(); value.trashed.append(url.path); lock.unlock() }
    func removed(_ url: URL) { lock.lock(); value.removed.append(url.path); lock.unlock() }
    var disposal: FileDisposal {
        FileDisposal(trash: { self.trashed($0) }, remove: { self.removed($0) })
    }
}

struct DeleteBoom: Error {}

struct DeleteSandbox {
    let base: String
    let work: String
    let outside: String
    let home: String

    init() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-delete-\(UUID().uuidString)")
        base = url.path
        work = url.appendingPathComponent("work").path
        outside = url.appendingPathComponent("outside").path
        home = url.appendingPathComponent("home").path
        for dir in [work, outside, home] {
            try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    func folder(_ path: String) -> String {
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    func file(_ name: String, in folder: String? = nil, _ text: String = "x") -> String {
        let path = ((folder ?? work) as NSString).appendingPathComponent(name)
        try! FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func clean() {
        // A test may leave a read-only folder behind.
        if let walker = FileManager.default.enumerator(atPath: base) {
            for case let entry as String in walker {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: (base as NSString).appendingPathComponent(entry))
            }
        }
        try? FileManager.default.removeItem(atPath: base)
    }
}

func resolvedPath(_ path: String) -> String { (path as NSString).resolvingSymlinksInPath }

@MainActor func makeDeleteRunner(
    _ sandbox: DeleteSandbox, workdir: String? = nil, skills: SkillsLocation? = nil,
    language: AppLanguage = .en, disposal: FileDisposal
) -> NativeToolRunner {
    NativeToolRunner(
        workdir: workdir ?? sandbox.work, language: language, skills: skills,
        home: URL(fileURLWithPath: sandbox.home), disposal: disposal)
}

@MainActor func runDelete(
    _ sandbox: DeleteSandbox, path: (any Sendable)?, approved: Bool = true, language: AppLanguage = .en,
    workdir: String? = nil, skills: SkillsLocation? = nil,
    trash: @escaping @Sendable (URL) throws -> Void = { _ in },
    remove: @escaping @Sendable (URL) throws -> Void = { _ in }
) -> (ToolResult, DeleteDisposed) {
    let recorder = DeleteRecorder()
    let runner = makeDeleteRunner(
        sandbox, workdir: workdir, skills: skills, language: language,
        disposal: FileDisposal(
            trash: { url in try trash(url); recorder.trashed(url) },
            remove: { url in try remove(url); recorder.removed(url) }))
    let result = try! runAsync {
        let arguments: [String: Any] = path.map { ["path": $0] } ?? [:]
        return try await runner.execute(tool: "delete_file", arguments: arguments, approved: approved)
    }
    return (result, recorder.calls)
}

/// A refusal: not ok, the model-facing reason, nothing disposed, still there.
@MainActor func expectDeleteRefused(
    _ sandbox: DeleteSandbox, _ path: String, reason: String, still: [String],
    workdir: String? = nil, skills: SkillsLocation? = nil, _ label: String
) {
    let (result, calls) = runDelete(sandbox, path: path, workdir: workdir, skills: skills)
    expectEq(result.ok, false, "\(label): not ok")
    expect(result.output.contains(reason), "\(label): the model reads «\(reason)», got «\(result.output)»")
    expectEq(calls, DeleteDisposed(), "\(label): nothing disposed")
    for item in still { expect(sandbox.exists(item), "\(label): \(item) is still there") }
}

@Test @MainActor func deleteFileIsOfferedToTheModel() {
    let runner = NativeToolRunner(workdir: "/tmp")
    expect(runner.availableTools.contains(.deleteFile), "registration: delete_file is advertised")
}

@Test @MainActor func deniedDeleteTouchesNothing() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("keep.md")
    let (result, calls) = runDelete(sandbox, path: file, approved: false, language: .es)
    expectEq(result.ok, false, "denied: not ok")
    expectEq(result.output, Escalation.deniedByUser(.es), "denied: the instruction, in the user's language")
    expectEq(calls, DeleteDisposed(), "denied: neither trash nor remove was called")
    expect(sandbox.exists(file), "denied: the file is still there")
}

@Test @MainActor func trashSuccessSaysItWentToTheTrash() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let (result, calls) = runDelete(sandbox, path: file, language: .es)
    expectEq(result.ok, true, "trash: ok")
    expect(result.output.contains("Trash") && !result.output.contains("permanent"),
           "trash: told it went to the Trash, in English even for a Spanish user")
    expectEq(calls.trashed, [resolvedPath(file)], "trash: the resolved path went to the Trash")
    expectEq(calls.removed, [], "trash: no permanent delete")
}

@Test @MainActor func trashFailureFallsBackToPermanentDeleteAndSaysSo() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let (result, calls) = runDelete(sandbox, path: file, language: .es, trash: { _ in throw DeleteBoom() })
    expectEq(result.ok, true, "fallback: ok, the file is gone")
    expect(result.output.contains("permanently") && result.output.contains("cannot be put back"),
           "fallback: told it was permanent, in English for a Spanish user")
    expectEq(calls.trashed, [], "fallback: the trash call failed before recording")
    expectEq(calls.removed, [resolvedPath(file)], "fallback: removed the same path")
}

@Test @MainActor func realPermanentFallbackRemovesTheFile() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let runner = makeDeleteRunner(sandbox, disposal: FileDisposal(
        trash: { _ in throw DeleteBoom() }, remove: { try FileManager.default.removeItem(at: $0) }))
    let result = try! runAsync {
        try await runner.execute(tool: "delete_file", arguments: ["path": file], approved: true)
    }
    expectEq(result.ok, true, "real fallback: ok")
    expect(!sandbox.exists(file), "real fallback: the file is gone")
}

@Test @MainActor func bothFailingOnAFileIsAnErrorAndNotPartial() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe.md")
    let (result, calls) = runDelete(sandbox, path: file, trash: { _ in throw DeleteBoom() }, remove: { _ in throw DeleteBoom() })
    expectEq(result.ok, false, "both fail: not ok")
    expect(result.output.contains("Could not delete"), "both fail: the model reads the failure")
    expect(!result.output.contains("partial"), "both fail on a file: nothing partial to say")
    expectEq(calls, DeleteDisposed(), "both fail: nothing recorded as done")
    expect(sandbox.exists(file), "both fail: the file is untouched")
}

@Test @MainActor func aFolderThatFailsPartwayIsReportedAsPossiblyPartial() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let folder = sandbox.folder((sandbox.work as NSString).appendingPathComponent("proyecto"))
    let sealed = sandbox.folder((folder as NSString).appendingPathComponent("sellada"))
    _ = sandbox.file("a.md", in: folder)
    _ = sandbox.file("b.md", in: sealed)
    try! FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sealed)
    let runner = makeDeleteRunner(sandbox, disposal: FileDisposal(
        trash: { _ in throw DeleteBoom() }, remove: { try FileManager.default.removeItem(at: $0) }))
    let result = try! runAsync {
        try await runner.execute(tool: "delete_file", arguments: ["path": folder], approved: true)
    }
    expectEq(result.ok, false, "partial: not ok")
    expect(result.output.contains("partial"), "partial: says it may be partial, got «\(result.output)»")
    expect(!result.output.contains("nothing"), "partial: never claims nothing happened")
}

@Test @MainActor func aFolderRemovedByTheFallbackLeavesWhatItsLinksPointAtIntact() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let outsideFile = sandbox.file("precious.md", in: sandbox.outside)
    let folder = sandbox.folder((sandbox.work as NSString).appendingPathComponent("carpeta"))
    try! FileManager.default.createSymbolicLink(
        atPath: (folder as NSString).appendingPathComponent("link.md"), withDestinationPath: outsideFile)
    let runner = makeDeleteRunner(sandbox, disposal: FileDisposal(
        trash: { _ in throw DeleteBoom() }, remove: { try FileManager.default.removeItem(at: $0) }))
    let result = try! runAsync {
        try await runner.execute(tool: "delete_file", arguments: ["path": folder], approved: true)
    }
    expectEq(result.ok, true, "inner link: ok")
    expect(!sandbox.exists(folder), "inner link: the folder is gone")
    expect(sandbox.exists(outsideFile), "inner link: the file it pointed at is intact")
}

@Test @MainActor func relativePathResolvesAgainstTheWorkdir() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("nota.md")
    let (result, calls) = runDelete(sandbox, path: "nota.md")
    expectEq(result.ok, true, "relative: ok")
    expectEq(calls.trashed, [resolvedPath(file)], "relative: resolved against the workdir")
}

@Test @MainActor func unicodeAndSpacesInTheNameAreHandled() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("informe final \u{1F4C4} ni\u{00F1}o.md")
    let (result, calls) = runDelete(sandbox, path: file)
    expectEq(result.ok, true, "unicode: ok")
    expectEq(calls.trashed, [resolvedPath(file)], "unicode: exact path")
}

@Test @MainActor func aFolderIsTrashedWhole() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let folder = sandbox.folder((sandbox.work as NSString).appendingPathComponent("carpeta"))
    _ = sandbox.file("dentro.md", in: folder)
    let (result, calls) = runDelete(sandbox, path: folder)
    expectEq(result.ok, true, "folder: ok")
    expectEq(calls.trashed, [resolvedPath(folder)], "folder: the folder itself")
}

@Test @MainActor func pathsOutsideTheScopeAreRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let outsideFile = sandbox.file("secret.md", in: sandbox.outside)
    for path in [outsideFile, "../outside/secret.md", "\(sandbox.work)/../outside/secret.md", "/etc/hosts"] {
        expectDeleteRefused(sandbox, path, reason: "outside working directory", still: [outsideFile, "/etc/hosts"],
                      "scope \(path)")
    }
}

@Test @MainActor func anySymlinkInThePathIsRefusedAndTargetsSurvive() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let target = sandbox.file("secret.md", in: sandbox.outside)
    let link = (sandbox.work as NSString).appendingPathComponent("link.md")
    try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
    expectDeleteRefused(sandbox, link, reason: "outside working directory", still: [target, link], "link out")

    let dirLink = (sandbox.work as NSString).appendingPathComponent("dirlink")
    try! FileManager.default.createSymbolicLink(atPath: dirLink, withDestinationPath: sandbox.outside)
    expectDeleteRefused(sandbox, "dirlink/secret.md", reason: "outside working directory", still: [target], "parent link out")

    let real = sandbox.file("real.md")
    let alias = (sandbox.work as NSString).appendingPathComponent("alias.md")
    try! FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: real)
    expectDeleteRefused(sandbox, alias, reason: "symbolic link", still: [real, alias], "link in scope")
}

@Test @MainActor func aSymlinkedParentPointingInsideTheRootsIsRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let realFolder = sandbox.folder((sandbox.work as NSString).appendingPathComponent("real"))
    let inner = sandbox.file("paper.md", in: realFolder)
    let sheetPath = (sandbox.work as NSString).appendingPathComponent("shortcut")
    try! FileManager.default.createSymbolicLink(atPath: sheetPath, withDestinationPath: realFolder)
    expectDeleteRefused(sandbox, "shortcut/paper.md", reason: "symbolic link", still: [inner],
                  "intermediate link: the sheet would show shortcut/paper.md, real/paper.md would go")
    expectDeleteRefused(sandbox, "\(sandbox.work)/shortcut/paper.md", reason: "symbolic link", still: [inner],
                  "intermediate link, absolute")
}

@Test @MainActor func missingEmptyAndWrongTypedPathsAreRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    expectDeleteRefused(sandbox, "no-existe.md", reason: "Nothing at that path", still: [sandbox.work], "missing")
    for bad: (any Sendable)? in [nil, "", 42, ["a"]] {
        let (result, calls) = runDelete(sandbox, path: bad)
        expectEq(result.ok, false, "bad argument \(String(describing: bad)): refused")
        expectEq(result.output, "Missing path argument", "bad argument: says what is missing")
        expectEq(calls, DeleteDisposed(), "bad argument: nothing disposed")
    }
}

@Test @MainActor func controlAndInvisibleCharactersInThePathAreRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("a\u{200B}b.md")
    for path in ["a\nb.md", "a\u{202E}b.md", file] {
        expectDeleteRefused(sandbox, path, reason: "invisible", still: [file], "hidden scalars in «\(path.debugDescription)»")
    }
}

@Test @MainActor func theWorkdirAndTheFilesystemRootAreNeverDeleted() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    for path in [sandbox.work, sandbox.work + "/", ".", "/"] {
        let (result, calls) = runDelete(sandbox, path: path)
        expectEq(result.ok, false, "protected: refused \(path)")
        expectEq(calls, DeleteDisposed(), "protected: nothing disposed for \(path)")
    }
    expect(sandbox.exists(sandbox.work), "protected: the workdir stands")
}

@Test @MainActor func somethingThatIsNeitherFileNorFolderIsRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let fifo = (sandbox.work as NSString).appendingPathComponent("pipe")
    expectEq(mkfifo(fifo, 0o600), 0, "setup: fifo")
    expectDeleteRefused(sandbox, fifo, reason: "Only files and folders", still: [fifo], "fifo")
}

@Test @MainActor func aReadOnlyRootIsRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let location = SkillsLocation(root: URL(fileURLWithPath: sandbox.base).appendingPathComponent("Companion"))
    let skill = sandbox.folder(location.systemSkills.appendingPathComponent("writing-content").path)
    let file = sandbox.file("SKILL.md", in: skill)
    expectDeleteRefused(sandbox, file, reason: "read-only", still: [file], skills: location, "read-only root")
}

// MARK: - Denylist (M3)

@Test @MainActor func homeFoldersLibraryAndDotEntriesAreRefused() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let documents = sandbox.folder((sandbox.home as NSString).appendingPathComponent("Documents"))
    let ssh = sandbox.folder((sandbox.home as NSString).appendingPathComponent(".ssh"))
    let dotfile = sandbox.file(".zshrc", in: sandbox.home)
    let prefs = sandbox.file("Prefs/app.plist", in: (sandbox.home as NSString).appendingPathComponent("Library"))
    let library = (sandbox.home as NSString).appendingPathComponent("Library")
    for (path, label) in [(documents, "~/Documents whole"), (ssh, "~/.ssh"), (dotfile, "~/.zshrc"),
                          (prefs, "under ~/Library"), (library, "~/Library itself"),
                          ((sandbox.home as NSString).appendingPathComponent("DOCUMENTS"), "case variant")] {
        let (result, calls) = runDelete(sandbox, path: path, workdir: sandbox.home)
        expectEq(result.ok, false, "denylist \(label): refused")
        expectEq(calls, DeleteDisposed(), "denylist \(label): nothing disposed")
        if label != "case variant" {
            expect(result.output.contains("protected"), "denylist \(label): the model reads why, got «\(result.output)»")
        }
    }
    for item in [documents, ssh, dotfile, prefs] { expect(sandbox.exists(item), "denylist: \(item) stands") }
}

@Test @MainActor func aFileInANormalProjectFolderUnderHomeIsAllowed() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let file = sandbox.file("main.md", in: (sandbox.home as NSString).appendingPathComponent("Projects/app"))
    let (result, calls) = runDelete(sandbox, path: file, workdir: sandbox.home)
    expectEq(result.ok, true, "allowed: a file in a project folder")
    expectEq(calls.trashed, [resolvedPath(file)], "allowed: goes to the Trash")
}

@Test @MainActor func theAppsOwnDataIsRefusedUnderEveryRoot() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let location = SkillsLocation(
        root: URL(fileURLWithPath: sandbox.home).appendingPathComponent("Projects/Companion"))
    let paths = [
        sandbox.file("note.md", in: sandbox.folder(location.memory.path)),
        sandbox.file("KNOWLEDGE.md", in: sandbox.folder(location.knowledge.appendingPathComponent("tema").path)),
        sandbox.file("SKILL.md", in: sandbox.folder(location.customSkills.appendingPathComponent("mia").path)),
        location.memory.path, location.knowledge.path, location.customSkills.path,
        location.root.path,
        (location.root.path as NSString).deletingLastPathComponent,
        ((location.root.path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent,
    ]
    for path in paths where path != sandbox.home {
        expectDeleteRefused(sandbox, path, reason: "protected", still: [path], workdir: sandbox.home, skills: location,
                      "app data \(path)")
    }
}

@Test @MainActor func aFolderContainingAnyRootIsRefusedAbsoluteOrTwoLevelsUp() {
    let sandbox = DeleteSandbox(); defer { sandbox.clean() }
    let inside = sandbox.folder((sandbox.work as NSString).appendingPathComponent("a/b"))
    let location = SkillsLocation(root: URL(fileURLWithPath: inside).appendingPathComponent("Companion"))
    for root in [location.systemSkills, location.customSkills, location.knowledge, location.memory] {
        _ = sandbox.folder(root.path)
    }
    let roots = [location.systemSkills.path, location.customSkills.path, location.knowledge.path, location.memory.path]
    for root in roots {
        var twoUp = root as NSString
        for _ in 0..<2 { twoUp = twoUp.deletingLastPathComponent as NSString }
        for path in [root, twoUp as String, (root as NSString).deletingLastPathComponent] {
            expectDeleteRefused(sandbox, path, reason: "protected", still: [root],
                                skills: location, "root \(root) via \(path)")
        }
    }
    expectDeleteRefused(sandbox, "a", reason: "protected", still: [inside], skills: location, "ancestor of the app roots, relative")
}
