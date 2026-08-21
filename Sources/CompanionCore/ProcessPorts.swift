import Foundation

/// Port for process launch: allows CLI executors to be tested without spawning real processes.
public protocol ProcessLauncher: Sendable {
    /// Launch a process with the given executable, arguments, and optional working directory.
    /// Returns a handle to read/write to the process, or nil if launch fails.
    func launch(
        executable: String,
        arguments: [String],
        cwd: String?
    ) async -> (any ProcessHandle)?
}

/// Handle to communicate with a running process.
public protocol ProcessHandle: Sendable {
    /// Send a line to stdin (NDJSON format expected).
    func sendLine(_ line: String) async throws

    /// Read the next line from stdout.
    func readLine() async -> String?

    /// Terminate the process.
    func terminate() async

    /// Check if the process is still running.
    var isRunning: Bool { get }
}
