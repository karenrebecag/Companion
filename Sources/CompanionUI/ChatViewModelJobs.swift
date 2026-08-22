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

    func finishJob() {
        job = nil
    }

    func appendStep(_ step: JobStepInfo) {
        if job == nil { startJob(goal: nil) }
        job?.steps.append(step)
    }

    /// One seam for every job event, chat-born or voice-born: steps and
    /// thoughts paint the timeline, an approval lands where the sheet looks.
    public func receiveJobEvent(_ event: JobEvent) {
        switch event {
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
        case .thought(let text):
            appendStep(JobStepInfo(tool: JobSteps.Thinking.tool, label: text))
        }
        persist()
    }

    public func answerApproval(_ approved: Bool) {
        guard let request = pendingApproval, let submitter = jobSubmitter else { return }
        pendingApproval = nil
        messages.append(ChatMessage(
            isStatus: true, text: ChatCopy.approvalAnswer(approved)))
        toast(ChatCopy.approvalAnswer(approved),
              level: approved ? .info : .error)
        Task { await submitter.resolveApproval(
            requestId: request.requestId, approved: approved) }
    }

    /// The whole life of a delegated turn: preface, live card, result. Errors
    /// close the card first — a card still ticking under a failure notice is
    /// the app lying about what it is doing.
    func runJob(
        preface: String, handoff: Handoff, submitter: any JobSubmitter
    ) async {
        if !preface.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: preface))
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
            finishJob()
            if result.isError {
                messages.append(ChatMessage(
                    isStatus: true,
                    text: Escalation.jobFailedStatus(
                        handoff.goal, detail: result.output)))
                toast(ChatCopy.jobFailed, level: .error)
            } else {
                messages.append(ChatMessage(
                    role: .assistant, text: result.output))
                toast(ChatCopy.jobDone)
            }
        } catch {
            sink.finish()
            finishJob()
            messages.append(ChatMessage(
                role: .assistant,
                text: "Error en el encargo: \(error.localizedDescription)"))
            toast(ChatCopy.jobFailed, level: .error)
        }
    }
}
