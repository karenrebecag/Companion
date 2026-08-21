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
