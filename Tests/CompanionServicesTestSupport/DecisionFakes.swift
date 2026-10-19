import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import Foundation

// Judges, executors and answers the decision tests of the voice and the
// typed paths share.

package final class ScriptedHosted: HostedDecisionProviding, @unchecked Sendable {
    package let isConfigured: Bool
    private let body: @Sendable (DecisionQuestion) -> DecisionAnswer?
    private let lock = NSLock()
    private var _calls = 0
    package var calls: Int { lock.withLock { _calls } }

    package init(configured: Bool, body: @escaping @Sendable (DecisionQuestion) -> DecisionAnswer?) {
        self.isConfigured = configured
        self.body = body
    }

    package func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
        lock.withLock { _calls += 1 }
        return body(question)
    }
}

package struct NoArbiter: Arbitrating {
    package init() {}
    package func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? { nil }
}

package final class CallCounter: @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var _count = 0
    package var count: Int { lock.withLock { _count } }
    package func increment() { lock.withLock { _count += 1 } }
}

package final class RecordingSystemActing: SystemActing, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var _actCount = 0
    package var supportsAnswer = true
    package var actResult: SystemActResult = .done
    package var actCount: Int { lock.withLock { _actCount } }

    package func supports(_ plan: Plan) -> Bool { supportsAnswer }
    package func act(_ plan: Plan) async -> SystemActResult {
        lock.withLock { _actCount += 1 }
        return actResult
    }
}

/// All but 0.01 of the mass on `choice`: a sure answer.
package func peaked(_ choice: String, _ ids: [String]) -> DecisionAnswer? {
    guard !ids.isEmpty, Set(ids).contains(choice) else { return nil }
    var distribution: [String: Double] = [:]
    if ids.count == 1 {
        distribution[choice] = 1
    } else {
        let share = 0.01 / Double(ids.count - 1)
        var rest = 0.0
        for id in ids where id != choice {
            distribution[id] = share
            rest += share
        }
        distribution[choice] = 1 - rest
    }
    return DecisionAnswer(
        choice: choice, distribution: distribution,
        confidence: DecisionMath.sharpness(distribution)
    ).validated(against: ids)
}

/// A judge sure the words ask to empty the trash.
package func trashProvider() -> ScriptedDecision {
    ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peaked("system", question.offeredIds)
        case DecisionHead.system: return peaked("empty_trash", question.offeredIds)
        default: return nil
        }
    }
}

/// A judge sure the words are a background job whose goal is all of them.
package func taskProvider() -> ScriptedDecision {
    ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peaked("task", question.offeredIds)
        case DecisionHead.goalStart: return peaked("t0", question.offeredIds)
        case DecisionHead.goalEnd: return question.offeredIds.last.flatMap { peaked($0, question.offeredIds) }
        default: return nil
        }
    }
}

/// Jobs that run until stopped one by one, stopped all at once, or told to
/// finish; bounded so a test that forgets one does not spin the suite.
package final class KeyedJobs: JobSubmitter, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var _live: [JobID] = []
    private var _stopped: [JobID] = []
    private var _finishing: Set<JobID> = []
    private var _stoppedAll = 0
    package var live: [JobID] { lock.withLock { _live } }
    package var stopped: [JobID] { lock.withLock { _stopped } }
    package var stoppedAll: Int { lock.withLock { _stoppedAll } }

    package func finish(_ id: JobID) { lock.withLock { _ = _finishing.insert(id) } }

    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, as: .mint(), events: events)
    }

    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock { _live.append(id) }
        defer { lock.withLock { _live.removeAll { $0 == id } } }
        for _ in 0 ..< 1000 {
            let (stopped, done) = lock.withLock {
                (_stopped.contains(id) || _stoppedAll > 0, _finishing.contains(id))
            }
            if stopped { return JobResult(output: "", isError: false, cancelled: true) }
            if done { return JobResult(output: "listo", isError: false) }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return JobResult(output: "", isError: true)
    }

    package func cancel() async { lock.withLock { _stoppedAll += 1 } }
    package func cancel(job id: JobID) async { lock.withLock { _stopped.append(id) } }
    package func resolveApproval(requestId: String, approved: Bool) async {}
    package var isBusy: Bool { get async { !live.isEmpty } }
}
