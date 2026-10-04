import CompanionCore
import Foundation

/// Ejecutor sobre `claude -p` con cable NDJSON bidireccional.
/// El proceso persiste entre encargos (el hilo del especialista es UNA
/// conversación); solo se rearma si murió. El rol viaja una vez, al lanzar.
/// final + @unchecked: el estado del handle lo toca un solo encargo a la vez
/// porque JobQueue serializa; el lock cubre el borde con cancelaciones.
package final class ClaudeCodeExecutor: Executor, @unchecked Sendable {
    package let descriptor: ExecutorDescriptor

    private let workdir: String
    private let executablePath: String
    private let processLauncher: any ProcessLauncher
    private let approvals: any ApprovalsProvider
    private let sessions: (any ExecutorSessionStoring)?
    /// The role and the job prompt are read by the specialist: they travel
    /// in the language the user is being answered in, not in the app's.
    private let language: AppLanguage
    /// The skills catalog for the job prompt (Wave 11a); Claude Code reads
    /// the paths with its own Read.
    private let skills: @Sendable () -> String
    private let lock = NSLock()
    private var handle: (any ProcessHandle)?
    private var sessionId: String?
    /// Whether the live process was launched resuming a stored thread, and
    /// whether it ever said hello. A resume the CLI rejects looks exactly like
    /// this: a process that starts, prints nothing and dies.
    private var resumedFromStore = false
    private var sawInitialized = false
    /// The store generation the process and `sessionId` belong to. The
    /// provider caches this executor for the app's life, so a clear that
    /// moved the generation must be noticed here, not by a new instance.
    private var generation: Int

    package init(
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider,
        modelArgs: [String] = ["--model", "sonnet"],
        sessions: (any ExecutorSessionStoring)? = nil,
        language: AppLanguage = .en,
        skills: @escaping @Sendable () -> String = { "" }
    ) {
        self.workdir = workdir
        self.executablePath = executablePath
        self.processLauncher = processLauncher
        self.approvals = approvals
        self.sessions = sessions
        self.language = language
        self.skills = skills
        self.generation = sessions?.currentGeneration() ?? 0

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "claude-code"),
            shortName: "claude",
            title: "Claude Code",
            kind: .detectedCLI,
            modelArgs: modelArgs
        )
    }

    package func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()
        await forgetIfCleared()
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
        var args = ["-p", batchPrompt(job), "--output-format", "text"] + Self.permissionArgs
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

            for event in AgentStreamCodec.events(line) {
                switch event {
                case .initialized(let sid):
                    lock.withLock {
                        sessionId = sid
                        sawInitialized = true
                    }
                    // The thread the CLI actually opened wins over the one we
                    // asked for: resuming yesterday's id tomorrow needs this.
                    sessions?.set(sid, for: sessionKey)

                case .toolUse(let id, let name, let detail):
                    events.yield(.stepStarted(tool: name, summary: detail, id: id))

                case .toolResult(let id, let isError):
                    // The tool name is not on the wire here; the id pairs the end.
                    events.yield(.stepFinished(tool: "", ok: !isError, id: id))

                case .thought(let text):
                    events.yield(.thought(text))

                case .approval(let approval):
                    // Wave 16b: in auto mode a question means the classifier was
                    // not sure. Karen asked for no permission sheets, so the
                    // safe answer is no, said to the specialist, never to her.
                    // Tool name only in the log: the input can hold anything.
                    Log.app("executor: auto-denied \(approval.toolName)")
                    if let control = AgentStreamCodec.controlResponse(
                        requestId: approval.requestId,
                        allow: false,
                        inputJSON: approval.inputJSON,
                        message: Self.autoDeniedMessage
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

    // MARK: - Permisos (Wave 16b)

    /// Never without asking — and nobody is asked any more: root, pushing
    /// code, wiping the disk or home, piping the web into a shell. AppleScript
    /// drives the screen, which is the parent's hands' job since 15g/16a.
    /// Claude Code splits `bash -c`, `;`/`&&` chains and full paths before
    /// matching (verified 2026-09-25 against 2.1.282), so these prefixes hold
    /// against wrappers; the variants cover other spellings. Not covered, by
    /// design of any list: a script written then run, `python -c`, base64.
    /// That residue is the auto classifier's, which Karen accepted.
    static let deniedTools = [
        "Bash(sudo *)", "Bash(git push*)",
        "Bash(rm -rf /*)", "Bash(rm -rf ~*)", "Bash(rm -fr /*)", "Bash(rm -fr ~*)",
        "Bash(rm -rf $HOME*)",
        "Bash(curl * | sh*)", "Bash(curl * | bash*)", "Bash(wget * | sh*)", "Bash(wget * | bash*)",
        "Bash(osascript *)",
    ]

    /// `auto`: Claude Code's classifier approves what is safe and refuses
    /// what is risky, without a sheet (Karen, 2026-09-25). Web reads stay
    /// explicitly allowed: a search is never a question.
    /// Each pattern is its own argument: they contain spaces, and the CLI
    /// also splits a single value on spaces (verified 2026-09-25, 2.1.282).
    static let permissionArgs = [
        "--permission-mode", "auto",
        "--allowedTools", "WebSearch,WebFetch",
        "--disallowedTools",
    ] + deniedTools

    static let autoDeniedMessage =
        "Not allowed without asking, and this session does not ask. Find a way that "
        + "does not need it, or say what you could not do."

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
            // Lo que el modo auto aún pregunte llega como can_use_tool por
            // este cable, y se niega solo (16b).
            "--permission-prompt-tool", "stdio",
        ] + Self.permissionArgs
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

    /// A clear erased the thread this process and `sessionId` still hold.
    /// Ending the process and dropping the id makes the next launch start
    /// clean instead of resuming an erased task.
    private func forgetIfCleared() async {
        guard let current = sessions?.currentGeneration() else { return }
        let stale = lock.withLock { () -> (any ProcessHandle)? in
            guard current != generation else { return nil }
            generation = current
            sessionId = nil
            resumedFromStore = false
            sawInitialized = false
            defer { handle = nil }
            return handle
        }
        await stale?.terminate()
    }

    private func dropProcess() async {
        let dead = lock.withLock { () -> (any ProcessHandle)? in
            defer { handle = nil }
            return handle
        }
        await dead?.terminate()
    }

    /// The store is the durable truth. The in-memory id covers only a run
    /// with no store wired (tests, and the native-only composition): with a
    /// store, a nil answer means the thread was cleared or never saved, and
    /// the id in memory may be the one a clear just erased.
    private func effectiveSession() -> String? {
        let saved = sessions.map { $0.session(for: sessionKey) }
            ?? lock.withLock { sessionId }
        return ExecutorSessions.effective(saved, for: descriptor.id)
    }

    private func batchPrompt(_ job: JobRequest) -> String {
        Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments, language: language, skills: skills())
    }

    private var sessionKey: ExecutorSessionKey {
        ExecutorSessionKey(executor: descriptor.id, workdir: workdir)
    }

    private func buildUserTurn(_ job: JobRequest) -> String {
        let prompt = Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments, language: language, skills: skills())
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
