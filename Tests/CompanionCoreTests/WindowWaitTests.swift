import CompanionCore
import CompanionTestKit
import Foundation
import Testing

/// The wait that open_app does for a launched app: bounded, cooperative, and
/// honest about the difference between "not yet" and "cut".
@Test @MainActor func windowWaitTests() async {
    await testItReturnsAsSoonAsReady()
    await testATimeoutOfZeroStillLooksOnce()
    await testItGivesUpAfterTheTimeout()
    await testAPollLongerThanTheTimeoutDoesNotHangTheWait()
    await testCancellationEndsTheWaitEarly()
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
    var count: Int { lock.withLock { n } }
}

@MainActor func testItReturnsAsSoonAsReady() async {
    let counter = Counter()
    let pid = await WindowWait(timeout: 5, poll: 0.01).wait { counter.next() >= 3 ? 42 : nil }
    expectEq(pid, 42, "espera: devuelve el pid cuando esta listo")
    expectEq(counter.count, 3, "espera: no sigue mirando despues de estar listo")
}

@MainActor func testATimeoutOfZeroStillLooksOnce() async {
    let counter = Counter()
    let ready = await WindowWait(timeout: 0, poll: 0.01).wait { _ = counter.next(); return 7 }
    expectEq(ready, 7, "plazo cero: mira una vez y toma lo que ya estaba listo")
    expectEq(counter.count, 1, "plazo cero: una sola mirada")
    let never = await WindowWait(timeout: 0, poll: 0.01).wait { nil }
    expectEq(never, nil, "plazo cero: sin nada listo, nil de inmediato")
}

@MainActor func testItGivesUpAfterTheTimeout() async {
    let started = Date()
    let pid = await WindowWait(timeout: 0.1, poll: 0.01).wait { nil }
    expectEq(pid, nil, "plazo vencido: nil")
    expect(Date().timeIntervalSince(started) < 2, "plazo vencido: no se queda esperando de mas")
}

@MainActor func testAPollLongerThanTheTimeoutDoesNotHangTheWait() async {
    let counter = Counter()
    let started = Date()
    _ = await WindowWait(timeout: 0.05, poll: 0.2).wait { _ = counter.next(); return nil }
    expect(Date().timeIntervalSince(started) < 2, "poll largo: la espera termina")
    expect(counter.count >= 2, "poll largo: mira al inicio y al final")
}

@MainActor func testCancellationEndsTheWaitEarly() async {
    let task = Task { await WindowWait(timeout: 30, poll: 0.01).wait { nil } }
    await settle(0.05)
    let started = Date()
    task.cancel()
    let pid = await task.value
    expectEq(pid, nil, "cancelado: nil")
    expect(Date().timeIntervalSince(started) < 1, "cancelado: termina mucho antes del plazo")
}
