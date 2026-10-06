// Thin shims over Swift Testing so the 1000+ existing call sites keep their
// (condition, label) shape; sourceLocation flows so failures point at the
// real assertion line, not this file.
import Foundation
import Testing

/// Tests that assert a wall-clock bound fail on loaded CI runners without a
/// real regression. Off in CI so they never block a merge; the nightly job
/// sets COMPANION_FLAKY_QUARANTINE_OFF to keep running them.
package let wallClockQuarantined: Bool = {
    let env = ProcessInfo.processInfo.environment
    return env["CI"] != nil && env["COMPANION_FLAKY_QUARANTINE_OFF"] == nil
}()

package let wallClockQuarantineReason: Comment =
    "reloj de pared inestable bajo carga en CI: docs/inventario-flakes.md"

package func expect(
    _ condition: Bool, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(condition, Comment(rawValue: label), sourceLocation: sourceLocation)
}

package func expectEq<T: Equatable>(
    _ got: T, _ want: T, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(got == want,
            Comment(rawValue: "\(label) — got: \(got)  want: \(want)"),
            sourceLocation: sourceLocation)
}

/// Fakes are written from an actor's thread and read from the main-actor test
/// body (`pumpUntil`); a bare stored property there is a data race that
/// crashed the suite in `Array.append`. Same idea as `ScriptedThread`'s lock.
package final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    package init(_ value: T) { stored = value }

    /// `_modify` keeps `box.value.append(x)` one critical section instead of
    /// a get and a set that another writer could slip between.
    package var value: T {
        get { lock.withLock { stored } }
        _modify {
            lock.lock()
            defer { lock.unlock() }
            yield &stored
        }
    }

    package func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
        try lock.withLock { try body(&stored) }
    }
}

/// The lock is non-recursive and held for the whole `_modify`: touching the
/// same property inside its own mutation deadlocks, and check-then-act across
/// two separate accesses is not atomic (use `withLock`).
/// Property-wrapper form of `LockedBox` for fakes with many independent
/// flags: `@Guarded var started = false` keeps every call site unchanged.
@propertyWrapper
package struct Guarded<T>: Sendable {
    private let box: LockedBox<T>

    package init(wrappedValue: T) { box = LockedBox(wrappedValue) }

    package var wrappedValue: T {
        get { box.value }
        nonmutating _modify { yield &box.value }
    }
}

/// Sequential harness only. Never call this from Core or Services.
package final class AsyncBox<T: Sendable>: @unchecked Sendable {
    package init() {}
    package var result: Result<T, Error>?
}

@MainActor package func runAsync<T: Sendable>(
    timeout: TimeInterval = 5,
    _ body: @escaping @Sendable () async throws -> T
) throws -> T {
    let box = AsyncBox<T>()
    let lock = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await body()) }
        catch { box.result = .failure(error) }
        lock.signal()
    }
    if lock.wait(timeout: .now() + timeout) == .timedOut {
        throw CancellationError()
    }
    guard let result = box.result else { throw CancellationError() }
    switch result {
    case .success(let value): return value
    case .failure(let error): throw error
    }
}

/// El plazo generoso no es holgura: estos tests son todos `@MainActor` y este
/// bucle espera OCUPANDO el main actor, asi que bajo carga se quedan sin turno
/// unos a otros. Con 2 s la suite fallaba de forma intermitente sin que nada
/// estuviera roto. Sale en cuanto se cumple la condicion, asi que un plazo
/// largo no cuesta nada cuando todo va bien.
/// Debugging 2026-09-28: 10 s alcanzaba en esta Mac (14 cores) pero no en el
/// runner de CI (macos-26, unos pocos vCPUs) — ahi el mismo main actor
/// contended contra el patron `runOk`/`runAsync` de otros ~50 sitios (cada
/// uno bloquea un hilo real hasta 5 s con un `DispatchSemaphore`) hacia que
/// este bucle se quedara sin turno mas tiempo del que el propio predicado
/// tarda en volverse verdadero.
@MainActor package func pumpUntil(
    _ label: String, timeout: TimeInterval = 30,
    sourceLocation: SourceLocation = #_sourceLocation, _ pred: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !pred(), Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    expect(pred(), label, sourceLocation: sourceLocation)
}

@MainActor package func settle(_ seconds: TimeInterval = 0.05) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// `pumpUntil` for a predicate that has to hop into an actor.
/// Debugging 2026-09-28: same headroom as `pumpUntil` (TestKit.swift), same
/// reason — CI's runner has far fewer cores than a dev Mac, so the main
/// actor (and the cooperative pool an unstructured `Task` like `prewarm`'s
/// needs) can go unserved for longer than a tight deadline allows even when
/// the work itself is instant.
@MainActor package func pumpUntilAsync(
    _ label: String, timeout: TimeInterval = 30, _ pred: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await pred()), Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    if !(await pred()) { Issue.record("timeout: \(label)") }
}

package struct StreamBox<T: Sendable>: @unchecked Sendable {
    package let stream: AsyncStream<T>
    package let cont: AsyncStream<T>.Continuation
    package init() { (stream, cont) = AsyncStream.makeStream(of: T.self) }
    package func yield(_ value: T) { cont.yield(value) }
    package func finish() { cont.finish() }
}

package func drain<T: Sendable>(_ stream: AsyncStream<T>) async -> [T] {
    var out: [T] = []
    for await item in stream { out.append(item) }
    return out
}

@MainActor package func runOk(_ label: String, _ body: @escaping @Sendable () async throws -> Void) {
    do { try runAsync(body) }
    catch { expect(false, "\(label): no debía tirar \(error)") }
}
