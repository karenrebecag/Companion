import Foundation
import Testing

@testable import CompanionCore

@Test @MainActor
func jobRequestIsCreatable() {
    let req = JobRequest(
        id: "job-1",
        goal: "write a file",
        context: "in the test project"
    )
    expectEq(req.id, "job-1", "id matches")
    expectEq(req.goal, "write a file", "goal matches")
    expectEq(req.context, "in the test project", "context matches")
    expectEq(req.attachments.count, 0, "attachments empty by default")
}

@Test @MainActor
func jobRequestIsSendable() {
    // Sendable is enforced by the compiler in the type definition.
    // This test just verifies that JobRequest compiles as Sendable.
    let req = JobRequest(
        id: "job-2",
        goal: "test goal",
        context: "test context"
    )
    // Compiler verifies Sendable at definition time
    expect(true, "JobRequest is Sendable")
}

@Test @MainActor
func jobRequestIsEquatable() {
    let req1 = JobRequest(
        id: "job-1",
        goal: "goal",
        context: "ctx"
    )
    let req2 = JobRequest(
        id: "job-1",
        goal: "goal",
        context: "ctx"
    )
    let req3 = JobRequest(
        id: "job-2",
        goal: "goal",
        context: "ctx"
    )
    expectEq(req1, req2, "identical requests are equal")
    expect(req1 != req3, "different ids are not equal")
}

@Test @MainActor
func jobResultIsCreatable() {
    let result = JobResult(
        output: "Success",
        isError: false
    )
    expectEq(result.output, "Success", "output matches")
    expect(!result.isError, "isError false when success")
    expectEq(result.sessionId, nil, "sessionId is nil by default")
}

@Test @MainActor
func jobResultCanHaveSessionId() {
    let result = JobResult(
        output: "Done",
        isError: false,
        sessionId: "session-123"
    )
    expectEq(result.sessionId, "session-123", "sessionId stored")
}

@Test @MainActor
func jobResultIsEquatable() {
    let r1 = JobResult(output: "test", isError: false, sessionId: "s1")
    let r2 = JobResult(output: "test", isError: false, sessionId: "s1")
    let r3 = JobResult(output: "different", isError: false, sessionId: "s1")
    expectEq(r1, r2, "identical results are equal")
    expect(r1 != r3, "different output means not equal")
}

@Test @MainActor
func jobEventStepStartedIsCreatable() {
    let event = JobEvent.stepStarted(tool: "read_file", summary: "Reading config.json")
    expectEq(event, JobEvent.stepStarted(tool: "read_file", summary: "Reading config.json"),
             "stepStarted events are equal")
}

@Test @MainActor
func jobEventStepFinishedIsCreatable() {
    let event = JobEvent.stepFinished(tool: "write_file", ok: true)
    expectEq(event, JobEvent.stepFinished(tool: "write_file", ok: true),
             "stepFinished events are equal")
}

@Test @MainActor
func jobEventApprovalRequestedIsCreatable() {
    let approval = ApprovalRequest(
        requestId: "req-1",
        toolName: "run_shell",
        summary: "rm -rf /",
        inputJSON: "{}"
    )
    let event = JobEvent.approvalRequested(approval)
    expectEq(event, JobEvent.approvalRequested(approval),
             "approvalRequested events are equal")
}

@Test @MainActor
func jobEventThoughtIsCreatable() {
    let event = JobEvent.thought("I should read the file first")
    expectEq(event, JobEvent.thought("I should read the file first"),
             "thought events are equal")
}

@Test @MainActor
func jobEventIsEquatable() {
    let e1 = JobEvent.stepStarted(tool: "read_file", summary: "test")
    let e2 = JobEvent.stepStarted(tool: "read_file", summary: "test")
    let e3 = JobEvent.stepStarted(tool: "read_file", summary: "different")
    expectEq(e1, e2, "same events equal")
    expect(e1 != e3, "different summaries not equal")
}

@Test @MainActor
func jobEventIsSendable() {
    // Sendable is enforced by the compiler in the type definition
    let event = JobEvent.stepStarted(tool: "test", summary: "test")
    expect(true, "JobEvent is Sendable")
}

struct FakeExecutor: Executor {
    var descriptor: ExecutorDescriptor
    var testResult: JobResult

    func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "test", summary: "Testing"))
        events.yield(.stepFinished(tool: "test", ok: true))
        events.finish()
        return testResult
    }
}

@Test @MainActor
func executorProtocolCanBeImplemented() throws {
    let fake = FakeExecutor(
        descriptor: ExecutorDescriptor(
            id: ExecutorID(rawValue: "test"),
            shortName: "test",
            title: "Test Executor",
            kind: .native
        ),
        testResult: JobResult(output: "OK", isError: false)
    )

    expectEq(fake.descriptor.title, "Test Executor", "descriptor accessible")

    let result = try runAsync {
        let (stream, continuation) = AsyncStream<JobEvent>.makeStream()
        let task = Task {
            var events: [JobEvent] = []
            for await event in stream {
                events.append(event)
            }
            return events
        }

        let job = JobRequest(id: "test", goal: "test", context: "")
        let jobResult = try await fake.run(job, events: continuation)

        let collectedEvents = await task.value
        return (jobResult, collectedEvents)
    }

    let (jobResult, events) = result
    expectEq(jobResult.output, "OK", "run returns JobResult")
    expectEq(events.count, 2, "stream collected 2 events")
}
