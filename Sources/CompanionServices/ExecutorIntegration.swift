import CompanionCore
import Foundation

/// Factory for creating executors based on descriptor and workdir.
/// Centralizes executor instantiation to ensure all have consistent state management.
public enum ExecutorFactory {
    /// Create an executor from a descriptor.
    /// Used by ExecutorProvider when a new executor needs to be instantiated.
    public static func createExecutor(
        descriptor: ExecutorDescriptor,
        workdir: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider
    ) -> (any Executor)? {
        switch descriptor.id.rawValue {
        case "native":
            // Native executor is created elsewhere (part of composition root)
            return nil

        case "claude-code":
            return ClaudeCodeExecutor(
                workdir: workdir,
                processLauncher: processLauncher,
                approvals: approvals
            )

        case "hermes":
            return HermesExecutor(
                workdir: workdir,
                processLauncher: processLauncher
            )

        default:
            return nil
        }
    }
}

/// Real process launcher for production: spawns actual subprocesses.
public struct RealProcessLauncher: ProcessLauncher {
    public init() {}

    public func launch(
        executable: String,
        arguments: [String],
        cwd: String?
    ) async -> (any ProcessHandle)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return RealProcessHandle(process: process, stdin: inputPipe, stdout: outputPipe)
        } catch {
            return nil
        }
    }
}

/// Real process handle: communicates with subprocess via pipes.
/// final + @unchecked: Process and Pipe are not Sendable, and the handle is
/// only ever driven from the executor's own task.
private final class RealProcessHandle: ProcessHandle, @unchecked Sendable {
    private let process: Process
    private let stdin: Pipe
    private let stdout: Pipe
    private let outputQueue: DispatchQueue

    init(process: Process, stdin: Pipe, stdout: Pipe) {
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.outputQueue = DispatchQueue(label: "com.companion.process-output", attributes: .concurrent)
    }

    func sendLine(_ line: String) async throws {
        guard let data = (line + "\n").data(using: .utf8) else {
            throw ProcessError.invalidEncoding
        }

        try await withCheckedThrowingContinuation { continuation in
            outputQueue.async(flags: .barrier) {
                do {
                    try self.stdin.fileHandleForWriting.write(contentsOf: data)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: ProcessError.writeFailed)
                }
            }
        }
    }

    func readLine() async -> String? {
        // Read a single line from stdout (blocking, called sequentially)
        let data = stdout.fileHandleForReading.readData(ofLength: 4096)
        guard !data.isEmpty else { return nil }

        if let string = String(data: data, encoding: .utf8) {
            // In real usage, would need proper line buffering; for now simple
            return string.trimmingCharacters(in: .newlines)
        }
        return nil
    }

    func terminate() async {
        process.terminate()
        do {
            try stdin.fileHandleForWriting.close()
        } catch {
            // Ignore close errors on cleanup
        }
        do {
            try stdout.fileHandleForReading.closeFile()
        } catch {
            // Ignore close errors on cleanup
        }
    }

    var isRunning: Bool {
        process.isRunning
    }
}

enum ProcessError: Error {
    case invalidEncoding
    case writeFailed
}
