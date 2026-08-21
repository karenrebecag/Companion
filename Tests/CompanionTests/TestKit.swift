// Thin shims over Swift Testing so the 1000+ existing call sites keep their
// (condition, label) shape; sourceLocation flows so failures point at the
// real assertion line, not this file.
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

@MainActor func pumpUntil(
    _ label: String, timeout: TimeInterval = 2,
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
