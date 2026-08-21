import CompanionCore
import Foundation

/// Delegation from a voice turn. Lives apart from VoiceSession so the session
/// stays about the turn and this stays about the job.
enum VoiceJobBridge {
    /// Runs the specialist off the voice turn: the conversation must not
    /// stall while a job works. The outcome closes the circuit twice — the
    /// text lands in the shared thread AND the voice model gets told via
    /// `announce`, so it narrates reality instead of promising forever.
    /// `onEvent` feeds the UI (steps, approvals): a drained-and-discarded
    /// stream meant approvals died in the 120s auto-deny unseen.
    static func run(
        _ handoff: Handoff,
        jobs: any JobSubmitter,
        thread: any ConversationPresenting,
        onEvent: (@Sendable (JobEvent) -> Void)? = nil,
        announce: (@Sendable (String) async -> Void)? = nil
    ) async {
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let pump = Task {
            for await event in stream { onEvent?(event) }
        }
        defer { pump.cancel() }
        do {
            let result = try await jobs.submit(handoff, events: sink)
            sink.finish()
            if result.isError {
                await thread.appendStatus(
                    Escalation.jobFailedStatus(handoff.goal, detail: result.output))
                await announce?(Escalation.jobFailedAnnouncement(handoff.goal))
            } else {
                await thread.appendAssistant(result.output)
                await announce?(Escalation.jobDoneAnnouncement(handoff.goal))
            }
        } catch {
            sink.finish()
            Log.app("voice: job failed (\(error))")
            await thread.appendStatus(
                Escalation.jobFailedStatus(handoff.goal, detail: ""))
            await announce?(Escalation.jobFailedAnnouncement(handoff.goal))
        }
    }
}
