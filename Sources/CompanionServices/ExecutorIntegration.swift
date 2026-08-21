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
        approvals: any ApprovalsProvider
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
                modelArgs: descriptor.modelArgs
            )
        }
        if id.hasPrefix("hermes") {
            return HermesExecutor(
                workdir: workdir,
                executablePath: executablePath,
                processLauncher: processLauncher,
                providerArgs: descriptor.modelArgs
            )
        }
        // El nativo se construye en el composition root, no aquí.
        return nil
    }
}

/// Lanzador real: subprocesos de verdad con pipes.
public struct RealProcessLauncher: ProcessLauncher {
    public init() {}

    public func launch(
        executable: String,
        arguments: [String],
        cwd: String?
    ) async -> (any ProcessHandle)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd = cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return RealProcessHandle(process: process, stdin: inputPipe, stdout: outputPipe)
        } catch {
            Log.app("process: launch de \(executable) falló: \(error)")
            return nil
        }
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
    private let process: Process
    private let stdinPipe: Pipe
    /// Un solo consumidor por contrato; nadie más toca este iterador.
    private var iterator: AsyncStream<String>.Iterator

    init(process: Process, stdin: Pipe, stdout: Pipe) {
        self.process = process
        self.stdinPipe = stdin
        let (stream, sink) = AsyncStream<String>.makeStream()
        self.iterator = stream.makeAsyncIterator()

        let accumulator = LineAccumulator()
        stdout.fileHandleForReading.readabilityHandler = { fileHandle in
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
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw ProcessError.writeFailed
        }
    }

    func readLine() async -> String? {
        await iterator.next()
    }

    func terminate() async {
        do {
            try stdinPipe.fileHandleForWriting.close()
        } catch {
            // Cerrar un pipe ya cerrado tira; el proceso muere igual abajo.
            Log.app("process: stdin ya estaba cerrado")
        }
        if process.isRunning { process.terminate() }
    }

    var isRunning: Bool {
        process.isRunning
    }
}

enum ProcessError: Error {
    case invalidEncoding
    case writeFailed
}
