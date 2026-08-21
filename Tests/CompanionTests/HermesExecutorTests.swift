import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// MARK: - HermesExecutor Tests (TDD RED phase)

@Test @MainActor
func hermesExecutorDescriptorIdentifies() throws {
    var launcher = StubProcessLauncher()
    let executor = HermesExecutor(
        workdir: "/tmp/test",
        processLauncher: launcher
    )

    expectEq(executor.descriptor.id.rawValue, "hermes", "descriptor id is hermes")
    expectEq(executor.descriptor.shortName, "hermes", "short name")
    expectEq(executor.descriptor.kind, .detectedCLI, "kind is detectedCLI")
}

@Test @MainActor
func hermesExecutorRunsBatchJob() throws {
    let result = try runAsync {
        var launcher = StubProcessLauncher()
        let executor = HermesExecutor(
            workdir: "/tmp/test",
            processLauncher: launcher
        )

        let job = JobRequest(id: "job-1", goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()

        // Hermes batch: just output, no NDJSON
        let response = "Task completed successfully"
        launcher.setResponseTranscript([response])

        let jobResult = try await executor.run(job, events: sink)
        return jobResult
    }

    expectEq(result.output, "Task completed successfully", "hermes returns output")
    expect(!result.isError, "hermes batch result is success")
}

@Test @MainActor
func hermesExecutorEmitsStepEvents() throws {
    let result = try runAsync {
        var launcher = StubProcessLauncher()
        let executor = HermesExecutor(
            workdir: "/tmp/test",
            processLauncher: launcher
        )

        let job = JobRequest(id: "job-1", goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()

        launcher.setResponseTranscript(["output"])

        let collector = Task {
            var collected: [JobEvent] = []
            for await event in events {
                collected.append(event)
            }
            return collected
        }

        _ = try await executor.run(job, events: sink)
        sink.finish()

        return await collector.value
    }

    let hasStepStarted = result.contains { event in
        if case .stepStarted = event { return true }
        return false
    }
    let hasStepFinished = result.contains { event in
        if case .stepFinished = event { return true }
        return false
    }

    expect(hasStepStarted, "emits stepStarted")
    expect(hasStepFinished, "emits stepFinished")
}
