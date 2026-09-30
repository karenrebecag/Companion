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
    /// not Library, not the app's own folders.
    package var inWorkZone: Bool
    /// Whether the range already holds values; nil when it was not read.
    package var rangeHasValues: Bool?
    /// The user's own words named this host (`ParentToolGate.saidIt`).
    package var hostSaid: Bool
    /// The resolved click/menu target falls in a destructive family.
    package var destructiveTarget: Bool
    /// The front app takes commands: typing there is running them.
    package var inTerminal: Bool

    package init(
        pathExists: Bool = true, inWorkZone: Bool = false, rangeHasValues: Bool? = nil,
        hostSaid: Bool = false, destructiveTarget: Bool = false, inTerminal: Bool = false
    ) {
        self.pathExists = pathExists
        self.inWorkZone = inWorkZone
        self.rangeHasValues = rangeHasValues
        self.hostSaid = hostSaid
        self.destructiveTarget = destructiveTarget
        self.inTerminal = inTerminal
    }
}

extension ActionBand {
    private static let reads: Set<String> = [
        "look", "see", "read_focused", "list_apps", "read_skill", "find_places",
        "list_directory", "read_file", "web_fetch", "web_search", "sheet_read",
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
        if reads.contains(toolName) { return .act }
        if hands.contains(toolName) {
            return facts.destructiveTarget || facts.inTerminal ? .critical : .act
        }
        switch toolName {
        case NativeTool.createDocument.rawValue:
            // createDirectory(intermediate) builds whatever tree the path names,
            // so a hidden or app-owned destination is judged like write_file's.
            guard let path = arguments["path"] as? String, isVisible(path) else { return .critical }
            return facts.inWorkZone && !facts.pathExists ? .act : .critical
        case NativeTool.writeFile.rawValue:
            guard let path = arguments["path"] as? String, isPlainData(path) else { return .critical }
            return facts.inWorkZone && !facts.pathExists ? .act : .critical
        case NativeTool.sheetWrite.rawValue:
            return facts.rangeHasValues == false ? .act : .critical
        case ParentTool.openURL.rawValue:
            return facts.hostSaid ? .act : .confirm
        default:
            return toolName.hasPrefix(ApprovalCopy.appToolPrefix) ? .confirm : .critical
        }
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
