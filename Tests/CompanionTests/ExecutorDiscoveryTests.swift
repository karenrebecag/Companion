import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// La detección es por sistema de archivos: una app GUI no hereda el PATH del
// shell, así que "which" en subproceso mentía (decía no-instalado con claude
// instalado, y la delegación moría en processLaunchFailed).

@Test @MainActor
func cliProbeFindsClaude() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") {
            $0 == "/Users/k/.local/bin/claude"
        },
        hermesProviders: { [] })
    let detected = try runAsync { await probe.detectAvailable() }
    expect(detected.contains { $0.id.rawValue == "claude-code" },
           "probe: claude instalado ⇒ ejecutor en el catálogo")
    expect(!detected.contains { $0.id.rawValue == "hermes" },
           "probe: hermes ausente ⇒ fuera del catálogo")
}

@Test @MainActor
func cliProbeFindsBoth() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") {
            ["/Users/k/.local/bin/claude", "/Users/k/.local/bin/hermes"].contains($0)
        },
        hermesProviders: { [] })
    let detected = try runAsync { await probe.detectAvailable() }
    expect(detected.contains { $0.id.rawValue == "claude-code" }, "probe: claude")
    expect(detected.contains { $0.id.rawValue == "hermes" }, "probe: hermes")
}

@Test @MainActor
func cliProbeResolvesExecutablePath() throws {
    let probe = CLIExecutorProbe(
        locator: CLIBinaryLocator(home: "/Users/k") {
            $0 == "/Users/k/.local/bin/claude"
        },
        hermesProviders: { [] })
    expectEq(probe.executablePath(for: ExecutorID(rawValue: "claude-code")),
             "/Users/k/.local/bin/claude",
             "probe: entrega la ruta real para lanzar, no una adivinada")
    expectEq(probe.executablePath(for: ExecutorID(rawValue: "hermes")), nil,
             "probe: sin binario no hay ruta")
}

@Test @MainActor
func executorProviderSelectsExecutor() throws {
    let result = try runAsync {
        let nativeExecutor = StubExecutor(id: "native")
        let probe = CLIExecutorProbe(
            locator: CLIBinaryLocator(home: "/Users/k") {
                $0 == "/Users/k/.local/bin/claude"
            },
            hermesProviders: { [] })
        let provider = ExecutorProvider(nativeExecutor: nativeExecutor, cliProbe: probe)

        await provider.refreshAvailableExecutors()

        let success = provider.selectExecutor(id: ExecutorID(rawValue: "claude-code"))
        let selected = provider.getSelectedExecutorId()

        return (success: success, selected: selected.rawValue)
    }

    expect(result.success, "select executor succeeds for available id")
    expectEq(result.selected, "claude-code", "selected executor id matches")
}

@Test @MainActor
func executorProviderDegradesMissingExecutor() throws {
    let result = try runAsync {
        let nativeExecutor = StubExecutor(id: "native")
        let installed = ExecutableSet(["/Users/k/.local/bin/claude"])
        let probe = CLIExecutorProbe(
            locator: CLIBinaryLocator(home: "/Users/k") {
                installed.contains($0)
            },
            hermesProviders: { [] })
        let provider = ExecutorProvider(nativeExecutor: nativeExecutor, cliProbe: probe)

        await provider.refreshAvailableExecutors()
        _ = provider.selectExecutor(id: ExecutorID(rawValue: "claude-code"))

        // Claude se desinstala entre un refresh y otro
        installed.set([])
        await provider.refreshAvailableExecutors()

        let selected = provider.getSelectedExecutorId()
        return selected.rawValue
    }

    expectEq(result, "native", "provider degrades to native when executor vanishes")
}

// MARK: - Stubs

/// Un "sistema de archivos" mutable: qué binarios existen ahora mismo.
final class ExecutableSet: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String>
    init(_ paths: Set<String>) { self.paths = paths }
    func set(_ paths: Set<String>) { lock.withLock { self.paths = paths } }
    func contains(_ path: String) -> Bool { lock.withLock { paths.contains(path) } }
}

struct StubExecutor: Executor {
    let id: String

    var descriptor: ExecutorDescriptor {
        ExecutorDescriptor(
            id: ExecutorID(rawValue: id),
            shortName: id,
            title: id,
            kind: .native
        )
    }

    func run(
        _: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        JobResult(output: "stub", isError: false)
    }
}
