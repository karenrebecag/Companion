import Foundation

/// What the rollover policy needs to know about the thread and its guards
/// (Wave 15a). Pure data: ChatViewModel builds it from its own state and the
/// session projection; the policy itself never reaches for either.
public struct ConversationActivity: Sendable, Equatable {
    public var lastActivity: Date?
    public var turnInFlight: Bool
    public var jobRunning: Bool
    public var approvalsPending: Bool
    public var liveRealtime: Bool

    public init(
        lastActivity: Date?,
        turnInFlight: Bool,
        jobRunning: Bool,
        approvalsPending: Bool,
        liveRealtime: Bool
    ) {
        self.lastActivity = lastActivity
        self.turnInFlight = turnInFlight
        self.jobRunning = jobRunning
        self.approvalsPending = approvalsPending
        self.liveRealtime = liveRealtime
    }
}

/// Ephemeral conversations by inactivity (Wave 15a): past `idleLimit` since
/// the thread's own last write, with nothing open that a fresh id would
/// strand, a turn archives the stale thread and starts a new one instead of
/// resuming it.
public enum ConversationRollover {
    public static let idleLimit: TimeInterval = 300

    /// nil `lastActivity`, any open work, or a clock that went backwards →
    /// false. A backwards clock only ever WITHHOLDS a rollover, never forces
    /// one: a wrong answer here must fail toward keeping the thread, not
    /// toward discarding it.
    public static func shouldRollover(
        _ activity: ConversationActivity, now: Date,
        limit: TimeInterval = idleLimit
    ) -> Bool {
        guard let lastActivity = activity.lastActivity else { return false }
        guard !activity.turnInFlight, !activity.jobRunning,
              !activity.approvalsPending, !activity.liveRealtime
        else { return false }
        let elapsed = now.timeIntervalSince(lastActivity)
        guard elapsed >= 0 else { return false }
        return elapsed >= limit
    }
}
