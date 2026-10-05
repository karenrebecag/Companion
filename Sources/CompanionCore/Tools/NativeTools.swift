import Foundation

package enum RiskLevel: Sendable, Equatable {
    case safe
    case requiresApproval
}

package enum NativeTool: String, CaseIterable, Sendable, Equatable {
    case findPlaces = "find_places"
    case listDirectory = "list_directory"
    case readFile = "read_file"
    case writeFile = "write_file"
    case editFile = "edit_file"
    case deleteFile = "delete_file"
    case runShell = "run_shell"
    case webFetch = "web_fetch"
    case webSearch = "web_search"
    /// Wave 20: deliverables and live spreadsheets.
    case createDocument = "create_document"
    case sheetRead = "sheet_read"
    case sheetWrite = "sheet_write"
    /// H-7 PR4c: the copies kept around a save of the user's file, and the way back.
    case listFileHistory = "list_file_history"
    case restoreFileVersion = "restore_file_version"

    package var riskLevel: RiskLevel {
        switch self {
        case .findPlaces, .listDirectory, .readFile, .webFetch, .webSearch, .sheetRead, .listFileHistory:
            return .safe
        case .writeFile, .editFile, .deleteFile, .runShell, .createDocument, .sheetWrite, .restoreFileVersion:
            return .requiresApproval
        }
    }

    package var spec: ToolSpec {
        switch self {
        case .findPlaces:
            return ToolSpec(
                name: "find_places",
                description: "Find real places near somewhere — cinemas, "
                    + "restaurants, shops, an address, a landmark. Use it "
                    + "whenever the user asks where something is or what is "
                    + "nearby; it is a map lookup, not a web search, and it "
                    + "works with no keys. You get names and addresses to "
                    + "talk about, and the map is drawn from the lookup "
                    + "rather than from anything you type.",
                properties: [
                    ToolProperty(name: "query", type: "string",
                                 description: "what to look for"),
                    ToolProperty(name: "near", type: "string",
                                 description: "city or area to search in"),
                ],
                required: ["query"])
        case .listDirectory:
            return ToolSpec(
                name: "list_directory",
                // The description earns its length: without it the model has
                // no way to know that looking around is cheap and allowed, and
                // it falls back to shell for something that needs no approval.
                description: "List what is inside a folder. Use this FIRST "
                    + "whenever the user names a file or folder loosely — the "
                    + "name they say and the name on disk rarely match "
                    + "exactly, and reading the real listing lets you "
                    + "recognise it. Never guess a path you have not listed.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "folder to list"),
                    ToolProperty(name: "depth", type: "integer",
                                 description: "levels to descend, 1 by "
                                     + "default, 3 at most"),
                ],
                required: ["path"])
        case .readFile:
            return ToolSpec(
                name: "read_file",
                description: "Read the contents of a file from the working directory.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "path to the file to read"),
                ],
                required: ["path"]
            )
        case .writeFile:
            return ToolSpec(
                name: "write_file",
                description: "Write content to a file in the working directory.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "path to the file to write"),
                    ToolProperty(name: "content", type: "string",
                                 description: "content to write"),
                ],
                required: ["path", "content"]
            )
        case .editFile:
            return ToolSpec(
                name: "edit_file",
                description: "Edit a file by replacing a section.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "path to the file"),
                    ToolProperty(name: "old_string", type: "string",
                                 description: "exact text to replace"),
                    ToolProperty(name: "new_string", type: "string",
                                 description: "replacement text"),
                ],
                required: ["path", "old_string", "new_string"]
            )
        case .deleteFile:
            return ToolSpec(
                name: "delete_file",
                description: "Delete a file or folder after the user approves. It goes to the "
                    + "Trash, where the user can put it back; only if the Trash is "
                    + "unavailable is it deleted permanently, and the result says which "
                    + "happened. Use this instead of rm.",
                properties: [
                    ToolProperty(name: "path", type: "string",
                                 description: "path to the file or folder to delete"),
                ],
                required: ["path"]
            )
        case .runShell:
            return ToolSpec(
                name: "run_shell",
                description: "Execute a shell command in the working directory.",
                properties: [
                    ToolProperty(name: "command", type: "string",
                                 description: "shell command to run"),
                ],
                required: ["command"]
            )
        case .webFetch:
            return ToolSpec(
                name: "web_fetch",
                description: "Fetch and read the content of a web page.",
                properties: [
                    ToolProperty(name: "url", type: "string",
                                 description: "URL to fetch"),
                ],
                required: ["url"]
            )
        case .webSearch:
            return ToolSpec(
                name: "web_search",
                description: "Search the web.",
                properties: [
                    ToolProperty(name: "query", type: "string",
                                 description: "search query"),
                ],
                required: ["query"]
            )
        case .createDocument, .sheetRead, .sheetWrite, .listFileHistory, .restoreFileVersion:
            return DeliverableTools.spec(self)
        }
    }
}

/// Where the specialist may read and where it may write. The working folder
/// is one root; the app's own folders (skills, knowledge, memory) are others,
/// and the system skills are readable but never writable (Wave 11a).
package struct PathValidator: Sendable {
    package struct Root: Sendable, Equatable {
        package var path: String
        package var writable: Bool

        package init(path: String, writable: Bool) {
            self.path = (path as NSString).standardizingPath
            self.writable = writable
        }
    }

    package var workdir: String?
    package var roots: [Root]

    package init(workdir: String?) {
        self.init(workdir: workdir, extraRoots: [])
    }

    package init(workdir: String?, extraRoots: [Root]) {
        self.workdir = workdir
        var roots = extraRoots
        if let workdir { roots.insert(Root(path: workdir, writable: true), at: 0) }
        self.roots = roots
    }

    /// Normalizes `.` and `..` first; a relative path resolves against the
    /// working folder and has nowhere to go without one.
    package func isAllowed(_ path: String, forWrite: Bool = false) -> Bool {
        let normalizedPath: String
        if path.hasPrefix("/") {
            normalizedPath = (path as NSString).standardizingPath
        } else {
            guard let workdir else { return false }
            let combined = ((workdir as NSString).standardizingPath as NSString)
                .appendingPathComponent(path)
            normalizedPath = (combined as NSString).standardizingPath
        }
        return roots.contains { root in
            (!forWrite || root.writable) && Self.contains(root.path, normalizedPath)
        }
    }

    /// The working folder only: the app's own folders (skills, memory) are
    /// writable roots too, but a file there is read back into the prompt, so
    /// it is never a plain deliverable.
    package func isInWorkdir(_ resolved: String) -> Bool {
        guard let workdir else { return false }
        return Self.contains((workdir as NSString).standardizingPath, resolved)
    }

    /// A trailing slash keeps `/a/b` from claiming `/a/bc`.
    private static func contains(_ root: String, _ path: String) -> Bool {
        if path == root { return true }
        let withSlash = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(withSlash)
    }
}
