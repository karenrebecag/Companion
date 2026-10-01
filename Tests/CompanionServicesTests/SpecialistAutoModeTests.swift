import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 16b (spec §5 fila 7). Karen: "asegúrate de que ya no pida permisos para
// ejecutar comandos". El especialista corre en modo `auto` de Claude Code (el
// clasificador aprueba lo seguro sin preguntar) con una lista negra fija; lo
// que aun así pregunte se niega solo, sin hoja.

@Test @MainActor func specialistAutoModeTests() throws {
    try testTheCableRunsInAutoModeWithTheDenyList()
    try testTheBatchFallbackKeepsTheSamePosture()
    try testAPermissionQuestionIsDeniedWithoutASheet()
}

private final class AutoModeApprovals: ApprovalsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var asked: Int { lock.withLock { count } }
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        lock.withLock { count += 1 }
        return ApprovalResponse(requestId: approval.requestId, approved: true)
    }
    func resolve(requestId: String, approved: Bool) async -> Bool { true }
}

private func deniedPatterns(_ args: [String]) -> [String] {
    guard let index = args.firstIndex(of: "--disallowedTools"), index + 1 < args.count else { return [] }
    return args[(index + 1)...].prefix { !$0.hasPrefix("--") }.flatMap {
        $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private func expectAutoPosture(_ args: [String], _ label: String) {
    expect(zip(args, args.dropFirst()).contains { $0 == "--permission-mode" && $1 == "auto" },
           "\(label): modo auto")
    expect(!args.contains("acceptEdits"), "\(label): ya no acceptEdits")
    let denied = deniedPatterns(args)
    for pattern in ClaudeCodeExecutor.deniedTools {
        expect(denied.contains(pattern), "\(label): prohíbe \(pattern)")
    }
    expect(ClaudeCodeExecutor.deniedTools.contains("Bash(osascript *)"),
           "\(label): la pantalla es de las manos del padre")
    expect(ClaudeCodeExecutor.deniedTools.contains("Bash(sudo *)"), "\(label): nunca sudo")
    // Security review 16 (H2): variants the first list missed. Claude Code
    // 2.1.282 already splits `bash -c`, `;` chains and full paths before
    // matching (spike 2026-09-25); these cover spellings, not wrappers.
    for pattern in ["Bash(git push*)", "Bash(rm -fr /*)", "Bash(rm -fr ~*)", "Bash(rm -rf $HOME*)",
                    "Bash(wget * | sh*)", "Bash(wget * | bash*)"] {
        expect(ClaudeCodeExecutor.deniedTools.contains(pattern), "\(label): prohíbe \(pattern)")
    }
}

@MainActor func testTheCableRunsInAutoModeWithTheDenyList() throws {
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([#"{"type":"result","result":"ok","is_error":false}"#])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test", executablePath: "/stub/bin/claude",
        processLauncher: launcher, approvals: InstantApprovals(approved: false))
    _ = try runAsync {
        try await executor.run(JobRequest(id: "1", goal: "x", context: ""), events: AsyncStream.makeStream().1)
    }
    let args = launcher.launched.first?.arguments ?? []
    expectAutoPosture(args, "cable")
    expect(zip(args, args.dropFirst()).contains { $0 == "--permission-prompt-tool" && $1 == "stdio" },
           "cable: el canal sigue, para negar lo que aún pregunte")
}

@MainActor func testTheBatchFallbackKeepsTheSamePosture() throws {
    let launcher = StubProcessLauncher()
    launcher.setNextTranscript([#"{"type":"system","subtype":"init","session_id":"s-1"}"#])
    launcher.setNextTranscript(["Hecho."])
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test", executablePath: "/stub/bin/claude",
        processLauncher: launcher, approvals: InstantApprovals(approved: false))
    _ = try runAsync {
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()
        return try await executor.run(JobRequest(id: "1", goal: "x", context: ""), events: sink)
    }
    guard launcher.launched.count == 2 else { return expect(false, "batch: hubo reintento") }
    expectAutoPosture(launcher.launched[1].arguments, "batch")
}

@MainActor func testAPermissionQuestionIsDeniedWithoutASheet() throws {
    let launcher = StubProcessLauncher()
    launcher.setResponseTranscript([
        #"{"type":"system","subtype":"init","session_id":"s-1"}"#,
        #"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"rm -rf ~/x"}}}"#,
        #"{"type":"result","result":"no pude","is_error":false}"#,
    ])
    let approvals = AutoModeApprovals()
    let executor = ClaudeCodeExecutor(
        workdir: "/tmp/test", executablePath: "/stub/bin/claude",
        processLauncher: launcher, approvals: approvals)
    let events = try runAsync { () -> [JobEvent] in
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let collector = Task { var all: [JobEvent] = []; for await e in stream { all.append(e) }; return all }
        _ = try await executor.run(JobRequest(id: "1", goal: "x", context: ""), events: sink)
        sink.finish()
        return await collector.value
    }
    expectEq(approvals.asked, 0, "pregunta: nunca llega a la hoja")
    expect(!events.contains { if case .approvalRequested = $0 { true } else { false } },
           "pregunta: sin evento de aprobación")
    let sent = launcher.handles.first?.sent ?? []
    expect(sent.contains { $0.contains("req-1") && $0.contains(#""behavior":"deny""#) },
           "pregunta: se contesta deny por el cable")
    expect(!sent.contains { $0.contains("rm -rf") && $0.contains("allow") }, "pregunta: nunca allow")
}
