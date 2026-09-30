import CompanionCore
import Foundation

/// Ejecutor sobre `hermes chat -Q`: batch, sin sesión persistente.
/// Hermes no tiene modo stdio — el prompt viaja como argumento -q (por stdin
/// se quedaba esperando para siempre) y el rol va pegado al prompt porque
/// tampoco hay flag de system prompt.
public struct HermesExecutor: Executor, Sendable {
    public var descriptor: ExecutorDescriptor

    private let workdir: String
    private let executablePath: String
    private let processLauncher: any ProcessLauncher
    private let providerArgs: [String]
    private let sessions: (any ExecutorSessionStoring)?
    /// The skills catalog for the job prompt (Wave 11a).
    private let skills: @Sendable () -> String
    private let language: AppLanguage

    public init(
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        providerArgs: [String] = [],
        sessions: (any ExecutorSessionStoring)? = nil,
        language: AppLanguage = .en,
        skills: @escaping @Sendable () -> String = { "" }
    ) {
        self.workdir = workdir
        self.executablePath = executablePath
        self.processLauncher = processLauncher
        self.providerArgs = providerArgs
        self.sessions = sessions
        self.skills = skills
        self.language = language

        self.descriptor = ExecutorDescriptor(
            id: ExecutorID(rawValue: "hermes"),
            shortName: "hermes",
            title: "Hermes",
            kind: .detectedCLI,
            modelArgs: []
        )
    }

    public func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try Task.checkCancellation()

        let prompt = Escalation.executorRole(language) + "\n\n"
            + Escalation.jobPrompt(
                Handoff(goal: job.goal, context: job.context),
                workdir: workdir,
                desktop: NSHomeDirectory() + "/Desktop",
                attachments: job.attachments, language: language,
                skills: skills())

        // Hermes prints its durable id on stderr, which this adapter does not
        // read; the `latest` sentinel is exactly what it exists for — resume
        // the last thread of this folder without knowing its name.
        var args = ["chat", "-Q"] + providerArgs
        if let resume = ExecutorSessions.effective(
            sessions?.session(for: sessionKey), for: descriptor.id) {
            args += ["--resume", resume]
        }

        guard let handle = await processLauncher.launch(
            executable: executablePath,
            arguments: args + ["-q", prompt],
            cwd: workdir
        ) else {
            Log.app("executor: hermes did not start at \(executablePath)")
            throw ExecutorError.processLaunchFailed
        }

        events.yield(.stepStarted(tool: "hermes", summary: "Running Hermes"))

        // Batch: todo el stdout hasta EOF es la respuesta.
        var output = ""
        while let line = await handle.readLine() {
            if Task.isCancelled { break }
            output += line + "\n"
        }

        await handle.terminate()
        if Task.isCancelled { throw CancellationError() }
        events.yield(.stepFinished(tool: "hermes", ok: true))

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw ExecutorError.emptyResult }
        sessions?.set(ExecutorSessions.latest, for: sessionKey)
        return JobResult(output: trimmed, isError: false)
    }

    private var sessionKey: ExecutorSessionKey {
        ExecutorSessionKey(executor: descriptor.id, workdir: workdir)
    }
}
