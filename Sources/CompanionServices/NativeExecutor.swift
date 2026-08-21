import CompanionCore
import Foundation

/// Native specialist executor: loop over ChatProvider with tool execution and approval gates.
/// All tool execution routes through this single entry point.
public struct NativeExecutor: Executor, Sendable {
    public var descriptor: ExecutorDescriptor

    private let chatProvider: any ChatProvider
    private let toolRunner: NativeToolRunner
    private let config: Config
    private let approvals: any ApprovalsProvider
    private let maxIterations = 10

    public init(
        descriptor: ExecutorDescriptor,
        chatProvider: any ChatProvider,
        config: Config,
        approvals: any ApprovalsProvider
    ) {
        self.descriptor = descriptor
        self.chatProvider = chatProvider
        self.toolRunner = NativeToolRunner(workdir: config.workdir)
        self.config = config
        self.approvals = approvals
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
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments)

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
            var toolCallId = ""

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

                    case .toolCall(let id, let name, let arguments):
                        // Real tool call from provider (not delegate)
                        isToolCall = true
                        toolCallId = id
                        toolName = name
                        toolArgs = arguments
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
                // Ask for approval through Approvals actor
                let requestId = UUID().uuidString
                let approval = ApprovalRequest(
                    requestId: requestId,
                    toolName: toolName,
                    summary: "Tool requires user approval",
                    inputJSON: toolArgs)

                events.yield(.approvalRequested(approval))

                // Wait for approval response (auto-deny after 120s per Approvals spec)
                let response = await approvals.request(approval)
                approved = response.approved
            }

            // Execute tool (may fail silently if not approved)
            let toolResult = try await executeToolSafely(
                tool: toolName,
                arguments: parseToolArguments(toolArgs),
                approved: approved || !approvalNeeded)

            events.yield(.stepFinished(tool: toolName, ok: toolResult.ok))

            // Both the request and its answer go back, carrying the call id:
            // a tool message without its assistant call is rejected.
            let call = ToolCallRef(
                id: toolCallId, name: toolName, arguments: toolArgs)
            history.append(Turn(role: .assistant, content: "", toolCalls: [call]))
            history.append(Turn(
                role: .tool,
                content: toolResult.output,
                toolCallID: toolCallId))
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
