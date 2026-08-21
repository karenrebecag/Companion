import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// MARK: - CLI Executor Discovery Tests

@Test @MainActor
func cliProbeFindsClaude() throws {
    let result = try runAsync {
        var launcher = StubProcessLauncher()
        let probe = CLIExecutorProbe(
            processLauncher: launcher,
            workdir: "/tmp/test"
        )

        // Simulate 'which claude' returning a path (success)
        launcher.setNextResponse("/usr/local/bin/claude")

        let detected = await probe.detectAvailable()
        return detected.map { $0.id.rawValue }
    }

    expect(result.contains("claude-code"), "probe finds claude code executor")
}

@Test @MainActor
func cliProbeFindsBoth() throws {
    let result = try runAsync {
        var launcher = StubProcessLauncher()
        let probe = CLIExecutorProbe(
            processLauncher: launcher,
            workdir: "/tmp/test"
        )

        // Simulate both binaries found
        launcher.setNextResponse("/usr/local/bin/claude")
        launcher.setNextResponse("/usr/local/bin/hermes")

        let detected = await probe.detectAvailable()
        return detected.map { $0.id.rawValue }
    }

    expect(result.contains("claude-code"), "probe finds claude")
    expect(result.contains("hermes"), "probe finds hermes")
}

@Test @MainActor
func executorProviderSelectsExecutor() throws {
    let result = try runAsync {
        var launcher = StubProcessLauncher()
        let nativeExecutor = StubExecutor(id: "native")
        let probe = CLIExecutorProbe(processLauncher: launcher, workdir: "/tmp/test")

        launcher.setNextResponse("/usr/local/bin/claude")
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
        var launcher = StubProcessLauncher()
        let nativeExecutor = StubExecutor(id: "native")
        let probe = CLIExecutorProbe(processLauncher: launcher, workdir: "/tmp/test")

        // First, claude is available
        launcher.setNextResponse("/usr/local/bin/claude")
        let provider = ExecutorProvider(nativeExecutor: nativeExecutor, cliProbe: probe)

        await provider.refreshAvailableExecutors()
        _ = provider.selectExecutor(id: ExecutorID(rawValue: "claude-code"))

        // Now simulate claude disappearing (no output from which)
        launcher.setNextResponse(nil)
        await provider.refreshAvailableExecutors()

        // Should degrade to native
        let selected = provider.getSelectedExecutorId()
        return selected.rawValue
    }

    expectEq(result, "native", "provider degrades to native when executor vanishes")
}

// MARK: - Stubs

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

