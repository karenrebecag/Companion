import CompanionCore
import Foundation

/// Detects optional CLI executors available in the system PATH.
/// Builds a catalog of [claude-code, hermes] if their binaries are found.
public struct CLIExecutorProbe: Sendable {
    private let processLauncher: any ProcessLauncher
    private let workdir: String

    public init(
        processLauncher: any ProcessLauncher,
        workdir: String
    ) {
        self.processLauncher = processLauncher
        self.workdir = workdir
    }

    /// Probe PATH for Claude Code and Hermes binaries.
    /// Returns descriptors for those found (in order of availability).
    public func detectAvailable() async -> [ExecutorDescriptor] {
        var detected: [ExecutorDescriptor] = []

        // Check for claude in PATH
        if await isBinaryAvailable("claude") {
            detected.append(ExecutorDescriptor(
                id: ExecutorID(rawValue: "claude-code"),
                shortName: "claude",
                title: "Claude Code",
                kind: .detectedCLI,
                modelArgs: ["-m", "claude-opus-4-1"]
            ))
        }

        // Check for hermes in PATH
        if await isBinaryAvailable("hermes") {
            detected.append(ExecutorDescriptor(
                id: ExecutorID(rawValue: "hermes"),
                shortName: "hermes",
                title: "Hermes",
                kind: .detectedCLI,
                modelArgs: []
            ))
        }

        return detected
    }

    /// Check if a binary exists in PATH by attempting `which <binary>`.
    private func isBinaryAvailable(_ binary: String) async -> Bool {
        let executable = "/usr/bin/which"
        let args = [binary]

        guard let handle = await processLauncher.launch(
            executable: executable,
            arguments: args,
            cwd: workdir
        ) else {
            return false
        }

        // If which succeeds, it prints the path; any output = found
        let found = (await handle.readLine()) != nil
        await handle.terminate()
        return found
    }
}
