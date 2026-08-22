import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// La sesión del especialista entre arranques. Deuda anotada al cerrar Wave 7:
// `sessionId` se capturaba y jamás se reusaba, así que cada vez que la app
// abría, el especialista era amnésico — "¿en qué estábamos?" no tenía
// respuesta posible.

@Test @MainActor func executorSessionTests() throws {
    testSessionRoundTrip()
    testLatestSentinelOnlyWhereItExists()
    try testResumeFlagTravelsOnLaunch()
    try testOtherWorkdirStartsFresh()
    try testStaleSessionRetriesClean()
    try testStreamIdOverwritesTheStoredOne()
    try testHermesResumesWithTheSentinel()
}

private func tempSessionsFile() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-sessions-\(UUID().uuidString).json")
}

private let claudeKey = ExecutorSessionKey(
    executor: ExecutorID(rawValue: "claude-code"), workdir: "/tmp/test")

/// 1. Sobrevive al proceso: eso es todo lo que se le pide.
@MainActor func testSessionRoundTrip() {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }

    FileExecutorSessionStore(fileURL: url).set("s-42", for: claudeKey)
    let reopened = FileExecutorSessionStore(fileURL: url)
    expectEq(reopened.session(for: claudeKey), "s-42",
             "sesiones: el id se relee tras recrear el store")

    reopened.set(nil, for: claudeKey)
    expectEq(FileExecutorSessionStore(fileURL: url).session(for: claudeKey), nil,
             "sesiones: borrar deja el hueco vacío, no un string vacío")
}

/// 2. La cicatriz del prototipo: claude NO entiende `--resume latest`, y un
/// flag que falla se queda pegado en el store envenenando cada arranque.
@MainActor func testLatestSentinelOnlyWhereItExists() {
    let claude = ExecutorID(rawValue: "claude-code:opus")
    let hermes = ExecutorID(rawValue: "hermes:copilot")
    expectEq(ExecutorSessions.effective(ExecutorSessions.latest, for: claude), nil,
             "sentinel: con claude, `latest` significa sesión nueva")
    expectEq(ExecutorSessions.effective(ExecutorSessions.latest, for: hermes),
             ExecutorSessions.latest,
             "sentinel: hermes sí lo entiende")
    expectEq(ExecutorSessions.effective("s-1", for: claude), "s-1",
             "sentinel: un id de verdad viaja igual")
}

/// 3. Con id guardado, el proceso arranca reanudando.
@MainActor func testResumeFlagTravelsOnLaunch() throws {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let sessions = FileExecutorSessionStore(fileURL: url)
    sessions.set("s-9", for: claudeKey)
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-9"}"#,
        #"{"type":"result","result":"ok","is_error":false}"#,
    ])

    _ = try runAsync {
        let executor = makeClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "seguir", context: ""), events: sink)
    }

    let args = launcher.launched.first?.arguments ?? []
    expect(hasFlag(args, "--resume", "s-9"),
           "reanudar: el id guardado viaja como --resume")
}

/// 4. Otra carpeta es otra conversación: reanudarla sería mezclar trabajos.
@MainActor func testOtherWorkdirStartsFresh() throws {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let sessions = FileExecutorSessionStore(fileURL: url)
    sessions.set("s-9", for: ExecutorSessionKey(
        executor: ExecutorID(rawValue: "claude-code"), workdir: "/otra/carpeta"))
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([
        #"{"type":"result","result":"ok","is_error":false}"#,
    ])

    _ = try runAsync {
        let executor = makeClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "empezar", context: ""), events: sink)
    }

    let args = launcher.launched.first?.arguments ?? []
    expect(!args.contains("--resume"),
           "reanudar: la carpeta de al lado arranca limpia")
}

/// 5. Un id que el CLI ya no reconoce: se olvida y se reintenta UNA vez.
@MainActor func testStaleSessionRetriesClean() throws {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let sessions = FileExecutorSessionStore(fileURL: url)
    sessions.set("s-podrido", for: claudeKey)
    let launcher = StubProcessLauncher()
    // Primer arranque: muere sin decir nada (así se ve un --resume rechazado).
    launcher.setNextTranscript([])
    launcher.setNextTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-nueva"}"#,
        #"{"type":"result","result":"hecho","is_error":false}"#,
    ])

    let result = try runAsync {
        let executor = makeClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "seguir", context: ""), events: sink)
    }

    expectEq(launcher.launched.count, 2, "podrido: exactamente un reintento")
    expect(hasFlag(launcher.launched[0].arguments, "--resume", "s-podrido"),
           "podrido: el primer intento sí usó el id guardado")
    expect(!launcher.launched[1].arguments.contains("--resume"),
           "podrido: el reintento arranca sin el flag")
    expectEq(result.output, "hecho", "podrido: el encargo termina de verdad")
    expectEq(sessions.session(for: claudeKey), "s-nueva",
             "podrido: el id malo se borra y queda el nuevo")
}

/// 6. El id que reporta el stream manda sobre el guardado.
@MainActor func testStreamIdOverwritesTheStoredOne() throws {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let sessions = FileExecutorSessionStore(fileURL: url)
    sessions.set("s-vieja", for: claudeKey)
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-fresca"}"#,
        #"{"type":"result","result":"ok","is_error":false}"#,
    ])

    _ = try runAsync {
        let executor = makeClaude(launcher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "algo", context: ""), events: sink)
    }

    expectEq(sessions.session(for: claudeKey), "s-fresca",
             "reanudar: el id del stream pisa al guardado")
}

/// 7. Hermes no publica su id por stdout; para eso existe el sentinel.
@MainActor func testHermesResumesWithTheSentinel() throws {
    let url = tempSessionsFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let sessions = FileExecutorSessionStore(fileURL: url)
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript(["listo"])
    let key = ExecutorSessionKey(
        executor: ExecutorID(rawValue: "hermes"), workdir: "/tmp/test")

    _ = try runAsync {
        let executor = HermesExecutor(
            workdir: "/tmp/test", executablePath: "/stub/bin/hermes",
            processLauncher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j1", goal: "algo", context: ""), events: sink)
    }
    expectEq(sessions.session(for: key), ExecutorSessions.latest,
             "hermes: tras un encargo bueno queda el hilo para retomar")

    _ = try runAsync {
        let executor = HermesExecutor(
            workdir: "/tmp/test", executablePath: "/stub/bin/hermes",
            processLauncher: launcher, sessions: sessions)
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(
            JobRequest(id: "j2", goal: "otra", context: ""), events: sink)
    }
    expect(hasFlag(launcher.launched[1].arguments, "--resume",
                   ExecutorSessions.latest),
           "hermes: el segundo encargo continúa el mismo hilo")
}

// MARK: - Helpers

/// nonisolated a propósito: un helper @MainActor dentro del closure detached
/// de `runAsync` espera un actor que el semáforo no va a soltar (ledger).
private func makeClaude(
    launcher: StubProcessLauncher, sessions: any ExecutorSessionStoring
) -> ClaudeCodeExecutor {
    ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false),
        sessions: sessions)
}

private func hasFlag(_ args: [String], _ flag: String, _ value: String) -> Bool {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else {
        return false
    }
    return args[i + 1] == value
}
