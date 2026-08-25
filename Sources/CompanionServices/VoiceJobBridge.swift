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
        announce: (@Sendable (String) async -> Void)? = nil,
        language: AppLanguage = .en
    ) async {
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let pump = Task {
            for await event in stream { onEvent?(event) }
        }
        defer { pump.cancel() }
        // Queued, not refused and never at the cost of what is running.
        // `JobQueue` already serialises execution, so submitting is enough to
        // make it wait; what was missing was saying so, because a second job
        // announcing itself as if it had started is what made two of them
        // fight over one card and one approval slot.
        let waiting = await jobs.isBusy
        await thread.appendStatus(
            waiting
                ? Escalation.queuedNotice(handoff.goal, language)
                : Escalation.heardNotice(handoff.goal, language))
        if waiting {
            await announce?(
                Escalation.queuedAnnouncement(handoff.goal, language))
        }

        do {
            let result = try await jobs.submit(handoff, events: sink)
            sink.finish()
            if result.isError {
                await thread.appendStatus(Escalation.jobFailedStatus(
                    handoff.goal, detail: result.output, language))
                await announce?(Escalation.jobFailedAnnouncement(
                    handoff.goal,
                    reason: Escalation.resultSummary(result.output),
                    language))
            } else {
                // The result travels once: the specialist's text IS the
                // assistant message. The voice only acknowledges — reading it
                // back made a second message for one result, and a card or a
                // code block cannot survive being spoken.
                await thread.appendAssistant(result.output)
                await announce?(
                    Escalation.jobDoneAnnouncement(handoff.goal, language))
            }
        } catch {
            sink.finish()
            Log.app("voice: job failed (\(error))")
            // A thrown error is still a reason: silence here is what made the
            // voice fall back on inventing an outcome.
            let reason = JobRunner.failureText(for: error, language)
            await thread.appendStatus(Escalation.jobFailedStatus(
                handoff.goal, detail: reason, language))
            await announce?(Escalation.jobFailedAnnouncement(
                handoff.goal, reason: reason, language))
        }
    }
}
