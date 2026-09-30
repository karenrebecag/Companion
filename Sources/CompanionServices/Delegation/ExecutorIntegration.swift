import CompanionCore
import Foundation

/// Fábrica de ejecutores CLI. La ruta del binario llega ya resuelta por el
/// probe: aquí no se adivinan rutas.
public enum ExecutorFactory {
    public static func createExecutor(
        descriptor: ExecutorDescriptor,
        workdir: String,
        executablePath: String,
        processLauncher: any ProcessLauncher,
        approvals: any ApprovalsProvider,
        sessions: (any ExecutorSessionStoring)? = nil,
        skills: @escaping @Sendable () -> String = { "" }
    ) -> (any Executor)? {
        // Prefijo, no igualdad: cada tier de claude y cada proveedor de
        // hermes es una fila propia (claude-code:opus, hermes:copilot).
        let id = descriptor.id.rawValue
        if id.hasPrefix("claude-code") {
            return ClaudeCodeExecutor(
                workdir: workdir,
                executablePath: executablePath,
                processLauncher: processLauncher,
                approvals: approvals,
                modelArgs: descriptor.modelArgs,
                sessions: sessions,
                skills: skills
            )
        }
        if id.hasPrefix("hermes") {
            return HermesExecutor(
                workdir: workdir,
                executablePath: executablePath,
                processLauncher: processLauncher,
                providerArgs: descriptor.modelArgs,
                sessions: sessions,
                skills: skills
            )
        }
        // El nativo se construye en el composition root, no aquí.
        return nil
    }
}

/// Lanzador real: subprocesos de verdad con pipes, cada uno en SU grupo de
/// proceso. El grupo importa porque un especialista arranca ayudantes propios:
/// senalar solo al hijo directo los deja vivos y launchd los adopta.
public struct RealProcessLauncher: ProcessLauncher {
    private let registry: ProcessRegistry

    public init(registry: ProcessRegistry = .shared) {
        self.registry = registry
    }

    public func launch(
        executable: String,
        arguments: [String],
        cwd: String?
    ) async -> (any ProcessHandle)? {
        guard let group = ProcessGroupRunner.spawnSession(
            executable: executable, arguments: arguments, cwd: cwd,
            registry: registry)
        else { return nil }
        return RealProcessHandle(group: group)
    }
}

/// El readabilityHandler corre en una cola interna de FileHandle; el lock
/// cubre la carrera entre el último feed y el flush de EOF.
private final class LineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = LineBuffer()
    func feed(_ data: Data) -> [String] { lock.withLock { buffer.feed(data) } }
    func flush() -> String? { lock.withLock { buffer.flush() } }
}

/// Handle real: stdout entra por readabilityHandler a un buffer de líneas y
/// sale como AsyncStream — readLine entrega LÍNEAS, nunca bloques del pipe.
/// final + @unchecked: Process/Pipe no son Sendable y el handle lo consume
/// un solo task (el del ejecutor), en serie.
private final class RealProcessHandle: ProcessHandle, @unchecked Sendable {
    private let group: GroupProcess
    /// Un solo consumidor por contrato; nadie más toca este iterador.
    private var iterator: AsyncStream<String>.Iterator

    init(group: GroupProcess) {
        self.group = group
        let (stream, sink) = AsyncStream<String>.makeStream()
        self.iterator = stream.makeAsyncIterator()

        let accumulator = LineAccumulator()
        group.stdout.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                // EOF: entregar el resto y cerrar el stream.
                if let rest = accumulator.flush() { sink.yield(rest) }
                sink.finish()
                fileHandle.readabilityHandler = nil
                return
            }
            for line in accumulator.feed(data) { sink.yield(line) }
        }
    }

    func sendLine(_ line: String) async throws {
        guard let data = (line + "\n").data(using: .utf8) else {
            throw ProcessError.invalidEncoding
        }
        do {
            try group.stdin.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw ProcessError.writeFailed
        }
    }

    func readLine() async -> String? {
        await iterator.next()
    }

    /// Cierra stdin primero — muchos CLIs salen solos al ver EOF — y solo
    /// entonces mata al grupo con la escalera SIGTERM/SIGKILL.
    func terminate() async {
        do {
            try group.stdin.fileHandleForWriting.close()
        } catch {
            Log.app("process: stdin was already closed")
        }
        group.terminate()
    }

    var isRunning: Bool {
        group.isRunning
    }
}

enum ProcessError: Error {
    case invalidEncoding
    case writeFailed
}
