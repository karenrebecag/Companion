import CompanionCore
import Foundation

/// A job while it runs: the live card's whole state. The thread used to get
/// one status line per step, which said what happened but never what is
/// happening now, nor for how long.
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
}

/// Everything the view model does with a delegated job. Split out of
/// ChatViewModel when it crossed the 400-line gate: the model stays about the
/// conversation, this stays about the specialist working inside it.
extension ChatViewModel {
    /// The chat path knows the goal up front; a voice-born job only shows up
    /// as events, so the card starts nameless rather than not at all.
    public func startJob(goal: String?) {
        job = JobTimeline(goal: goal)
    }

    /// The live card is for the wait; this is the record. Replacing the old
    /// status line with a card that vanishes left no trace of WHAT was
    /// delegated, which made a specialist that searched instead of creating
    /// impossible to diagnose.
    func finishJob() {
        defer { job = nil }
        guard let job, let goal = job.goal else { return }
        var text = String(format: Localized.string("job.record"), goal)
        if let summary = JobSteps.summary(job.steps, Localized.language()) {
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
        guard job != nil, let submitter = jobSubmitter else { return }
        cancelledJob = true
        Task { await submitter.cancel() }
        // The record first, so what it managed to do survives the stop — the
        // same promise the reference makes: stopping keeps the work so far.
        finishJob()
        messages.append(ChatMessage(isStatus: true, text: ChatCopy.jobStopped))
        toast(ChatCopy.jobStopped, level: .info)
        persist()
    }

    func appendStep(_ step: JobStepInfo) {
        if job == nil { startJob(goal: nil) }
        job?.steps.append(step)
    }

    /// One seam for every job event, chat-born or voice-born: steps and
    /// thoughts paint the timeline, an approval lands where the sheet looks.
    public func receiveJobEvent(_ event: JobEvent) {
        switch event {
        case .started(let goal):
            // Chat already named the job; a voice-born one gets its name here
            // so the record it leaves behind is not anonymous.
            if job == nil { startJob(goal: goal) } else { job?.goal = goal }
        case .stepStarted(let tool, let summary):
            appendStep(JobStepInfo(
                tool: tool, label: ChatCopy.step(tool, summary)))
        case .stepFinished:
            // One row per tool use, not two: the card shows the step, and the
            // next one starting is what "done" looks like.
            break
        case .approvalRequested(let request):
            // Surface it: a request that only prints text ends in the
            // auto-deny with the user none the wiser.
            pendingApproval = request
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
        case .thought(let text):
            appendStep(JobStepInfo(tool: JobSteps.Thinking.tool, label: text))
        }
        persist()
    }

    public func answerApproval(_ approved: Bool) {
        guard let request = pendingApproval, let submitter = jobSubmitter else { return }
        pendingApproval = nil
        let wasFirst = !jobHasApprovedAction
        if approved { jobHasApprovedAction = true }
        messages.append(ChatMessage(
            isStatus: true, text: ChatCopy.approvalAnswer(approved)))
        toast(ChatCopy.approvalAnswer(approved),
              level: approved ? .info : .error)
        Task { await submitter.resolveApproval(
            requestId: request.requestId, approved: approved) }
        // Refusing the first step stops the whole job. Refusing a later one
        // only narrows a job you already agreed to: by then it is going where
        // you sent it, and aborting would throw away what you authorised.
        if !approved, wasFirst, job != nil {
            cancelJob()
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
        jobHasApprovedAction = false
        persist()

        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        _ = Task {
            for await event in stream { receiveJobEvent(event) }
        }

        do {
            let result = try await submitter.submit(handoff, events: sink)
            sink.finish()
            finishJob()
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
            finishJob()
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
