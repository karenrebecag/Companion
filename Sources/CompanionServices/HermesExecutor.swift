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

    public init(
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        providerArgs: [String] = []
    ) {
        self.workdir = workdir
        self.executablePath = executablePath
        self.processLauncher = processLauncher
        self.providerArgs = providerArgs

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

        let prompt = Escalation.executorRole + "\n\n" + Escalation.jobPrompt(
            Handoff(goal: job.goal, context: job.context),
            workdir: workdir,
            desktop: NSHomeDirectory() + "/Desktop",
            attachments: job.attachments)

        guard let handle = await processLauncher.launch(
            executable: executablePath,
            arguments: ["chat", "-Q"] + providerArgs + ["-q", prompt],
            cwd: workdir
        ) else {
            Log.app("executor: hermes no arrancó en \(executablePath)")
            return JobResult(output: "", isError: true)
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
        return JobResult(output: trimmed, isError: trimmed.isEmpty)
    }
}
