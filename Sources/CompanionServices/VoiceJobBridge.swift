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
    /// stream meant approvals died in the auto-deny (ApprovalTiming) unseen.
    static func run(
        _ handoff: Handoff,
        jobs: any JobSubmitter,
        thread: any ConversationPresenting,
        onEvent: (@Sendable (SessionEvent) -> Void)? = nil,
        announce: (@Sendable (JobAnnouncement) async -> Void)? = nil,
        language: AppLanguage = .en
    ) async {
        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let pump = Task { () -> Bool in
            var card = false
            for await event in stream {
                if case .card = event { card = true }
                onEvent?(.job(event))
            }
            return card
        }
        defer { pump.cancel() }
        // Named up front: the runner says it too, but a submitter that does
        // not must still leave a card with a goal on it.
        onEvent?(.job(.started(goal: handoff.goal)))
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
            await announce?(JobAnnouncement(goal: handoff.goal, outcome: .queued, language: language))
        }

        do {
            let result = try await jobs.submit(handoff, events: sink)
            sink.finish()
            onEvent?(.jobFinished(ok: !result.isError))
            if result.isError {
                await thread.appendStatus(Escalation.jobFailedStatus(
                    handoff.goal, detail: result.output, language))
                await announce?(JobAnnouncement(
                    goal: handoff.goal, outcome: .failed(reason: result.output), language: language))
            } else {
                // The result travels once: the specialist's text IS the
                // assistant message. The voice never reads it back — a card
                // or a code block cannot survive being spoken; it acknowledges
                // (realtime) or says a short summary through the mouth's
                // guards (classic, code review 2026-09-25 HIGH-B).
                await thread.appendAssistant(result.output)
                // The stream ended with the job, so the pump finishes now and
                // says whether a card was painted: a card carries the detail
                // and the voice keeps to a line (16h-1 H2).
                let sawCard = await pump.value
                await announce?(JobAnnouncement(
                    goal: handoff.goal, outcome: .done(result: result.output), language: language,
                    hasCard: sawCard || SpeechBudget.hasCard(in: result.output)))
            }
        } catch {
            sink.finish()
            onEvent?(.jobFinished(ok: false))
            Log.app("voice: job failed (\(error))")
            // A thrown error is still a reason: silence here is what made the
            // voice fall back on inventing an outcome.
            let reason = JobRunner.failureText(for: error, language)
            await thread.appendStatus(Escalation.jobFailedStatus(
                handoff.goal, detail: reason, language))
            await announce?(JobAnnouncement(
                goal: handoff.goal, outcome: .failed(reason: reason), language: language))
        }
    }
}
