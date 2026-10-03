import CompanionCore
import Foundation

// Wave 20d B. The band of one call, from what this runner can see: the disk
// and the open workbook. Both lanes (the specialist's and the parent's) ask
// here, so "does it need the sheet" has one answer.

extension NativeToolRunner {
    // HACK: two parallel calls to one new path both read "free" and both act;
    // the second replaces the first with no backup. Upgrade trigger: exclusive
    // create (O_EXCL) in write_file, or serialising a round's writes.
    func actionBand(tool: String, arguments: [String: Any]) async -> ActionBand {
        if tool == NativeTool.sheetWrite.rawValue {
            let facts = ActionFacts(rangeHasValues: await rangeHasValues(arguments))
            return ActionBand.classify(toolName: tool, arguments: arguments, facts: facts)
        }
        if tool == NativeTool.runShell.rawValue, let command = arguments["command"] as? String,
           CommandClassifier.isGit(command) {
            let facts = ActionFacts(gitConfigInert: await gitConfigInert())
            return ActionBand.classify(toolName: tool, arguments: arguments, facts: facts)
        }
        return fileBand(tool: tool, arguments: arguments)
    }

    /// Repo-scoped keys git only stores. Anything else in the repo's own
    /// config (core.fsmonitor, filter.*, diff.*, pager.*, include*) may name
    /// a program a "read" runs, so an unknown key keeps the sheet.
    private static let inertGitKey = try! NSRegularExpression(pattern:
        #"^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode|symlinks)"#
        + #"|remote\.[^=]+\.(url|fetch|pushurl|tagopt|prune)|branch\.[^=]+\.(remote|merge|rebase)"#
        + #"|user\.(name|email)|extensions\.(worktreeconfig|objectformat)|init\.defaultbranch)=.*$"#)

    /// The user's global and system config are their own; only the repo's
    /// local and worktree scopes arrive with a clone. A config git cannot read
    /// counts as not inert.
    func gitConfigInert() async -> Bool {
        guard let workdir else { return false }
        let outcome = await ProcessGroupRunner.run(
            executable: "/usr/bin/git", arguments: ["config", "--show-scope", "--list"],
            cwd: workdir, timeout: 5)
        guard outcome.exitCode == 0, !outcome.timedOut else { return false }
        for line in outcome.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { return false }
            guard parts[0] == "local" || parts[0] == "worktree" else { continue }
            let entry = String(parts[1]).lowercased()
            let range = NSRange(entry.startIndex..., in: entry)
            if Self.inertGitKey.firstMatch(in: entry, range: range) == nil { return false }
        }
        return true
    }

    /// Split from `actionBand` because `ParentToolRunner.approval(for:)` is
    /// synchronous and only the path tools can be decided without the workbook.
    func fileBand(tool: String, arguments: [String: Any]) -> ActionBand {
        var facts = ActionFacts()
        var judged = arguments
        if tool == NativeTool.createDocument.rawValue || tool == NativeTool.writeFile.rawValue {
            guard let path = arguments["path"] as? String,
                  case .success(let real) = writeBarrier(path) else { return .critical }
            facts.pathExists = Self.entryExists(real)
            facts.inWorkZone = inDeliverablesZone(real)
            // The name is judged where it really lands: a visible link that points
            // into a hidden folder must not make `link/x.md` look visible.
            judged["path"] = relativeToWorkdir(real) ?? real
        }
        return ActionBand.classify(toolName: tool, arguments: judged, facts: facts)
    }

    /// The default workdir is the whole home, where a new .json or .md can be
    /// an agent's or an editor's config, and Library and the app's own folders
    /// (memory, skills) are read back into a prompt. None of that is a folder
    /// meant for deliverables. Compared case-folded: the volume is not
    /// case-sensitive, so `skill.md` is the catalog's `SKILL.md`.
    private func inDeliverablesZone(_ real: String) -> Bool {
        guard pathValidator.isInWorkdir(real), let workdir else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path.lowercased()
        let work = ((workdir as NSString).standardizingPath as NSString).resolvingSymlinksInPath.lowercased()
        if work == "/" || home == work || home.hasPrefix(work + "/") { return false }
        let lowered = real.lowercased()
        let owned = [(skills?.root ?? SkillsLocation.standard().root).path.lowercased(), home + "/library"]
        return !owned.contains { lowered == $0 || lowered.hasPrefix($0 + "/") }
    }

    private func relativeToWorkdir(_ real: String) -> String? {
        guard let workdir else { return nil }
        let work = ((workdir as NSString).standardizingPath as NSString).resolvingSymlinksInPath
        guard real.hasPrefix(work + "/") else { return nil }
        return String(real.dropFirst(work.count + 1))
    }

    /// lstat semantics (attributes of the entry itself, a link is not followed).
    static func attributes(_ path: String) -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            return nil
        }
    }

    /// lstat semantics: a dangling symlink is something already there, and
    /// `fileExists` would call it free.
    static func entryExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Nil when it could not be read: the caller must then treat the write as
    /// an overwrite.
    // HACK: a formula that evaluates to "" reads as empty, so writing over it
    // counts as an append. The copy of the saved workbook that every write makes
    // is the net; read formulas through the driver when it exposes them.
    private func rangeHasValues(_ arguments: [String: Any]) async -> Bool? {
        guard let sheets, let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)),
              let app = await sheetApp(arguments, sheets) else { return nil }
        do {
            return try await sheets.read(app, range: range).contains { $0.contains { !$0.isEmpty } }
        } catch {
            return nil
        }
    }

    /// What an action that ran on its own band leaves on the island, built
    /// from the arguments it really ran with (the workbook the runner bound,
    /// the path it resolved) and from the target as it is right now, so the
    /// undo can tell later whether the user touched it. Nil when there is
    /// nothing to say; the receipt has no undo when the target cannot be read.
    func receipt(tool: String, arguments: [String: Any]) async -> UndoReceipt? {
        switch tool {
        case NativeTool.createDocument.rawValue, NativeTool.writeFile.rawValue:
            guard let path = arguments["path"] as? String, case .success(let real) = writeBarrier(path),
                  let attributes = Self.attributes(real) else { return nil }
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let modified = attributes[.modificationDate] as? Date ?? Date()
            return UndoReceipt(
                kind: .created, subject: (real as NSString).lastPathComponent,
                undo: .trash(path: real, size: size, modified: modified))
        case NativeTool.sheetWrite.rawValue:
            guard let range = (arguments["range"] as? String).flatMap(SheetRange.init(a1:)),
                  let app = (arguments["app"] as? String).flatMap(SheetApp.init(rawValue:)),
                  let workbook = SheetApproval.workbook(in: arguments) else { return nil }
            var undo: UndoReceipt.Undo?
            do {
                if let now = try await sheets?.read(app, range: range) {
                    undo = .clearCells(app: app, range: range.a1, workbook: workbook, expected: now)
                }
            } catch {
                // No baseline to compare against later, so no undo is offered.
                Log.app("receipt: sheet unreadable, no undo")
            }
            return UndoReceipt(kind: .wrote, subject: range.a1, undo: undo)
        default:
            return nil
        }
    }
}
