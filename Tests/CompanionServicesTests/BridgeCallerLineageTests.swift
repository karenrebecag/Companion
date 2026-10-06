import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Darwin
import Foundation
import Testing

// The bridge wraps every call in `HandsCaller.$apps.withValue(lineage)` so
// `resolveTarget` and `holds(pid:)` know which pids count as the caller's
// own. `FakeParentTools` snapshots `HandsCaller.apps` at `approval` and
// `execute`; the two snapshots are the same set (a yes cannot be bound to
// a different lineage than the execute that spends it).
//
// `BridgeSession.serve(_:)` is the only path that sets `current`, which
// carries the peer pid; we drive the session through a real
// `BridgeConnection` (a `socketpair` whose peer pid is this very process)
// to get a non-empty lineage. A session with no peer (driven through
// `handle(line:)`) sees an empty lineage and the test confirms the
// wiring by checking both points.

/// A `withTimeout`-ish wrapper around an awaited Task that fails the
/// test instead of hanging the gate when `serve` never finishes (a
/// misbehaving server loop otherwise blocks the suite forever).
private func withServing<T: Sendable>(
    timeout: TimeInterval = 5, _ body: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return nil
            }
            return nil
        }
        // First to finish wins; a nil from the sleeper means serve hung.
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

// MARK: - (a) the bridge records the same lineage at approval and execute


@Test @MainActor func bridgeCallerLineageAtApprovalAndExecuteMatch() async throws {
    let tools = FakeParentTools()
    let recorder = LineageRecorder()
    // `HandsCaller.apps` is read inside the closure, so it captures the
    // value the bridge installed via `withValue(lineage)`. The fake
    // never sees the closure; only the moment and the value reach it.
    tools.setLineageObserver { point in
        recorder.append(point: point, value: HandsCaller.apps)
    }
    let session = bridgeSession(tools: tools, approvals: ScriptedApprovals(answer: true))
    let pair = BridgePair(onClosed: {})
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine(timeout: 2)
    pair.send(call(2, "look"))
    let reply = pair.readLine(timeout: 2) ?? ""
    expect(reply.contains(#""ok":true"#), "look: ok \(reply)")
    let snapshots = recorder.snapshots()
    // Two snapshots: the per-call verdict (run inside `performCall`'s
    // `withValue(lineage)` wrap) and the execute (same wrap). The
    // session-open sheet itself runs UNWRAPPED; only `performCall` is
    // wrapped, so a snapshot labelled "session-open" would be a false
    // positive in the wiring test.
    expect(snapshots.count >= 2, "snapshots capturados: \(snapshots.count) \(snapshots)")
    let approval = snapshots.first { $0.point == "approval" }
    let execute = snapshots.first { $0.point == "execute" }
    expect(approval != nil, "approval: capturado")
    expect(execute != nil, "execute: capturado")
    let expected = HandsCaller.lineage(of: ProcessInfo.processInfo.processIdentifier)
    expect(!expected.isEmpty, "lineage del proceso de test: no vacio \(expected)")
    expect(execute?.value == expected,
           "execute: ve la lineage del peer \(execute?.value ?? []) vs \(expected)")
    expect(approval?.value == execute?.value,
           "approval y execute ven la misma lineage \(approval?.value ?? []) vs \(execute?.value ?? [])")
    // Close the client end of the pair so the server's read loop sees
    // EOF and the serve task can finish; otherwise `await serving.value`
    // would hang waiting for more lines.
    pair.closeClient()
    let finished = await withServing { await serving.value }
    expect(finished != nil, "serve termino en vez de colgar")
}

// MARK: - (b) a session with no peer sees [] at both points

@Test @MainActor func bridgeCallerLineageEmptyWhenNoPeer() async throws {
    let tools = FakeParentTools()
    let recorder = LineageRecorder()
    tools.setLineageObserver { point in
        recorder.append(point: point, value: HandsCaller.apps)
    }
    let session = BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true })
    // `handle(line:)` does not set `current`; `current?.peer?.pid` is nil,
    // so `lineage(of: nil)` is `[]` and that is what the bridge wraps.
    _ = await session.handle(line: hello(1, token: "tok"))
    _ = await session.handle(line: call(2, "look"))
    let snapshots = recorder.snapshots()
    expect(snapshots.count >= 2, "snapshots: \(snapshots.count)")
    for snapshot in snapshots {
        expect(snapshot.value.isEmpty, "sin peer: snapshot vacio \(snapshot)")
    }
}

// MARK: - helpers

private func bridgeSession(tools: FakeParentTools, approvals: ScriptedApprovals) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true })
}

/// The fake fires its observer from off the main actor; the test reads
/// the snapshots later, on the main actor. A small class with a lock
/// is the cheapest way to bridge the two without losing or duplicating
/// entries.
private final class LineageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshots: [(point: String, value: Set<Int32>)] = []

    func append(point: String, value: Set<Int32>) {
        lock.withLock { _snapshots.append((point, value)) }
    }

    func snapshots() -> [(point: String, value: Set<Int32>)] {
        lock.withLock { _snapshots }
    }
}
