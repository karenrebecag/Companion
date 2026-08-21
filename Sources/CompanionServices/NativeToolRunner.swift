import CompanionCore
import Foundation

public struct ToolResult: Sendable {
    public var ok: Bool
    public var output: String

    public init(ok: Bool, output: String) {
        self.ok = ok
        self.output = output
    }
}

/// Single entry point for tool execution: enforces approval gate for risky tools
/// and applies double-barrier path validation (lexical + symlink resolution).
public struct NativeToolRunner: Sendable {
    private let workdir: String?
    private let pathValidator: PathValidator
    private let timeout: TimeInterval = 60 // seconds

    public init(workdir: String?) {
        self.workdir = workdir
        self.pathValidator = PathValidator(workdir: workdir)
    }

    /// Execute a tool with approval gate and path barrier.
    /// Returns error BEFORE touching disk/shell if risky tool lacks approval.
    public func execute(
        tool: String,
        arguments: [String: Any],
        approved: Bool
    ) async throws -> ToolResult {
        guard let nativeTool = NativeTool(rawValue: tool) else {
            return ToolResult(ok: false, output: "Unknown tool: \(tool)")
        }

        // First gate: check risk level and approval
        if nativeTool.riskLevel == .requiresApproval && !approved {
            return ToolResult(ok: false, output: "Tool requires approval: \(tool)")
        }

        // Dispatch to implementation
        switch nativeTool {
        case .readFile:
            return try readFile(arguments: arguments)
        case .writeFile:
            return try writeFile(arguments: arguments)
        case .editFile:
            return try editFile(arguments: arguments)
        case .runShell:
            return try runShell(arguments: arguments)
        case .webFetch:
            return try await webFetch(arguments: arguments)
        case .webSearch:
            return try await webSearch(arguments: arguments)
        }
    }

    // MARK: - Tool Implementations

    private func readFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }

        // Double barrier: lexical validation + real path resolution
        guard pathValidator.isAllowed(path) else {
            return ToolResult(ok: false, output: "Path outside working directory")
        }

        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return ToolResult(ok: false, output: "Resolved path outside working directory")
        }

        do {
            let content = try String(contentsOfFile: realPath, encoding: .utf8)
            // Limit size to prevent memory exhaustion
            let maxSize = 10 * 1024 * 1024 // 10 MB
            if content.count > maxSize {
                return ToolResult(
                    ok: true,
                    output: content.prefix(maxSize) + "\n... (truncated)"
                )
            }
            return ToolResult(ok: true, output: content)
        } catch {
            return ToolResult(ok: false, output: "Failed to read file: \(error)")
        }
    }

    private func writeFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        guard let content = arguments["content"] as? String else {
            return ToolResult(ok: false, output: "Missing content argument")
        }

        // Double barrier
        guard pathValidator.isAllowed(path) else {
            return ToolResult(ok: false, output: "Path outside working directory")
        }

        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return ToolResult(ok: false, output: "Resolved path outside working directory")
        }

        do {
            try content.write(toFile: realPath, atomically: true, encoding: .utf8)
            return ToolResult(ok: true, output: "File written successfully")
        } catch {
            return ToolResult(ok: false, output: "Failed to write file: \(error)")
        }
    }

    private func editFile(arguments: [String: Any]) throws -> ToolResult {
        guard let path = arguments["path"] as? String else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        guard let oldString = arguments["old_string"] as? String else {
            return ToolResult(ok: false, output: "Missing old_string argument")
        }
        guard let newString = arguments["new_string"] as? String else {
            return ToolResult(ok: false, output: "Missing new_string argument")
        }

        // Double barrier
        guard pathValidator.isAllowed(path) else {
            return ToolResult(ok: false, output: "Path outside working directory")
        }

        let realPath = resolveRealPath(path)
        guard pathValidator.isAllowed(realPath) else {
            return ToolResult(ok: false, output: "Resolved path outside working directory")
        }

        do {
            var content = try String(contentsOfFile: realPath, encoding: .utf8)
            guard content.contains(oldString) else {
                return ToolResult(ok: false, output: "old_string not found in file")
            }
            content = content.replacingOccurrences(of: oldString, with: newString)
            try content.write(toFile: realPath, atomically: true, encoding: .utf8)
            return ToolResult(ok: true, output: "File edited successfully")
        } catch {
            return ToolResult(ok: false, output: "Failed to edit file: \(error)")
        }
    }

    private func runShell(arguments: [String: Any]) throws -> ToolResult {
        guard let command = arguments["command"] as? String else {
            return ToolResult(ok: false, output: "Missing command argument")
        }

        guard let workdir = workdir else {
            return ToolResult(ok: false, output: "No working directory configured")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workdir)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()

            // Wait with timeout
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                usleep(10_000) // 0.01 second
            }

            if process.isRunning {
                process.terminate()
                return ToolResult(
                    ok: false,
                    output: "Command execution timeout exceeded (\(timeout)s)")
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            var output = String(data: outData, encoding: .utf8) ?? ""
            let stderr = String(data: errData, encoding: .utf8) ?? ""

            if !stderr.isEmpty {
                output += "\n" + stderr
            }

            return ToolResult(ok: process.terminationStatus == 0, output: output)
        } catch {
            return ToolResult(ok: false, output: "Failed to execute command: \(error)")
        }
    }

    private func webFetch(arguments: [String: Any]) async throws -> ToolResult {
        guard let urlString = arguments["url"] as? String else {
            return ToolResult(ok: false, output: "Missing url argument")
        }

        guard let url = URL(string: urlString) else {
            return ToolResult(ok: false, output: "Invalid URL")
        }

        // Validate endpoint policy
        guard EndpointPolicy.isAcceptable(url) else {
            return ToolResult(ok: false, output: "URL not acceptable by security policy")
        }

        let request = URLRequest(url: url, timeoutInterval: 30)
        let session = URLSession.shared

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(ok: false, output: "Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                return ToolResult(
                    ok: false,
                    output: "HTTP \(httpResponse.statusCode)")
            }

            let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""

            // Limit size to prevent memory exhaustion
            let maxSize = 1 * 1024 * 1024 // 1 MB for web
            if content.count > maxSize {
                return ToolResult(
                    ok: true,
                    output: content.prefix(maxSize) + "\n... (truncated)"
                )
            }

            return ToolResult(ok: true, output: content)
        } catch {
            return ToolResult(ok: false, output: "Failed to fetch URL: \(error)")
        }
    }

    private func webSearch(arguments: [String: Any]) async throws -> ToolResult {
        guard arguments["query"] as? String != nil else {
            return ToolResult(ok: false, output: "Missing query argument")
        }

        // web_search requires a provider key we don't have configured yet
        // Return "not available" instead of inventing a backend
        return ToolResult(
            ok: false,
            output: "web_search not available: requires configured search provider API key")
    }

    // MARK: - Path Utilities

    /// Resolve symlinks to get the real path on disk, then re-validate.
    private func resolveRealPath(_ path: String) -> String {
        let absolutePath = path.hasPrefix("/")
            ? path
            : ((workdir ?? ".") as NSString).appendingPathComponent(path)

        // Use resolvingSymlinksInPath to follow symlinks
        return (absolutePath as NSString).resolvingSymlinksInPath
    }
}
