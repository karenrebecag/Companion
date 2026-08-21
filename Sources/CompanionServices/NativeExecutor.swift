import CompanionCore
import Foundation

/// Native specialist executor: loop over ChatProvider with tool execution and approval gates.
/// All tool execution routes through this single entry point.
public struct NativeExecutor: Executor, Sendable {
    public var descriptor: ExecutorDescriptor

    private let chatProvider: any ChatProvider
    private let toolRunner: NativeToolRunner
    private let config: Config
    private let maxIterations = 10

    public init(
        descriptor: ExecutorDescriptor,
        chatProvider: any ChatProvider,
        config: Config
    ) {
        self.descriptor = descriptor
        self.chatProvider = chatProvider
        self.toolRunner = NativeToolRunner(workdir: config.workdir)
        self.config = config
    }

    /// Execute a job by looping with the model: accumulate text, execute tools on request,
    /// emit JobEvent through the continuation. Respect cancellation gracefully.
    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()

        // Build initial history with the job prompt
        let handoff = Handoff(goal: job.goal, context: job.context)
        let jobPrompt = Escalation.jobPrompt(
            handoff,
            workdir: config.workdir ?? "(not configured)",
            desktop: NSHomeDirectory())

        // System message with executor role (once)
        let systemMessage = Turn(
            role: .system,
            content: Escalation.executorRole)

        // User message with job details (delimited section for anti-injection)
        let userMessage = Turn(
            role: .user,
            content: jobPrompt)

        var history = [systemMessage, userMessage]
        var accumulatedOutput = ""
        var iteration = 0

        // Main loop
        while iteration < maxIterations {
            try Task.checkCancellation()
            iteration += 1

            // Request streaming reply with available tools
            let tools = nativeToolSpecs()
            let stream = chatProvider.stream(history, tools: tools)

            var isToolCall = false
            var toolName = ""
            var toolArgs = ""

            // Consume stream
            do {
                for try await delta in stream {
                    try Task.checkCancellation()

                    switch delta {
                    case .text(let text):
                        accumulatedOutput += text

                    case .handoff(let h):
                        // Tool call: parse which tool and its args
                        isToolCall = true
                        toolName = h.goal
                        toolArgs = h.context
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return JobResult(output: accumulatedOutput, isError: true)
            }

            // If model returned text and no tool call, we're done
            if !isToolCall || toolName.isEmpty {
                return JobResult(output: accumulatedOutput, isError: false)
            }

            // Tool was requested: check approval and execute
            events.yield(.stepStarted(tool: toolName, summary: "Executing \(toolName)"))

            let approvalNeeded = riskLevel(tool: toolName) == .requiresApproval
            var approved = false

            if approvalNeeded {
                // Ask for approval
                let requestId = UUID().uuidString
                let approval = ApprovalRequest(
                    requestId: requestId,
                    toolName: toolName,
                    summary: "Tool requires user approval",
                    inputJSON: toolArgs)

                events.yield(.approvalRequested(approval))

                // In this tramp, approval is manual (D2); mock approval for now
                // Real flow: wait for user response via resolve_approval tool call
                approved = false // Default deny per spec
            }

            // Execute tool (may fail silently if not approved)
            let toolResult = try await executeToolSafely(
                tool: toolName,
                arguments: parseToolArguments(toolArgs),
                approved: approved || !approvalNeeded)

            events.yield(.stepFinished(tool: toolName, ok: toolResult.ok))

            // If tool failed or was denied, inform model and continue
            if !toolResult.ok {
                let toolFailure = Turn(
                    role: .assistant,
                    content: "Tool \(toolName) failed: \(toolResult.output)")
                history.append(toolFailure)
                continue
            }

            // Tool succeeded: add result to history and continue
            let toolSuccess = Turn(
                role: .user,
                content: "Tool result: \(toolResult.output)")
            history.append(toolSuccess)
        }

        // Hit iteration limit
        return JobResult(
            output: accumulatedOutput,
            isError: true)
    }

    // MARK: - Helpers

    private func nativeToolSpecs() -> [ToolSpec] {
        NativeTool.allCases.map { $0.spec }
    }

    private func riskLevel(tool: String) -> RiskLevel {
        NativeTool(rawValue: tool)?.riskLevel ?? .safe
    }

    /// Execute tool through the single entry point (NativeToolRunner).
    /// No other code path should execute tools directly.
    private func executeToolSafely(
        tool: String,
        arguments: [String: Any],
        approved: Bool
    ) async throws -> ToolResult {
        return try await toolRunner.execute(tool: tool, arguments: arguments, approved: approved)
    }

    /// Parse tool arguments from JSON string (from model output).
    private func parseToolArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8) else { return [:] }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }
            return obj
        } catch {
            return [:]
        }
    }
}
