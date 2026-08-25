import Foundation

public enum RiskLevel: Sendable, Equatable {
    case safe
    case requiresApproval
}

public enum NativeTool: String, CaseIterable, Sendable, Equatable {
    case findPlaces = "find_places"
    case listDirectory = "list_directory"
    case readFile = "read_file"
    case writeFile = "write_file"
    case editFile = "edit_file"
    case runShell = "run_shell"
    case webFetch = "web_fetch"
    case webSearch = "web_search"

    public var riskLevel: RiskLevel {
        switch self {
        case .findPlaces, .listDirectory, .readFile, .webFetch, .webSearch:
            return .safe
        case .writeFile, .editFile, .runShell:
            return .requiresApproval
        }
    }

    public var spec: ToolSpec {
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
        }
    }
}

public struct PathValidator: Sendable {
    public var workdir: String?

    public init(workdir: String?) {
        self.workdir = workdir
    }

    public func isAllowed(_ path: String) -> Bool {
        guard let workdir = workdir else {
            return false
        }

        // Normalize the path to resolve . and .. components
        let normalizedWorkdir = (workdir as NSString).standardizingPath
        let normalizedPath: String

        // If path is absolute, use it; if relative, resolve against workdir
        if path.hasPrefix("/") {
            normalizedPath = (path as NSString).standardizingPath
        } else {
            let combined = (normalizedWorkdir as NSString).appendingPathComponent(path)
            normalizedPath = (combined as NSString).standardizingPath
        }

        // Ensure the normalized path starts with the normalized workdir
        if normalizedPath == normalizedWorkdir {
            return true
        }

        // Check if path is inside workdir (with trailing slash for directory boundary)
        let workdirWithSlash = normalizedWorkdir.hasSuffix("/")
            ? normalizedWorkdir
            : normalizedWorkdir + "/"

        return normalizedPath.hasPrefix(workdirWithSlash)
    }
}
