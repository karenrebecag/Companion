// Minimal harness mirroring Swift Testing's surface so migration is
// mechanical: expect(x == y) -> #expect(x == y), test("name") { } -> @Test.
// See Package.swift for why Swift Testing itself is not available yet.
import Foundation

// MainActor: el runner es secuencial y top-level code ya corre ahi; asi los
// contadores compilan bajo strict concurrency sin locks.
@MainActor var testsRun = 0
@MainActor var testsFailed = 0

@MainActor func expect(
    _ condition: Bool, _ label: String,
    file: StaticString = #file, line: Int = #line
) {
    testsRun += 1
    if condition {
        print("  ok  \(label)")
    } else {
        testsFailed += 1
        print("FAIL  \(label)  (\(file):\(line))")
    }
}

@MainActor func expectEq<T: Equatable>(
    _ got: T, _ want: T, _ label: String,
    file: StaticString = #file, line: Int = #line
) {
    expect(got == want, "\(label) — got: \(got)  want: \(want)",
           file: file, line: line)
}

/// Sequential harness only. Never call this from Core or Services.
@MainActor func runAsync<T: Sendable>(
    timeout: TimeInterval = 5,
    _ body: @escaping @Sendable () async throws -> T
) throws -> T {
    final class Box: @unchecked Sendable {
        var result: Result<T, Error>?
    }
    let box = Box()
    let lock = DispatchSemaphore(value: 0)
    Task {
        do { box.result = .success(try await body()) }
        catch { box.result = .failure(error) }
        lock.signal()
    }
    if lock.wait(timeout: .now() + timeout) == .timedOut {
        throw CancellationError()
    }
    switch box.result {
    case .success(let value): return value
    case .failure(let error): throw error
    case nil: throw CancellationError()
    }
}

@MainActor func finishTests() -> Never {
    print("\n\(testsRun) tests, \(testsFailed) fallidos")
    exit(testsFailed == 0 ? 0 : 1)
}
