import Foundation

/// 16h-2: which job an event comes from. Minted by whoever starts the job
/// (the voice bridge, the chat), never by the executor: the executor only
/// reports, and the projection must tell a queued job from the running one.
public struct JobID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public static func mint() -> JobID { JobID(UUID().uuidString) }
    public var description: String { raw }
}

/// A job while it runs: the live card's whole state. In Core since Wave 12a
/// because the session projection carries it and Core cannot see UI.
public struct JobTimeline: Equatable, Sendable {
    public var goal: String?
    public var startedAt: Date
    public var steps: [JobStepInfo]
    /// Nil for producers that do not tag their events (the parent's own
    /// cards and gates, older callers): nil only ever matches nil.
    public var id: JobID?
    /// This job already had one of its own actions approved (10c 3B.4). On
    /// the timeline so it can never outlive the job it belongs to.
    public var approvedOnce = false
    /// A turn of the user's own opened while this job ran: the chrome shows
    /// her turn, and the row comes back at rest. On the timeline so that a
    /// job that ends takes the flag with it.
    public var behindTurn = false

    public init(
        goal: String?, startedAt: Date = Date(), steps: [JobStepInfo] = [], id: JobID? = nil
    ) {
        self.goal = goal
        self.startedAt = startedAt
        self.steps = steps
        self.id = id
    }

    /// "Write: prueba1.md", or the bare tool when there is nothing to say.
    /// The path after the colon is what `JobSteps.summary` counts.
    public static func step(_ tool: String, _ summary: String) -> JobStepInfo {
        JobStepInfo(tool: tool, label: summary.isEmpty ? tool : "\(tool): \(summary)")
    }
}
