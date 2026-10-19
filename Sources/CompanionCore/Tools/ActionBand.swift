import Foundation

/// Wave 20d A. How much a step needs from the user, in Incredible's three
/// levels: it just acts, it is confirmed on a card, or it can never be undone
/// or hands over the controls and always takes the sheet and a ticket.
package enum ActionBand: Sendable, Equatable {
    case act
    case confirm
    case critical
}

/// What the runner verified about the target before asking for a band. Every
/// field defaults to the answer that raises the band, so a caller that did not
/// look gets the sheet, not a free pass. The model never supplies any of it.
package struct ActionFacts: Sendable, Equatable {
    /// A symlink counts as existing, dangling or not.
    package var pathExists: Bool
    /// A folder the user handed over for deliverables: not the whole home,
    /// not Library, not the app's own folders. It only relaxes a new file from
    /// confirm to act; it never reaches an existing one.
    package var inWorkZone: Bool
    /// The destination is Library or one of the app's own folders (memory,
    /// skills): their files are read back into a prompt or run by a tool, so a
    /// new one there is never a plain deliverable, whatever the zone.
    package var appOwned: Bool
    /// The turn has read nothing outside the work folder, so a fetch has nothing
    /// of the user's to carry out in its address. Defaults to false: a caller
    /// that did not track the turn gets the owner, not a free pass.
    package var cleanTurn: Bool
    /// The turn already read something outside the work folder: an address it
    /// opens could carry that out. Only open_url reads it (web_fetch has the
    /// inverse `cleanTurn`, which fails closed).
    package var tainted: Bool
    /// Whether the range already holds values; nil when it was not read.
    package var rangeHasValues: Bool?
    /// The user's own words named this host (`ParentToolGate.saidIt`).
    package var hostSaid: Bool
    /// The resolved click/menu target falls in a destructive family.
    package var destructiveTarget: Bool
    /// The front app takes commands: typing there is running them.
    package var inTerminal: Bool
    /// The repo's own git config names no program git could run on a read
    /// (core.fsmonitor, filter.*, diff.*.textconv). A cloned repo carries its
    /// .git/config, so `git status` there is not a read until this is seen.
    package var gitConfigInert: Bool

    package init(
        pathExists: Bool = true, inWorkZone: Bool = false, appOwned: Bool = false, cleanTurn: Bool = false, tainted: Bool = false, rangeHasValues: Bool? = nil,
        hostSaid: Bool = false, destructiveTarget: Bool = false, inTerminal: Bool = false,
        gitConfigInert: Bool = false
    ) {
        self.pathExists = pathExists
        self.inWorkZone = inWorkZone
        self.appOwned = appOwned
        self.cleanTurn = cleanTurn
        self.tainted = tainted
        self.rangeHasValues = rangeHasValues
        self.hostSaid = hostSaid
        self.destructiveTarget = destructiveTarget
        self.inTerminal = inTerminal
        self.gitConfigInert = gitConfigInert
    }
}

extension ActionBand {
    private static let reads: Set<String> = [
        "look", "see", "read_focused", "list_apps", "read_skill", "find_places",
        "list_directory", "read_file", "web_search", "sheet_read",
    ]

    /// Local, non-destructive hands. What makes one of them dangerous is the
    /// target it resolves to, which arrives as a fact, not as a tool name.
    private static let hands: Set<String> = [
        "open_app", "open_file", "focus_window", "scroll", "click", "type_text", "press_key", "menu",
    ]

    /// Allowlist: a tool nobody classified is critical, so a new tool needs
    /// the sheet until someone decides otherwise.
    package static func classify(
        toolName: String, arguments: [String: Any], facts: ActionFacts
    ) -> ActionBand {
        // One line in a folder she can open, undone from Settings › Memoria.
        if reads.contains(toolName) || toolName == MemoryTool.name { return .act }
        if hands.contains(toolName) {
            return facts.destructiveTarget || facts.inTerminal ? .critical : .act
        }
        switch toolName {
        case NativeTool.createDocument.rawValue:
            // createDirectory(intermediate) builds whatever tree the path names,
            // so a hidden or app-owned destination is judged like write_file's.
            guard let path = arguments["path"] as? String, isVisible(path) else { return .critical }
            return newFileBand(facts)
        case NativeTool.writeFile.rawValue:
            guard let path = arguments["path"] as? String, isPlainData(path) else { return .critical }
            return newFileBand(facts)
        case NativeTool.sheetWrite.rawValue:
            return facts.rangeHasValues == false ? .act : .critical
        case NativeTool.webFetch.rawValue, NativeTool.readURL.rawValue:
            // Read, then fetch: text in a file or a page can ask for
            // `evil.tld?d=<what you read>`. In QA a critical band is the finger.
            // read_url is the same egress as web_fetch (the address goes out and
            // the host is chosen by the page), not the web_search class, whose
            // query goes to a fixed provider.
            return facts.cleanTurn || facts.hostSaid ? .act : .critical
        case ParentTool.openURL.rawValue:
            // Opening an http(s) address is navigation; the scheme check lives in `httpURL`.
            // After a read outside the work folder it is also a way out for what was read.
            return facts.tainted && !facts.hostSaid ? .critical : .act
        case NativeTool.runShell.rawValue:
            // A plain read cannot change the disk. Ask is never a denial:
            // every other command still takes the sheet.
            guard let command = arguments["command"] as? String,
                  CommandClassifier.classify(command) == .allow else { return .critical }
            if CommandClassifier.isGit(command), !facts.gitConfigInert { return .critical }
            return .act
        default:
            return toolName.hasPrefix(ApprovalCopy.appToolPrefix) ? .confirm : .critical
        }
    }

    /// The whole disk is open (docs/DECISIONS.md), so a new file anywhere asks
    /// for a confirmation; only a folder the user handed over for deliverables
    /// acts alone. Replacing something that exists is never a creation.
    private static func newFileBand(_ facts: ActionFacts) -> ActionBand {
        if facts.pathExists || facts.appOwned { return .critical }
        return facts.inWorkZone ? .act : .confirm
    }

    /// A file the folder's tooling would pick up and run (a git hook, a
    /// script, a Makefile, a launcher) is code, not a deliverable: writing it
    /// without a sheet is how an injected prompt plants something that runs
    /// later. Only data-shaped names in visible folders qualify.
    private static let dataExtensions: Set<String> = ["txt", "md", "markdown", "csv", "log"]

    /// Data-shaped names that a coding agent or a tool still reads as
    /// instructions or as what to run: planting one is code by another name.
    private static let instructionNames: Set<String> = [
        "claude.md", "agents.md", "gemini.md", "package.json", "composer.json", "deno.json",
        "tsconfig.json", "mcp.json", "settings.json", "tasks.json", "launch.json",
        "requirements.txt", "cmakelists.txt", "claude.local.md", "agent.md", "qwen.md", "warp.md",
        "crush.md", "conventions.md", "soul.md", "memory.md", "heartbeat.md", "skill.md", "knowledge.md",
    ]
    // HACK: a denylist of instruction names cannot be complete; it only matters
    // when the user picks a project folder (home and Library never act).
    // Upgrade trigger: the first tool that reads another name as instructions,
    // or moving write_file's act band to an explicit deliverables folder.

    static func isPlainData(_ path: String) -> Bool {
        guard isVisible(path), let name = path.split(separator: "/").last.map(String.init) else { return false }
        let lowered = name.lowercased()
        guard !instructionNames.contains(lowered), !lowered.contains("config") else { return false }
        return dataExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func isVisible(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        return !parts.isEmpty && !parts.contains(where: { $0.hasPrefix(".") || $0 == ".." })
    }
}
