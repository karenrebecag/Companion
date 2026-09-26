import CompanionCore
import Foundation

/// The hold's timeline: committing it, a parent tool's marks on it, and
/// flushing it to the log. Split out of VoiceSession when it hit the
/// 800-line gate (Wave DM0). What they touch is not `private` any more but
/// still actor-isolated: the actor, not the access level, is what keeps
/// this state single-threaded.
extension VoiceSession {
    /// The turn just committed: everything from here belongs to this hold,
    /// including whatever parent-tool answer the server sends back for it.
    func commitTimeline() {
        timeline.mark(.committed, at: now())
        toolGeneration = holdGeneration
    }

    /// The runtime reports the two instants of a parent tool. A mark for a
    /// hold that already committed and moved on is a stranger's — a fresh
    /// press reset the clock before the server answered — and is dropped
    /// instead of corrupting the hold now in flight (review DM0 2026-09-22).
    func markTool(_ point: TurnTimeline.Point) {
        guard toolGeneration == holdGeneration else { return }
        timeline.mark(point, at: now())
    }

    /// The hold's line goes to the log once, when the agent's first audio
    /// lands or when the hold is over without it.
    func flushTimeline() {
        guard let line = timeline.line() else { return }
        lastTimeline = timeline
        timeline = TurnTimeline()
        Log.app(line)
    }
}
