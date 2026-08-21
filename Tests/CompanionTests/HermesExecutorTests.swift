import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Hermes no tiene modo stdio: es batch con el prompt como argumento -q
// (mandarlo por stdin lo dejaba esperando para siempre). El rol del ejecutor
// viaja pegado al prompt porque no hay flag de system prompt.

@Test @MainActor
func hermesExecutorDescriptorIdentifies() throws {
    let executor = HermesExecutor(
        workdir: "/tmp/test",
        executablePath: "/stub/bin/hermes",
        processLauncher: StubProcessLauncher()
    )

    expectEq(executor.descriptor.id.rawValue, "hermes", "descriptor id is hermes")
    expectEq(executor.descriptor.shortName, "hermes", "short name")
    expectEq(executor.descriptor.kind, .detectedCLI, "kind is detectedCLI")
}

@Test @MainActor
func hermesExecutorRunsBatchJob() throws {
    let launcher = StubProcessLauncher()
    let result = try runAsync {
        let executor = HermesExecutor(
            workdir: "/tmp/test",
            executablePath: "/stub/bin/hermes",
            processLauncher: launcher
        )

        let job = JobRequest(id: "job-1", goal: "test", context: "")
        let (events, sink) = AsyncStream<JobEvent>.makeStream()
        events.ignore()

        launcher.setResponseTranscript(["Task completed successfully"])
        return try await executor.run(job, events: sink)
    }

    expectEq(result.output, "Task completed successfully", "hermes returns output")
    expect(!result.isError, "hermes batch result is success")

    guard let launch = launcher.launched.first else {
        return expect(false, "hermes: hubo un launch")
    }
    expectEq(launch.executable, "/stub/bin/hermes",
             "hermes: corre el binario resuelto")
    guard let q = launch.arguments.firstIndex(of: "-q"),
          q + 1 < launch.arguments.count else {
        return expect(false, "hermes: el prompt viaja como argumento -q")
    }
    let prompt = launch.arguments[q + 1]
    expect(prompt.contains("test"), "hermes: el objetivo va en el prompt")
    expect(prompt.contains(Escalation.executorRole.prefix(30)),
           "hermes: el rol viaja pegado al prompt — no hay flag de system")
}

@Test @MainActor
func hermesExecutorEmitsStepEvents() throws {
    let result = try runAsync {
        let launcher = StubProcessLauncher()
        let executor = HermesExecutor(
            workdir: "/tmp/test",
            executablePath: "/stub/bin/hermes",
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
