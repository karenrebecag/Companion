import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El contrato del cable con `claude -p`, aprendido en el prototipo:
// sin --verbose no hay stream-json; sin --permission-prompt-tool stdio las
// aprobaciones jamás viajan; sin el rol el especialista no sabe su contrato
// de pantalla; y el proceso persiste entre encargos.

@Test @MainActor func claudeWireContractTests() throws {
    try testLaunchArgumentsCarryTheProtocol()
    try testProcessPersistsBetweenJobs()
    try testDeadProcessRespawns()
    try testAttachmentsTravelInTheUserTurn()
}

@MainActor func testLaunchArgumentsCarryTheProtocol() throws {
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([resultLine("ok")])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false))

    _ = try runAsync {
        try await executor.run(job("1"), events: ignoredSink())
    }

    guard let launch = launcher.launched.first else {
        return expect(false, "cable: hubo un launch")
    }
    expectEq(launch.executable, "/stub/bin/claude",
             "cable: corre el binario resuelto, no una ruta inventada")
    let args = launch.arguments
    expect(args.contains("--verbose"),
           "cable: stream-json en -p exige --verbose para emitir eventos")
    expect(hasPair(args, "--permission-prompt-tool", "stdio"),
           "cable: sin stdio las aprobaciones nunca llegan")
    expect(hasPair(args, "--append-system-prompt", Escalation.executorRole),
           "cable: el rol del ejecutor viaja una vez por sesión")
    expect(hasPair(args, "--model", "opus"),
           "cable: el modelo va con --model y alias corto, como el CLI acepta")
    expect(!args.contains("-m"),
           "cable: -m no es un flag de claude; mataba el proceso en argparse")
    expectEq(launch.cwd, "/tmp/test", "cable: el workdir es el cwd del hijo")
}

@MainActor func testProcessPersistsBetweenJobs() throws {
    let launcher = StubProcessLauncher()
    // Un solo handle con las líneas de DOS encargos: si el ejecutor lo
    // reutiliza, el segundo result sale del mismo transcript.
    launcher.setResponseTranscript([
        initLine("s-1"), resultLine("primero"),
        resultLine("segundo"),
    ])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false))

    let outputs = try runAsync {
        let a = try await executor.run(job("1"), events: ignoredSink())
        let b = try await executor.run(job("2"), events: ignoredSink())
        return [a.output, b.output]
    }

    expectEq(outputs, ["primero", "segundo"], "cable: ambos encargos responden")
    expectEq(launcher.launched.count, 1,
             "cable: el proceso sobrevive entre encargos — un solo launch")
}

@MainActor func testDeadProcessRespawns() throws {
    let launcher = StubProcessLauncher()
    // Transcript de UN encargo: al agotarse, el handle reporta muerto y el
    // siguiente encargo debe rearmar el proceso en vez de fallar.
    launcher.setResponseTranscript([initLine("s-1"), resultLine("ok")])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false))

    _ = try runAsync {
        let a = try await executor.run(job("1"), events: ignoredSink())
        let b = try await executor.run(job("2"), events: ignoredSink())
        return [a.output, b.output]
    }

    expectEq(launcher.launched.count, 2,
             "cable: proceso muerto ⇒ se rearma para el siguiente encargo")
}

@MainActor func testAttachmentsTravelInTheUserTurn() throws {
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([resultLine("ok")])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/claude",
        processLauncher: launcher,
        approvals: InstantApprovals(approved: false))
    let request = JobRequest(
        id: "1", goal: "describe la imagen", context: "",
        attachments: ["/tmp/captura.png"])

    _ = try runAsync { try await executor.run(request, events: ignoredSink()) }

    // JSONSerialization escapa las diagonales (\/tmp\/...), así que se
    // asserta sobre el nombre, que viaja igual en ambas formas.
    let sent = launcher.handles.first?.sent.first ?? ""
    expect(sent.contains("captura.png"),
           "cable: las rutas adjuntas viajan en el turno — el especialista las abre")
}

// MARK: - Piezas del transcript

private func initLine(_ sid: String) -> String {
    #"{"type":"system","subtype":"init","session_id":"\#(sid)"}"#
}

private func resultLine(_ text: String) -> String {
    #"{"type":"result","result":"\#(text)","is_error":false}"#
}

private func job(_ id: String) -> JobRequest {
    JobRequest(id: id, goal: "objetivo", context: "")
}

/// nonisolated a propósito: se llama dentro del closure detached de runAsync,
/// que corre con el MainActor bloqueado por el semáforo del propio runAsync.
private func ignoredSink() -> AsyncStream<JobEvent>.Continuation {
    let (stream, sink) = AsyncStream<JobEvent>.makeStream()
    stream.ignore()
    return sink
}

private func hasPair(_ args: [String], _ flag: String, _ value: String) -> Bool {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return false }
    return args[i + 1] == value
}
