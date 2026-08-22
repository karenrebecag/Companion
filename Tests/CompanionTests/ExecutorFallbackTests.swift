import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El cable stdio que muere a media tarea. Deuda anotada al cerrar Wave 7: el
// prototipo caía a un subproceso batch conservando la sesión; el rebuild
// reportaba el encargo como fallido y el trabajo ya hecho se perdía.

@Test @MainActor func executorFallbackTests() throws {
    try testDeadCableFinishesInBatch()
    try testFallbackNarratesTheDetour()
    try testBatchFailureStopsThere()
    try testCancellationNeverFallsBack()
}

private let key = ExecutorSessionKey(
    executor: ExecutorID(rawValue: "claude-code"), workdir: "/tmp/test")

private func store() -> FileExecutorSessionStore {
    FileExecutorSessionStore(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-fb-\(UUID().uuidString).json"))
}

/// El cable cae con el encargo a medias: se retoma por batch, reanudando la
/// sesión, y el encargo TERMINA.
@MainActor func testDeadCableFinishesInBatch() throws {
    let launcher = StubProcessLauncher()
    // Arrancó, dijo quién era, empezó a trabajar... y el pipe murió.
    launcher.setNextTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-viva"}"#,
        #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{}}]}}"#,
    ])
    launcher.setNextTranscript(["El archivo quedó en tu escritorio."])
    let sessions = store()

    let result = try runAsync {
        let executor = makeFallbackClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "crear prueba1.md", context: ""),
            events: sink)
    }

    expectEq(launcher.launched.count, 2, "cable muerto: un solo reintento")
    let batch = launcher.launched[1].arguments
    expect(!batch.contains("--input-format"),
           "cable muerto: el reintento es batch, no otro cable stdio")
    expect(batch.contains("--resume") && batch.contains("s-viva"),
           "cable muerto: el batch retoma la sesión, no empieza de cero")
    expect(batch.contains { $0.contains("crear prueba1.md") },
           "cable muerto: el encargo viaja como argumento")
    expectEq(result.output, "El archivo quedó en tu escritorio.",
             "cable muerto: el encargo termina de verdad")
    expect(!result.isError, "cable muerto: terminar por la vía lenta no es fallar")
}

/// Nada silencioso: el hilo dice que hubo desvío.
@MainActor func testFallbackNarratesTheDetour() throws {
    let launcher = StubProcessLauncher()
    launcher.setNextTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-1"}"#,
    ])
    launcher.setNextTranscript(["hecho"])
    let sessions = store()

    let events = try runAsync {
        let executor = makeFallbackClaude(launcher: launcher, sessions: sessions)
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let collector = Task {
            var seen: [JobEvent] = []
            for await event in stream { seen.append(event) }
            return seen
        }
        _ = try await executor.run(
            JobRequest(id: "j1", goal: "algo", context: ""), events: sink)
        sink.finish()
        return await collector.value
    }

    expect(events.contains {
        if case .thought(let text) = $0 { return text == Escalation.fallbackNotice() }
        return false
    }, "desvío: el hilo cuenta que se cayó el canal y se retomó por otra vía")
}

/// El batch también falla: fallo honesto, sin bucle de reintentos.
@MainActor func testBatchFailureStopsThere() throws {
    let launcher = StubProcessLauncher()
    launcher.setNextTranscript([])
    launcher.setNextTranscript([])
    let sessions = store()

    let result = try runAsync {
        let executor = makeFallbackClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "lo imposible", context: ""),
            events: sink)
    }

    expectEq(launcher.launched.count, 2, "batch fallido: no hay tercer intento")
    expect(result.isError, "batch fallido: se reporta como fallo")
}

/// Cancelar es cancelar: no se relanza nada por detrás.
@MainActor func testCancellationNeverFallsBack() throws {
    let launcher = HangingLauncher()
    let sessions = store()
    let cancelled = try runAsync { () -> Bool in
        let executor = ClaudeCodeExecutor(
            workdir: "/tmp/test", executablePath: "/stub/bin/claude",
            processLauncher: launcher,
            approvals: InstantApprovals(approved: false),
            sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        let task = Task {
            try await executor.run(
                JobRequest(id: "j1", goal: "algo largo", context: ""),
                events: sink)
        }
        try? await Task.sleep(for: .milliseconds(40))
        task.cancel()
        do {
            _ = try await task.value
            return false
        } catch {
            return error is CancellationError
        }
    }

    expect(cancelled, "cancelar: el encargo termina cancelado, no en batch")
    expectEq(launcher.launches, 1, "cancelar: no se lanza ningún proceso más")
}

// MARK: - Helpers

private func makeFallbackClaude(
    launcher: StubProcessLauncher, sessions: any ExecutorSessionStoring
) -> ClaudeCodeExecutor {
    ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false),
        sessions: sessions)
}

/// Un proceso que no contesta hasta que cancelan: así se ve un encargo largo.
final class HangingLauncher: ProcessLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var launches: Int { lock.withLock { count } }

    func launch(
        executable: String, arguments: [String], cwd: String?
    ) async -> (any ProcessHandle)? {
        lock.withLock { count += 1 }
        return HangingProcessHandle()
    }
}

final class HangingProcessHandle: ProcessHandle, @unchecked Sendable {
    func sendLine(_ line: String) async throws {}

    func readLine() async -> String? {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    func terminate() async {}
    var isRunning: Bool { true }
}
