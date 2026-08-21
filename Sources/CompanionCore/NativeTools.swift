import Foundation

public enum RiskLevel: Sendable, Equatable {
    case safe
    case requiresApproval
}

public enum NativeTool: String, CaseIterable, Sendable, Equatable {
    case readFile = "read_file"
    case writeFile = "write_file"
    case editFile = "edit_file"
    case runShell = "run_shell"
    case webFetch = "web_fetch"
    case webSearch = "web_search"

    public var riskLevel: RiskLevel {
        switch self {
        case .readFile, .webFetch, .webSearch:
            return .safe
        case .writeFile, .editFile, .runShell:
            return .requiresApproval
        }
    }

    public var spec: ToolSpec {
        switch self {
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
