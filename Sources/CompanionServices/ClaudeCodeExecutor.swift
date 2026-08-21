import CompanionCore
import Foundation

/// Executor that runs `claude -p` as a persistent process with bidirectional NDJSON stream.
/// Process persists between jobs if workdir doesn't change; respawns on workdir change.
public struct ClaudeCodeExecutor: Executor, Sendable {
    public var descriptor: ExecutorDescriptor

    private let workdir: String
    private let processLauncher: any ProcessLauncher
    private let approvals: any ApprovalsProvider
    private var process: ProcessHandleReference?

    public init(
        workdir: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider
    ) {
        self.workdir = workdir
        self.processLauncher = processLauncher
        self.approvals = approvals

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "claude-code"),
            shortName: "claude",
            title: "Claude Code",
            kind: .detectedCLI,
            modelArgs: ["-m", "claude-opus-4-1"]
        )
    }

    /// Execute a job: connect to process, send user turn, handle approval loops,
    /// emit events, return result.
    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()

        // Ensure process is running
        let handle = try await ensureProcessRunning()

        // Build user turn: format as NDJSON for claude -p
        let userTurn = buildUserTurn(goal: job.goal, context: job.context)
        try await handle.sendLine(userTurn)

        // Read response loop: parse events from NDJSON stream
        var output = ""
        var sessionId: String? = nil

        while let line = await handle.readLine() {
            try Task.checkCancellation()

            let event = AgentStreamCodec.parse(line)
            switch event {
            case .initialized(let sid):
                sessionId = sid

            case .toolUse(let name, let detail):
                // Emit step event for UI timeline
                events.yield(.stepStarted(tool: name, summary: detail))
                events.yield(.stepFinished(tool: name, ok: true))

            case .thought(let text):
                events.yield(.thought(text))

            case .approval(let approval):
                // Request approval from the shared Approvals actor
                events.yield(.approvalRequested(approval))
                let response = await approvals.request(approval)

                // Send control response back to claude
                let message = response.approved ? "" : "User denied authorization"
                if let controlResp = AgentStreamCodec.controlResponse(
                    requestId: approval.requestId,
                    allow: response.approved,
                    inputJSON: approval.inputJSON,
                    message: message
                ) {
                    try await handle.sendLine(controlResp)
                }

            case .result(let text, let isError):
                output = text
                return JobResult(output: output, isError: isError, sessionId: sessionId)

            case .ignored:
                continue
            }
        }

        // Stream ended without result
        return JobResult(output: output, isError: true, sessionId: sessionId)
    }

    // MARK: - Helpers

    private func ensureProcessRunning() async throws -> any ProcessHandle {
        // For now, always launch a new process (state management comes in IMPROVE phase)
        let executable = "/usr/local/bin/claude"
        let args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-mode", "acceptEdits",
            "--allowedTools", "WebSearch,WebFetch"
        ]

        guard let handle = await processLauncher.launch(
            executable: executable,
            arguments: args,
            cwd: workdir
        ) else {
            throw ExecutorError.processLaunchFailed
        }

        return handle
    }

    private func buildUserTurn(goal: String, context: String) -> String {
        // Format as NDJSON for stream-json input
        let fullPrompt = """
        Goal: \(goal)
        Context: \(context)
        """

        if let line = AgentStreamCodec.userTurn(fullPrompt) {
            return line
        }
        return ""
    }
}

enum ExecutorError: Error {
    case processLaunchFailed
    case invalidTranscript
}

// MARK: - Process State Reference (for future persistence)

private class ProcessHandleReference: @unchecked Sendable {
    let handle: any ProcessHandle

    init(_ handle: any ProcessHandle) {
        self.handle = handle
    }
}
