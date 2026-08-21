import Foundation

public struct JobRequest: Sendable, Equatable {
    public var id: String
    public var goal: String
    public var context: String
    public var attachments: [String]

    public init(
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

public struct JobResult: Sendable, Equatable {
    public var output: String
    public var isError: Bool
    public var sessionId: String?

    public init(
        output: String,
        isError: Bool,
        sessionId: String? = nil
    ) {
        self.output = output
        self.isError = isError
        self.sessionId = sessionId
    }
}

public enum JobEvent: Sendable, Equatable {
    case stepStarted(tool: String, summary: String)
    case stepFinished(tool: String, ok: Bool)
    case approvalRequested(ApprovalRequest)
    case thought(String)
}

public protocol Executor: Sendable {
    var descriptor: ExecutorDescriptor { get }
    func run(
        _ job: JobRequest,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult
}

/// Protocol for submitting handoffs and tracking execution.
/// Abstracts the job runner for dependency injection into UI.
public protocol JobSubmitter: Sendable {
    func submit(
        _ handoff: Handoff,
        events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult
    func cancel() async
    /// The UI must be able to answer a pending approval: without this the
    /// request only ever ends in the 120s auto-deny.
    func resolveApproval(requestId: String, approved: Bool) async
    var isBusy: Bool { get async }
}
