import CompanionCore
import Foundation

/// Everything the view model does with a delegated job. Split out of
/// ChatViewModel when it crossed the 400-line gate: the model stays about the
/// conversation, this stays about the specialist working inside it.
///
/// Since Wave 12a the job's state lives in the session projection: this file
/// publishes events and writes the thread; it never keeps a card of its own.
extension ChatViewModel {
    /// Non-nil while a specialist works: the live card owns the steps.
    public var job: JobTimeline? { session.projection.job }

    /// The first request waiting for the sheet.
    public var pendingApproval: ApprovalRequest? { session.projection.approval }

    /// The chat path knows the goal up front.
    public func startJob(goal: String) {
        session.send(.job(.started(goal: goal)))
    }

    /// The live card is for the wait; this is the record. Replacing the old
    /// status line with a card that vanishes left no trace of WHAT was
    /// delegated, which made a specialist that searched instead of creating
    /// impossible to diagnose.
    func finishJob(ok: Bool = true) {
        let timeline = session.projection.job
        session.send(.jobFinished(ok: ok))
        record(timeline)
    }

    private func record(_ timeline: JobTimeline?) {
        guard let timeline, let goal = timeline.goal else { return }
        var text = String(format: Localized.string("job.record"), goal)
        if let summary = JobSteps.summary(timeline.steps, Localized.language()) {
            text += " · " + summary
        }
        messages.append(ChatMessage(isStatus: true, text: text))
    }

    /// The brake. `JobRunner.cancel()` has existed since Wave 4 and had no
    /// caller anywhere in Sources — built, tested, and never wired to a pedal.
    /// Without it, a job started on a misheard sentence could not be stopped:
    /// denying a permission only refused one command, and correcting yourself
    /// out loud did nothing at all.
    public func cancelJob() {
        guard let timeline = session.projection.job, jobSubmitter != nil else { return }
        let effects = session.send(.stop)
        guard effects.contains(.cancelJob) else { return }
        noteStopped(timeline)
    }

    /// The record first, so what it managed to do survives the stop — the
    /// same promise the reference makes: stopping keeps the work so far.
    private func noteStopped(_ timeline: JobTimeline) {
        cancelledJob = true
        record(timeline)
        messages.append(ChatMessage(isStatus: true, text: ChatCopy.jobStopped))
        toast(ChatCopy.jobStopped, level: .info)
        persist()
    }

    /// One seam for every job event, chat-born or voice-born. The thread
    /// keeps what deserves a line; the session keeps the state.
    public func receiveJobEvent(_ event: JobEvent) {
        switch event {
        case .started, .stepStarted, .stepFinished, .thought, .acted:
            break
        case .approvalRequested:
            // Surface it: a request that only prints text ends in the
            // auto-deny with the user none the wiser.
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.approvalPending))
        case .card(let card):
            // Painted straight from the lookup. Its recall is a marker, never
            // the payload: the model must not be able to quote back a
            // coordinate it never read.
            messages.append(ChatMessage(
                role: .assistant, text: "", card: card,
                recall: Recall(
                    role: .assistant,
                    content: ChatCopy.cardShown(card))))
        case .approvalDenied(let tool):
            messages.append(ChatMessage(isStatus: true, text: ChatCopy.approvalDeniedTool(tool)))
        case .approvalRemembered(let tool, let approved):
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.approvalRemembered(tool, approved: approved)))
        }
        session.send(.job(event))
        persist()
    }

    /// What the voice session reports: job events keep their thread lines,
    /// everything else goes straight to the reducer.
    public func receive(_ event: SessionEvent) {
        if case .job(let jobEvent) = event {
            receiveJobEvent(jobEvent)
        } else {
            session.send(event)
        }
    }

    /// `remember` is the sheet's toggle (Wave 10c 3B.3). The reducer decides
    /// whether refusing this step stops the whole job (10c 3B.4) and where
    /// the answer travels; the thread only says what happened.
    public func answerApproval(_ approved: Bool, remember: Bool = false) {
        guard let request = pendingApproval else { return }
        let timeline = session.projection.job
        let effects = session.send(.approvalAnswered(
            requestId: request.requestId, approved: approved, remember: remember))
        messages.append(ChatMessage(
            isStatus: true, text: ChatCopy.approvalAnswer(approved)))
        toast(ChatCopy.approvalAnswer(approved),
              level: approved ? .info : .error)
        if effects.contains(.cancelJob), let timeline {
            noteStopped(timeline)
        }
    }

    /// The delegate call as the provider expects to see it echoed back.
    static func arguments(_ handoff: Handoff) -> String {
        let payload: [String: String] = [
            "goal": handoff.goal, "context": handoff.context,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }

    /// The whole life of a delegated turn: preface, live card, result. Errors
    /// close the card first — a card still ticking under a failure notice is
    /// the app lying about what it is doing.
    func runJob(
        preface: String, handoff: Handoff, submitter: any JobSubmitter
    ) async {
        // The delegate call has to survive in the history, or the result that
        // answers it arrives orphaned: the API rejects a tool message whose id
        // matches no call, and a model that never sees the call believes it
        // wrote the report itself. We mint the id — the history we send is the
        // one we build, and the spec only asks that both sides of it agree.
        let callID = UUID().uuidString
        let call = ToolCallRef(
            id: callID, name: "delegate", arguments: Self.arguments(handoff))
        if !preface.isEmpty {
            messages.append(ChatMessage(
                role: .assistant, text: preface,
                recall: Recall(
                    role: .assistant, content: preface, toolCalls: [call])))
        } else {
            // No preface to show, but the call still has to be remembered:
            // the status line is already the record of WHAT was delegated, so
            // it carries the turn instead of inventing an empty bubble.
            messages.append(ChatMessage(
                isStatus: true,
                text: ChatCopy.handoff(handoff),
                recall: Recall(role: .assistant, content: "", toolCalls: [call])))
        }
        startJob(goal: handoff.goal)
        persist()

        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        _ = Task {
            for await event in stream { receiveJobEvent(event) }
        }

        do {
            let result = try await submitter.submit(handoff, events: sink)
            sink.finish()
            finishJob(ok: !result.isError)
            // Stopped while it was finishing: the answer is no longer wanted.
            guard !cancelledJob else {
                cancelledJob = false
                return
            }
            if result.isError {
                messages.append(ChatMessage(
                    isStatus: true,
                    text: Escalation.jobFailedStatus(
                        handoff.goal, detail: result.output)))
                toast(ChatCopy.jobFailed, level: .error)
            } else {
                // Shown whole, remembered bounded, and attributed to the tool
                // that produced it rather than to the model that asked for it.
                messages.append(ChatMessage(
                    role: .assistant, text: result.output,
                    recall: Recall(
                        role: .tool,
                        content: ConversationMemory.recall(result.output),
                        toolCallID: callID)))
                toast(ChatCopy.jobDone)
            }
        } catch {
            sink.finish()
            finishJob(ok: false)
            // A stop is not a failure: cancelJob already wrote the record and
            // said so, and a second notice would read as something breaking.
            guard !cancelledJob else {
                cancelledJob = false
                return
            }
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.jobFailedNotice(error)))
            toast(ChatCopy.jobFailed, level: .error)
        }
    }
}
