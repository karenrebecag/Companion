import CompanionCore
import CompanionServices
import Foundation

// Job submitters and text boxes the voice tests of both targets share.

package final class CapturingSubmitter: JobSubmitter, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _goals: [String] = []
    package var goals: [String] { lock.withLock { _goals } }

    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock { _goals.append(handoff.goal) }
        return JobResult(output: "ok", isError: false)
    }
    package func cancel() async {}
    package func cancel(job id: JobID) async { await cancel() }
    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    package func resolveApproval(requestId: String, approved: Bool) async {}
    package var isBusy: Bool { get async { false } }
}

package final class TextBox: @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var texts: [String] = []
    package func append(_ text: String) { lock.withLock { texts.append(text) } }
    package var all: [String] { lock.withLock { texts } }
}

package struct FixedSubmitter: JobSubmitter {
    package let result: JobResult

    package init(result: JobResult) {
        self.result = result
    }
    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult { result }
    package func cancel() async {}
    package func cancel(job id: JobID) async { await cancel() }
    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    package func resolveApproval(requestId: String, approved: Bool) async {}
    package var isBusy: Bool { get async { false } }
}

package struct SteppingSubmitter: JobSubmitter {
    package init() {}

    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "read_file", summary: "leyendo"))
        events.yield(.stepFinished(tool: "read_file", ok: true))
        // El puente drena en paralelo; un respiro para que le lleguen.
        try? await Task.sleep(for: .milliseconds(10))
        return JobResult(output: "ok", isError: false)
    }
    package func cancel() async {}
    package func cancel(job id: JobID) async { await cancel() }
    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    package func resolveApproval(requestId: String, approved: Bool) async {}
    package var isBusy: Bool { get async { false } }
}
