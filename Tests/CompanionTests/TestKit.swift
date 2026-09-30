// Thin shims over Swift Testing so the 1000+ existing call sites keep their
// (condition, label) shape; sourceLocation flows so failures point at the
// real assertion line, not this file.
import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

func expect(
    _ condition: Bool, _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(condition, Comment(rawValue: label), sourceLocation: sourceLocation)
}

func expectEq<T: Equatable>(
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
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    /// `_modify` keeps `box.value.append(x)` one critical section instead of
    /// a get and a set that another writer could slip between.
    var value: T {
        get { lock.withLock { stored } }
        _modify {
            lock.lock()
            defer { lock.unlock() }
            yield &stored
        }
    }

    func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
        try lock.withLock { try body(&stored) }
    }
}

/// The lock is non-recursive and held for the whole `_modify`: touching the
/// same property inside its own mutation deadlocks, and check-then-act across
/// two separate accesses is not atomic (use `withLock`).
/// Property-wrapper form of `LockedBox` for fakes with many independent
/// flags: `@Guarded var started = false` keeps every call site unchanged.
@propertyWrapper
struct Guarded<T>: Sendable {
    private let box: LockedBox<T>

    init(wrappedValue: T) { box = LockedBox(wrappedValue) }

    var wrappedValue: T {
        get { box.value }
        nonmutating _modify { yield &box.value }
    }
}

/// Sequential harness only. Never call this from Core or Services.
final class AsyncBox<T: Sendable>: @unchecked Sendable {
    var result: Result<T, Error>?
}

@MainActor func runAsync<T: Sendable>(
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
@MainActor func pumpUntil(
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

@MainActor func settle(_ seconds: TimeInterval = 0.05) async {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}

@testable import CompanionServices

/// Mock clock that can be advanced programmatically for testing time-dependent logic.
final class MockClock: Clock, @unchecked Sendable {
    private let lock = DispatchSemaphore(value: 1)
    private var _now: TimeInterval

    init(startTime: TimeInterval = 0) {
        self._now = startTime
    }

    nonisolated func now() -> TimeInterval {
        // Mutex-protected access from nonisolated context
        let mc = self as! MockClock // Unsafe but necessary for test-only code
        mc.lock.wait()
        defer { mc.lock.signal() }
        return mc._now
    }

    func advance(by seconds: TimeInterval) {
        lock.wait()
        defer { lock.signal() }
        _now += seconds
    }

    func set(now: TimeInterval) {
        lock.wait()
        defer { lock.signal() }
        _now = now
    }
}

/// UI copy tests assert exact wording, so they must not depend on which
/// language the machine running them happens to prefer. English is the
/// source; a Spanish assertion pins `.es` explicitly.
/// Debugging 2026-09-28: takes the rest of the dispatcher as a trailing
/// closure instead of just assigning `Localized.language` — Swift Testing
/// runs `@Test` functions in parallel, so a bare assignment let two
/// dispatchers stomp on each other's pin mid-run. `Localized.scoped` binds
/// it to this call's task tree only.
@MainActor func pinLanguage<R>(
    _ language: AppLanguage = .en, _ body: () async throws -> R
) async rethrows -> R {
    try await Localized.scoped(to: language, body)
}
