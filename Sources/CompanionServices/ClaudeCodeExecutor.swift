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
    private let sessions: (any ExecutorSessionStoring)?
    /// The role and the job prompt are read by the specialist: they travel
    /// in the language the user is being answered in, not in the app's.
    private let language: AppLanguage
    private let lock = NSLock()
    private var handle: (any ProcessHandle)?
    private var sessionId: String?
    /// Whether the live process was launched resuming a stored thread, and
    /// whether it ever said hello. A resume the CLI rejects looks exactly like
    /// this: a process that starts, prints nothing and dies.
    private var resumedFromStore = false
    private var sawInitialized = false

    public init(
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider,
        modelArgs: [String] = ["--model", "sonnet"],
        sessions: (any ExecutorSessionStoring)? = nil,
        language: AppLanguage = .en
    ) {
        self.workdir = workdir
        self.executablePath = executablePath
        self.processLauncher = processLauncher
        self.approvals = approvals
        self.sessions = sessions
        self.language = language

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "claude-code"),
            shortName: "claude",
            title: "Claude Code",
            kind: .detectedCLI,
            modelArgs: modelArgs
        )
    }

    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()
        do {
            return try await attempt(job, events: events)
        } catch ExecutorError.staleSession {
            // The stored thread is gone from the CLI's side. Forget it and
            // start clean once — never twice: the second attempt carries no
            // id, so it cannot raise this again.
            Log.app("executor: stored session rejected; starting clean")
            sessions?.set(nil, for: sessionKey)
            do {
                return try await attempt(job, events: events)
            } catch ExecutorError.cableDied {
                return try await fallbackToBatch(job, events: events)
            }
        } catch ExecutorError.cableDied {
            return try await fallbackToBatch(job, events: events)
        }
    }

    /// The stdio cable died with work already done. The prototype fell back to
    /// a batch subprocess rather than losing the job; resuming the session is
    /// what keeps the half-finished work. One try only, and never after a
    /// cancellation — the user said stop.
    private func fallbackToBatch(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()
        Log.app("executor: cable died; picking the job up in batch")
        events.yield(.thought(Escalation.fallbackNotice(language)))

        // Same posture as the streaming path, and as the prototype's batch:
        // without these the fallback runs on default permissions AND has no
        // way to ask for more (there is no --permission-prompt-tool here), so
        // the specialist silently loses the disk and answers "I found nothing"
        // to questions that do have an answer.
        var args = [
            "-p", batchPrompt(job), "--output-format", "text",
            "--permission-mode", "acceptEdits",
            "--allowedTools", "WebSearch,WebFetch",
        ]
        args += descriptor.modelArgs
        args += ["--append-system-prompt", Escalation.executorRole(language)]
        if let resume = effectiveSession() { args += ["--resume", resume] }

        guard let handle = await processLauncher.launch(
            executable: executablePath, arguments: args, cwd: workdir
        ) else {
            Log.app("executor: the batch did not start either")
            throw ExecutorError.processLaunchFailed
        }
        var output = ""
        while let line = await handle.readLine() {
            if Task.isCancelled { break }
            output += line + "\n"
        }
        await handle.terminate()
        if Task.isCancelled { throw CancellationError() }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ExecutorError.emptyResult }
        return JobResult(
            output: trimmed, isError: false,
            sessionId: lock.withLock { sessionId })
    }

    private func attempt(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
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
                lock.withLock {
                    sessionId = sid
                    sawInitialized = true
                }
                // The thread the CLI actually opened wins over the one we
                // asked for: resuming yesterday's id tomorrow needs this.
                sessions?.set(sid, for: sessionKey)

            case .toolUse(let name, let detail):
                events.yield(.stepStarted(tool: name, summary: detail))
                events.yield(.stepFinished(tool: name, ok: true))

            case .thought(let text):
                events.yield(.thought(text))

            case .approval(let approval):
                events.yield(.approvalRequested(approval))
                let response = await approvals.request(approval)
                let message = response.approved ? "" : deniedMessage
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
        let (resumed, greeted) = lock.withLock {
            (resumedFromStore, sawInitialized)
        }
        await dropProcess()
        if resumed && !greeted { throw ExecutorError.staleSession }
        throw ExecutorError.cableDied
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
        args += ["--append-system-prompt", Escalation.executorRole(language)]

        let stored = effectiveSession()
        if let stored { args += ["--resume", stored] }

        guard let fresh = await processLauncher.launch(
            executable: executablePath,
            arguments: args,
            cwd: workdir
        ) else {
            Log.app("executor: claude did not start at \(executablePath)")
            throw ExecutorError.processLaunchFailed
        }

        lock.withLock {
            handle = fresh
            resumedFromStore = stored != nil
            sawInitialized = false
        }
        return fresh
    }

    private func dropProcess() async {
        let dead = lock.withLock { () -> (any ProcessHandle)? in
            defer { handle = nil }
            return handle
        }
        await dead?.terminate()
    }

    /// The store is the durable truth; the in-memory id covers a run with no
    /// store wired (tests, and the native-only composition).
    private func effectiveSession() -> String? {
        let saved = sessions?.session(for: sessionKey)
            ?? lock.withLock { sessionId }
        return ExecutorSessions.effective(saved, for: descriptor.id)
    }

    private func batchPrompt(_ job: JobRequest) -> String {
        Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments, language: language)
    }

    /// Read by the specialist, so it follows the answer language.
    private var deniedMessage: String {
        language == .en
            ? "The user did not allow it."
            : "La usuaria no lo autorizó."
    }

    private var sessionKey: ExecutorSessionKey {
        ExecutorSessionKey(executor: descriptor.id, workdir: workdir)
    }

    private func buildUserTurn(_ job: JobRequest) -> String {
        let prompt = Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments, language: language)
        return AgentStreamCodec.userTurn(prompt) ?? ""
    }
}

enum ExecutorError: Error {
    case processLaunchFailed
    case invalidTranscript
    /// Launched with a stored `--resume` the CLI would not take. Internal:
    /// `run` swallows it by retrying clean, so it never reaches the user.
    case staleSession
    /// The stdio stream closed without a result: the process died mid-task.
    /// Internal too — `run` answers it with the batch fallback.
    case cableDied
    /// The batch ran to the end and said nothing. Reaches the user, because
    /// by then there is no route left to try.
    case emptyResult
}
