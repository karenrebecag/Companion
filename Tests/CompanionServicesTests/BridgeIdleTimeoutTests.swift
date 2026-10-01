import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D5 (M2a). A bridge session nobody is using closes itself: the
// hands are not left lent to a peer that went quiet (Incredible's bridge
// times a session out the same way).

final class IdleClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

@Test @MainActor func bridgeIdleTimeoutTests() async {
    await testAnIdleSessionClosesAfterTheTimeout()
    await testActivityKeepsTheSessionAlive()
    await testASessionWaitingOnASheetIsNotIdle()
    await testTheWatchdogClosesAQuietConnectionOnItsOwn()
}

func idleSession(
    _ tools: FakeParentTools, _ approvals: ScriptedApprovals, clock: IdleClock,
    timeout: TimeInterval = 60, interval: TimeInterval = 3600
) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true },
        now: { clock.now }, idleTimeout: timeout, idleCheckInterval: interval)
}

func openSession(_ session: BridgeSession, _ pair: BridgePair) async -> Task<Void, Never> {
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2))
    _ = pair.readLine()
    return serving
}

@MainActor func testAnIdleSessionClosesAfterTheTimeout() async {
    let clock = IdleClock()
    let session = idleSession(FakeParentTools(), ScriptedApprovals(answer: true), clock: clock,
                              timeout: BridgePolicy.idleTimeout)
    let pair = BridgePair()
    let serving = await openSession(session, pair)
    expect(await session.state == .open(until: nil), "M2a: la sesion esta abierta")

    clock.advance(BridgePolicy.idleTimeout - 1)
    expect(await session.expireIfIdle() == false, "M2a: dentro del plazo sigue abierta")

    clock.advance(2)
    expect(await session.expireIfIdle(), "M2a: pasado el plazo se cierra")
    expect(!pair.connection.isOpen, "M2a: la conexion se cierra para que el cliente vea EOF")
    await serving.value
    expect(await session.state == .idle, "M2a: sin conexion, la proxima parte de idle y pide hoja")
}

@MainActor func testActivityKeepsTheSessionAlive() async {
    let clock = IdleClock()
    let session = idleSession(FakeParentTools(), ScriptedApprovals(answer: true), clock: clock, timeout: 60)
    let pair = BridgePair()
    let serving = await openSession(session, pair)
    clock.advance(45)
    pair.send(call(3))
    _ = pair.readLine()
    clock.advance(45)
    expect(await session.expireIfIdle() == false, "M2a: una llamada reinicia el reloj")
    pair.closeClient()
    await serving.value
}

@MainActor func testASessionWaitingOnASheetIsNotIdle() async {
    let clock = IdleClock()
    let approvals = ScriptedApprovals(park: true)
    let session = idleSession(FakeParentTools(), approvals, clock: clock, timeout: 60)
    let pair = BridgePair()
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2))
    await pollUntilTrue { !approvals.requests.isEmpty }
    clock.advance(600)
    expect(await session.expireIfIdle() == false, "M2a: la hoja pendiente tiene su propio plazo")
    if let request = approvals.requests.first {
        _ = await approvals.resolve(requestId: request.requestId, approved: false)
    }
    pair.closeClient()
    await serving.value
}

@MainActor func testTheWatchdogClosesAQuietConnectionOnItsOwn() async {
    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true },
        idleTimeout: 0.05, idleCheckInterval: 0.02)
    let pair = BridgePair()
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    await pollUntilTrue { !pair.connection.isOpen }
    expect(!pair.connection.isOpen, "M2a: el vigilante cierra la conexion callada")
    await serving.value
    expect(await session.state == .idle, "M2a: tras cerrar, el estado vuelve a idle")
}
