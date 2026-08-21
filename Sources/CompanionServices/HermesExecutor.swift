import CompanionCore
import Foundation

/// Executor that runs `hermes chat -Q` as a batch subprocess.
/// No persistent session: each job is a fresh invocation that captures output.
public struct HermesExecutor: Executor, Sendable {
    public var descriptor: ExecutorDescriptor

    private let workdir: String
    private let processLauncher: any ProcessLauncher

    public init(
        workdir: String,
        processLauncher: any ProcessLauncher
    ) {
        self.workdir = workdir
        self.processLauncher = processLauncher

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "hermes"),
            shortName: "hermes",
            title: "Hermes",
            kind: .detectedCLI,
            modelArgs: []
        )
    }

    /// Execute a job as a batch: launch hermes, send full prompt, capture output.
    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()

        // Build full prompt from job details
        let prompt = """
        Goal: \(job.goal)
        Context: \(job.context)
        """

        // Launch hermes chat -Q (quiet mode, batch)
        let executable = "/usr/local/bin/hermes"
        let args = ["chat", "-Q"]

        guard let handle = await processLauncher.launch(
            executable: executable,
            arguments: args,
            cwd: workdir
        ) else {
            return JobResult(output: "Hermes launch failed", isError: true)
        }

        events.yield(.stepStarted(tool: "hermes", summary: "Running Hermes"))

        // Send the full prompt as a single user turn
        do {
            try await handle.sendLine(prompt)
        } catch {
            events.yield(.stepFinished(tool: "hermes", ok: false))
            return JobResult(output: "Failed to send prompt to Hermes", isError: true)
        }

        // Capture all output (hermes -Q outputs result on stdout, all at once)
        var output = ""
        while let line = await handle.readLine() {
            try Task.checkCancellation()
            output += line + "\n"
        }

        await handle.terminate()
        events.yield(.stepFinished(tool: "hermes", ok: true))

        // Hermes batch output is plain text result, no error marker
        return JobResult(output: output.trimmingCharacters(in: .whitespacesAndNewlines), isError: false)
    }
}
