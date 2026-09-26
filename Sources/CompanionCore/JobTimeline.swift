import Foundation

/// A job while it runs: the live card's whole state. In Core since Wave 12a
/// because the session projection carries it and Core cannot see UI.
public struct JobTimeline: Equatable, Sendable {
    public var goal: String?
    public var startedAt: Date
    public var steps: [JobStepInfo]

    public init(
        goal: String?, startedAt: Date = Date(), steps: [JobStepInfo] = []
    ) {
        self.goal = goal
        self.startedAt = startedAt
        self.steps = steps
    }

    /// "Write: prueba1.md", or the bare tool when there is nothing to say.
    /// The path after the colon is what `JobSteps.summary` counts.
    public static func step(_ tool: String, _ summary: String) -> JobStepInfo {
        JobStepInfo(tool: tool, label: summary.isEmpty ? tool : "\(tool): \(summary)")
    }
}
