import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@testable import CompanionServices

/// A limit the test holds open and releases when it wants the cap to elapse.
private final class HeldLimit: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Error>?
    private var _asked: [Int] = []

    var asked: [Int] { lock.withLock { _asked } }
    var isWaiting: Bool { lock.withLock { waiter != nil } }

    var limit: TurnWaiter.Limit {
        { seconds in
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.withLock {
                        self._asked.append(seconds)
                        self.waiter = continuation
                    }
                }
            } onCancel: {
                let pending = self.lock.withLock { () -> CheckedContinuation<Void, Error>? in
                    defer { self.waiter = nil }
                    return self.waiter
                }
                pending?.resume(throwing: CancellationError())
            }
        }
    }

    func elapse() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            defer { waiter = nil }
            return waiter
        }
        pending?.resume()
    }
}

@Test func aFinishedSignalWakesTheWaiter() async {
    let held = HeldLimit()
    let waiter = TurnWaiter(limit: held.limit)
    let waiting = Task { await waiter.wait(turnId: "t1", seconds: 60) }
    while !held.isWaiting { await Task.yield() }
    await waiter.signal(turnId: "t1", .finished)
    expectEq(await waiting.value, .finished, "termino")
    expectEq(held.asked, [60], "espero con el tope pedido")
}

@Test func anOpenedOwnerCheckHandsControlBackAtOnce() async {
    let held = HeldLimit()
    let waiter = TurnWaiter(limit: held.limit)
    let waiting = Task { await waiter.wait(turnId: "t1", seconds: 60) }
    while !held.isWaiting { await Task.yield() }
    await waiter.signal(turnId: "t1", .ownerCheckOpened)
    expectEq(await waiting.value, .awaitingOwner, "hay Touch ID pendiente")
}

@Test func theCapEndsTheWaitWithoutATurnSignal() async {
    let held = HeldLimit()
    let waiter = TurnWaiter(limit: held.limit)
    let waiting = Task { await waiter.wait(turnId: "t1", seconds: 5) }
    while !held.isWaiting { await Task.yield() }
    held.elapse()
    expectEq(await waiting.value, .timedOut, "tope")
}

@Test func aTurnThatEndedBeforeTheWaitAnswersWithoutWaiting() async {
    let waiter = TurnWaiter(limit: { _ in })
    await waiter.signal(turnId: "t1", .finished)
    expectEq(await waiter.wait(turnId: "t1", seconds: 60), .finished, "ya habia terminado")
}

@Test func aClosedOwnerCheckGoesBackToWaiting() async {
    let held = HeldLimit()
    let waiter = TurnWaiter(limit: held.limit)
    await waiter.signal(turnId: "t1", .ownerCheckOpened)
    await waiter.signal(turnId: "t1", .ownerCheckClosed)
    let waiting = Task { await waiter.wait(turnId: "t1", seconds: 60) }
    while !held.isWaiting { await Task.yield() }
    await waiter.signal(turnId: "t1", .finished)
    expectEq(await waiting.value, .finished, "ya no hay dialogo abierto")
}

@Test func aSessionBoundaryReleasesTheOrphanedWait() async {
    let held = HeldLimit()
    let waiter = TurnWaiter(limit: held.limit)
    let waiting = Task { await waiter.wait(turnId: "t1", seconds: 60) }
    while !held.isWaiting { await Task.yield() }
    await waiter.cancelAll()
    expectEq(await waiting.value, .timedOut, "nadie queda leyendo")
}
