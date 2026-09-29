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
    /// Read per job, like memory: a skill saved this turn is in the next
    /// job's catalog. Falls back to the config snapshot.
    private let skillsSource: (@Sendable () -> String)?
    private let maxIterations = 10

    public init(
        descriptor: ExecutorDescriptor,
        chatProvider: any ChatProvider,
        config: Config,
        approvals: any ApprovalsProvider,
        webSearch: (any WebSearching)? = nil,
        skills: SkillsLocation? = nil,
        skillsSource: (@Sendable () -> String)? = nil,
        documents: (any DocumentRendering)? = nil,
        sheets: (any SpreadsheetDriving)? = nil
    ) {
        self.descriptor = descriptor
        self.chatProvider = chatProvider
        self.toolRunner = NativeToolRunner(
            workdir: config.workdir, webSearch: webSearch, language: config.language,
            skills: skills, documents: documents, sheets: sheets)
        self.config = config
        self.approvals = approvals
        self.skillsSource = skillsSource
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
            attachments: job.attachments, language: config.language,
            skills: skillsSource?() ?? config.skills)

        // System message with executor role (once)
        let systemMessage = Turn(
            role: .system,
            content: Escalation.executorRole(config.language))

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

            var calls: [ToolCallRef] = []

            // Consume stream
            do {
                for try await delta in stream {
                    try Task.checkCancellation()

                    switch delta {
                    case .text(let text):
                        accumulatedOutput += text
                    case .handoff:
                        // The specialist does not delegate; a handoff here
                        // is a model calling a tool it was not offered.
                        Log.app("native: ignoring delegate call from the specialist")
                    case .toolCalls(let round):
                        calls += round
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return JobResult(output: accumulatedOutput, isError: true)
            }

            // If model returned text and no tool call, we're done
            if calls.isEmpty {
                return JobResult(output: accumulatedOutput, isError: false)
            }

            // One assistant turn carries every call of the round; each answer
            // follows with its own id (the provider rejects a round with a
            // missing answer). Runs in index order, deduplicated: the same
            // tool with the same arguments runs once and answers twice
            // (`routing_dedupe`, spec 24 §5).
            history.append(Turn(role: .assistant, content: "", toolCalls: calls))
            var answered: [String: ToolResult] = [:]
            for call in calls {
                try Task.checkCancellation()
                let key = Self.dedupeKey(call)
                let result: ToolResult
                if let repeated = answered[key] {
                    result = repeated
                } else {
                    result = try await perform(call, events: events)
                    answered[key] = result
                }
                history.append(Turn(
                    role: .tool, content: result.output, toolCallID: call.id))
            }
        }

        // Hit iteration limit
        return JobResult(
            output: accumulatedOutput,
            isError: true)
    }

    // MARK: - Helpers

    /// One call: arguments repaired or refused, approval asked or remembered,
    /// the tool run through the single entry point, events for the card.
    private func perform(
        _ call: ToolCallRef, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> ToolResult {
        let toolName = call.name
        // Never `[:]` on a parse failure: the model must see what it sent
        // to be able to correct it (OpenAI: "validate the arguments").
        guard let arguments = ToolArguments.parse(call.arguments) else {
            return ToolResult(
                ok: false,
                output: "invalid_args: could not parse arguments: \(call.arguments)")
        }
        events.yield(.stepStarted(tool: toolName, summary: "Executing \(toolName)"))

        let approvalNeeded = riskLevel(tool: toolName) == .requiresApproval
        var approved = !approvalNeeded
        var runArguments = arguments
        if approvalNeeded {
            // A sheet write runs the arguments the sheet showed, workbook included.
            let shown = await toolRunner.approvalArguments(tool: toolName, json: call.arguments)
            guard let bound = Self.boundArguments(shown: shown, original: call.arguments, parsed: arguments) else {
                return ToolResult(ok: false, output: "denied: the approved arguments could not be read, so nothing ran")
            }
            runArguments = bound
            let approval = ApprovalRequest(
                requestId: UUID().uuidString,
                toolName: toolName,
                summary: "Tool requires user approval",
                inputJSON: shown)
            // A decision the session already took answers without the sheet
            // (3B.2); otherwise wait (auto-deny per ApprovalTiming).
            if let decision = await approvals.remembered(approval) {
                events.yield(.approvalRemembered(tool: toolName, approved: decision))
                approved = decision
            } else {
                events.yield(.approvalRequested(approval))
                approved = await approvals.request(approval).approved
            }
            if !approved { events.yield(.approvalDenied(tool: toolName)) }
        }

        // A tool that throws (real I/O failure) is one failed step the model
        // reads about, not a lost round: the calls before it already ran.
        let toolResult: ToolResult
        do {
            toolResult = try await executeToolSafely(
                tool: toolName, arguments: runArguments, approved: approved)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            toolResult = ToolResult(ok: false, output: "tool failed: \(error)")
        }
        events.yield(.stepFinished(tool: toolName, ok: toolResult.ok))
        // Straight to the interface. It is not appended to the turn, so the
        // model never sees the payload it would otherwise retype.
        if let card = toolResult.card { events.yield(.card(card)) }
        return toolResult
    }

    /// What runs is what the sheet showed; if that JSON cannot be read there is
    /// nothing approved to run, so it is a denial and never empty arguments.
    static func boundArguments(shown: String, original: String, parsed: [String: Any]) -> [String: Any]? {
        shown == original ? parsed : ToolArguments.parse(shown)
    }

    /// Same tool, same arguments once canonicalised (sorted keys, no
    /// whitespace) — one intent, however the model spelled it.
    static func dedupeKey(_ call: ToolCallRef) -> String {
        guard let object = ToolArguments.parse(call.arguments) else {
            return call.name + "\u{0}" + call.arguments
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys])
            return call.name + "\u{0}" + (String(data: data, encoding: .utf8) ?? call.arguments)
        } catch {
            return call.name + "\u{0}" + call.arguments
        }
    }

    private func nativeToolSpecs() -> [ToolSpec] {
        // Only what can actually run. The catalog is not the offer.
        toolRunner.availableTools.map { $0.spec }
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
}
