import Foundation

package struct JobRequest: Sendable, Equatable {
    package var id: String
    package var goal: String
    package var context: String
    package var attachments: [String]

    package init(
        id: String,
        goal: String,
        context: String,
        attachments: [String] = []
    ) {
        self.id = id
        self.goal = goal
        self.context = context
        self.attachments = attachments
    }
}

package struct JobResult: Sendable, Equatable {
    package var output: String
    package var isError: Bool
    package var sessionId: String?
    /// 16h-2: someone stopped it (the island, the menu, "para"). Not a
    /// failure to announce: the user already knows, she asked for it.
    package var cancelled: Bool

    package init(
        output: String,
        isError: Bool,
        sessionId: String? = nil,
        cancelled: Bool = false
    ) {
        self.output = output
        self.isError = isError
        self.sessionId = sessionId
        self.cancelled = cancelled
    }
}

package enum JobEvent: Sendable, Equatable {
    /// What was delegated. Chat knows it up front; a voice-born job only
    /// exists as events, and without this its record in the thread is
    /// anonymous — which is exactly what made "why did it search instead of
    /// create?" undiagnosable.
    case started(goal: String)
    /// `id` pairs a step's end with its start. Nil for producers that have no
    /// id of their own: their end then closes the oldest open step of the tool.
    case stepStarted(tool: String, summary: String, id: String? = nil)
    case stepFinished(tool: String, ok: Bool, id: String? = nil)
    case approvalRequested(ApprovalRequest)
    case thought(String)
    /// What the interface should paint, straight from the tool that produced
    /// it. Deliberately NOT part of the tool's text result: a payload that
    /// travels through the model's context comes back rewritten, and a
    /// rewritten coordinate is a pin in the wrong street.
    case card(Card)
    /// The user said no (Wave 10c 3B.4): a decision, painted as one — not a
    /// failed step. The model reads `denied_by_user` on its side.
    case approvalDenied(tool: String)
    /// Answered from the session's memory, without the sheet: "allowed, as
    /// before" / "denied, as before".
    case approvalRemembered(tool: String, approved: Bool)
    /// Wave 20d B: a step ran on its own band (no sheet); the way back.
    case acted(UndoReceipt)
}

package protocol Executor: Sendable {
    var descriptor: ExecutorDescriptor { get }
    func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult
}

/// Protocol for submitting handoffs and tracking execution.
/// Abstracts the job runner for dependency injection into UI.
package protocol JobSubmitter: Sendable {
    func submit(
        _ handoff: Handoff,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult
    func cancel() async
    /// One job's own stop (16q-1). Not defaulted: a submitter that forgot it
    /// would silently stop nothing, or too much.
    func cancel(job id: JobID) async
    /// Same as `submit(_:events:)` under the id its owner minted, so
    /// `cancel(job:)` can find the job. Not defaulted either.
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult
    /// The UI must be able to answer a pending approval: without this the
    /// request only ever ends in the 120s auto-deny.
    func resolveApproval(requestId: String, approved: Bool) async
    /// Wave 10c: the sheet's "remember for this session". Submitters without
    /// a memory take the default and drop the flag.
    func resolveApproval(requestId: String, approved: Bool, remember: Bool) async
    var isBusy: Bool { get async }
}

extension JobSubmitter {
    package func resolveApproval(requestId: String, approved: Bool, remember: Bool) async {
        await resolveApproval(requestId: requestId, approved: approved)
    }
}
