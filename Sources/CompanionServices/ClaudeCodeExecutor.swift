import CompanionCore
import Foundation

/// Ejecutor sobre `claude -p` con cable NDJSON bidireccional.
/// El proceso persiste entre encargos (el hilo del especialista es UNA
/// conversación); solo se rearma si murió. El rol viaja una vez, al lanzar.
/// final + @unchecked: el estado del handle lo toca un solo encargo a la vez
/// porque JobQueue serializa; el lock cubre el borde con cancelaciones.
public final class ClaudeCodeExecutor: Executor, @unchecked Sendable {
    public let descriptor: ExecutorDescriptor

    private let workdir: String
    private let executablePath: String
    private let processLauncher: any ProcessLauncher
    private let approvals: any ApprovalsProvider
    private let lock = NSLock()
    private var handle: (any ProcessHandle)?
    private var sessionId: String?

    public init(
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider
    ) {
        self.workdir = workdir
        self.executablePath = executablePath
        self.processLauncher = processLauncher
        self.approvals = approvals

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "claude-code"),
            shortName: "claude",
            title: "Claude Code",
            kind: .detectedCLI,
            modelArgs: ["--model", "opus"]
        )
    }

    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()
        let handle = try await ensureProcessRunning()
        let turn = buildUserTurn(job)
        do {
            try await handle.sendLine(turn)
        } catch {
            // El cable murió entre encargos sin avisar: un rearme y de nuevo.
            await dropProcess()
            let fresh = try await ensureProcessRunning()
            try await fresh.sendLine(turn)
            return try await consume(fresh, events: events)
        }
        return try await consume(handle, events: events)
    }

    private func consume(
        _ handle: any ProcessHandle,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        while let line = await handle.readLine() {
            if Task.isCancelled { break }

            switch AgentStreamCodec.parse(line) {
            case .initialized(let sid):
                lock.withLock { sessionId = sid }

            case .toolUse(let name, let detail):
                events.yield(.stepStarted(tool: name, summary: detail))
                events.yield(.stepFinished(tool: name, ok: true))

            case .thought(let text):
                events.yield(.thought(text))

            case .approval(let approval):
                events.yield(.approvalRequested(approval))
                let response = await approvals.request(approval)
                let message = response.approved ? "" : "La usuaria no lo autorizó."
                if let control = AgentStreamCodec.controlResponse(
                    requestId: approval.requestId,
                    allow: response.approved,
                    inputJSON: approval.inputJSON,
                    message: message
                ) {
                    try await handle.sendLine(control)
                }

            case .result(let text, let isError):
                return JobResult(
                    output: text, isError: isError,
                    sessionId: lock.withLock { sessionId })

            case .ignored:
                continue
            }
        }

        // Presupuesto agotado o cancelación: el proceso puede seguir a media
        // tarea — se mata para que el siguiente encargo arranque limpio.
        if Task.isCancelled {
            await dropProcess()
            throw CancellationError()
        }
        // El stream cerró sin result: el proceso murió a media tarea.
        await dropProcess()
        return JobResult(
            output: "", isError: true, sessionId: lock.withLock { sessionId })
    }

    // MARK: - Proceso

    private func ensureProcessRunning() async throws -> any ProcessHandle {
        if let live = lock.withLock({ handle }), live.isRunning {
            return live
        }

        var args = [
            "-p",
            "--input-format", "stream-json",
            // Sin --verbose, stream-json en modo -p no emite los eventos.
            "--output-format", "stream-json", "--verbose",
            // acceptEdits: los archivos pasan sin preguntar; lo demás llega
            // como can_use_tool por el mismo cable gracias a stdio.
            "--permission-mode", "acceptEdits",
            // Leer la web no es destructivo, y cada WebFetch con permiso
            // manual convertía una búsqueda en 5 minutos de diálogo.
            "--allowedTools", "WebSearch,WebFetch",
            "--permission-prompt-tool", "stdio",
        ]
        args += descriptor.modelArgs
        args += ["--append-system-prompt", Escalation.executorRole]

        guard let fresh = await processLauncher.launch(
            executable: executablePath,
            arguments: args,
            cwd: workdir
        ) else {
            Log.app("executor: claude no arrancó en \(executablePath)")
            throw ExecutorError.processLaunchFailed
        }

        lock.withLock { handle = fresh }
        return fresh
    }

    private func dropProcess() async {
        let dead = lock.withLock { () -> (any ProcessHandle)? in
            defer { handle = nil }
            return handle
        }
        await dead?.terminate()
    }

    private func buildUserTurn(_ job: JobRequest) -> String {
        let prompt = Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments)
        return AgentStreamCodec.userTurn(prompt) ?? ""
    }
}

enum ExecutorError: Error {
    case processLaunchFailed
    case invalidTranscript
}
