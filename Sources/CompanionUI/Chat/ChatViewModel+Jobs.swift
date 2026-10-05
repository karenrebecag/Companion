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
    package var job: JobTimeline? { session.projection.job }

    /// The first request waiting for the sheet.
    package var pendingApproval: ApprovalRequest? { session.projection.approval }

    /// The chat path knows the goal up front.
    @discardableResult
    package func startJob(goal: String) -> JobID {
        let id = JobID.mint()
        chatJobID = id
        session.send(.job(.started(goal: goal), from: id))
        return id
    }

    /// The live card is for the wait; this is the record. Replacing the old
    /// status line with a card that vanishes left no trace of WHAT was
    /// delegated, which made a specialist that searched instead of creating
    /// impossible to diagnose. Only the chat's own job, by id (review 16h-2
    /// round 3): each job records itself when ITS end arrives, never
    /// whichever row happens to be in front.
    func finishJob(ok: Bool = true, id: JobID) {
        if chatJobID == id { chatJobID = nil }
        end(ok: ok, id: id)
    }

    private func end(ok: Bool, id: JobID?) {
        let timeline = timeline(of: id)
        session.send(.jobFinished(ok: ok, from: id))
        record(timeline)
    }

    /// Job `id`'s timeline, running or queued; nil when no row carries it.
    private func timeline(of id: JobID?) -> JobTimeline? {
        guard let id else { return nil }
        let shown = session.projection
        if shown.job?.id == id { return shown.job }
        return shown.queued.first { $0.id == id }
    }

    private func record(_ timeline: JobTimeline?) {
        guard let timeline, let goal = timeline.goal else { return }
        var text = String(format: Localized.string("job.record"), goal)
        if let summary = JobSteps.summary(timeline.steps, Localized.language()) {
            text += " · " + summary
        }
        messages.append(ChatMessage(isStatus: true, text: text))
    }

    /// One job's own stop (16q-1): the job card's, by id. The rest of the
    /// line keeps running; the thread records this job only if it is the
    /// chat's own.
    package func cancelJob(_ id: JobID) {
        guard jobSubmitter != nil else { return }
        let own = chatJobID == id ? timeline(of: id) : nil
        let effects = session.send(.stopJob(id))
        guard effects.contains(.cancelJobByID(id)) else { return }
        noteStopped(own)
    }

    /// The brake. `JobRunner.cancel()` has existed since Wave 4 and had no
    /// caller anywhere in Sources — built, tested, and never wired to a pedal.
    /// Without it, a job started on a misheard sentence could not be stopped:
    /// denying a permission only refused one command, and correcting yourself
    /// out loud did nothing at all.
    package func cancelJob() {
        guard session.projection.job != nil, jobSubmitter != nil else { return }
        let own = timeline(of: chatJobID)
        let effects = session.send(.stop)
        guard effects.contains(.cancelJob) else { return }
        noteStopped(own)
    }

    /// The clear takes the tasks with the chats. No "stopped" line: it would
    /// be the first line of the new thread. Their late events and results are
    /// dropped on two paths: `runJob` compares the history epoch it started
    /// in (the chat's own job), and `jobsStoppedByClear` recognises a voice
    /// job's events by id in `receiveJobEvent`.
    func stopJobsForClear() {
        let shown = session.projection
        for id in ([shown.job?.id] + shown.queued.map(\.id)).compactMap({ $0 }) {
            jobsStoppedByClear.insert(id)
            session.send(.stopJob(id))
        }
        // A job with no id cannot be stopped by it.
        if session.projection.job != nil || !session.projection.queued.isEmpty {
            session.send(.stop)
        }
        chatJobID = nil
        cancelledJob = false
    }

    /// The record first, so what it managed to do survives the stop — the
    /// same promise the reference makes: stopping keeps the work so far.
    /// `own` is the chat's job among the stopped ones; a voice job's stop
    /// leaves no record here and no mark on the chat's next ending.
    private func noteStopped(_ own: JobTimeline?) {
        if own != nil { cancelledJob = true }
        record(own)
        messages.append(ChatMessage(isStatus: true, text: ChatCopy.jobStopped))
        toast(ChatCopy.jobStopped, level: .info)
        persist()
    }

    /// One seam for every job event, chat-born or voice-born. The thread
    /// keeps what deserves a line; the session keeps the state.
    package func receiveJobEvent(_ event: JobEvent, from id: JobID?) {
        if let id, jobsStoppedByClear.contains(id) { return }
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
        session.send(.job(event, from: id))
        persist()
    }

    /// What the voice session reports: job events keep their thread lines,
    /// everything else goes straight to the reducer.
    package func receive(_ event: SessionEvent) {
        if case .job(let jobEvent, let id) = event {
            receiveJobEvent(jobEvent, from: id)
        } else if case .jobFinished(_, let id) = event, let id, jobsStoppedByClear.contains(id) {
            return
        } else if case .jobFinished(let ok, let id) = event {
            // A voice job's end records that job, found by its own id.
            end(ok: ok, id: id)
        } else {
            session.send(event)
        }
    }

    /// `remember` is the sheet's toggle (Wave 10c 3B.3). The reducer decides
    /// whether refusing this step stops the whole job (10c 3B.4) and where
    /// the answer travels; the thread only says what happened.
    /// The closure a sheet hands its buttons, bound to the request it was built
    /// for. Both sheet hosts use it, so the binding cannot drift between them.
    package func approvalAnswer(for request: ApprovalRequest) -> (Bool, Bool) -> Void {
        { [self] approved, remember in
            answerApproval(approved, remember: remember, requestId: request.requestId)
        }
    }

    /// `requestId` is the request the clicked sheet was showing: a click that
    /// outlived its sheet must not answer the request that replaced it, and
    /// the dwell guard alone only narrows that window.
    package func answerApproval(_ approved: Bool, remember: Bool = false, requestId: String) {
        guard let request = pendingApproval else {
            log("approval: ignored an answer for \(requestId); nothing is pending")
            return
        }
        guard request.requestId == requestId else {
            log("approval: ignored an answer for \(requestId); \(request.requestId) is pending")
            return
        }
        let own = timeline(of: chatJobID)
        let effects = session.send(.approvalAnswered(
            requestId: request.requestId, approved: approved, remember: remember))
        messages.append(ChatMessage(
            isStatus: true, text: ChatCopy.approvalAnswer(approved)))
        toast(ChatCopy.approvalAnswer(approved),
              level: approved ? .info : .error)
        // Refusing a job's first action stops that job (by id): the thread
        // records it only when it is the chat's own.
        if let stopped = effects.compactMap({ effect -> JobID? in
            if case .cancelJobByID(let id) = effect { id } else { nil }
        }).first {
            noteStopped(stopped == chatJobID ? own : nil)
        } else if effects.contains(.cancelJob) {
            noteStopped(own)
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
        // The id is this run's, captured: tagging with whatever job the chat
        // has at delivery time sent late steps out untagged (review 16h-2
        // round 3).
        let id = startJob(goal: handoff.goal)
        persist()
        // A clear in the meantime erased the chat this job belongs to: what
        // it still says has nowhere to go.
        let epoch = historyEpoch

        let (stream, sink) = AsyncStream<JobEvent>.makeStream()
        let pump = Task {
            for await event in stream where historyEpoch == epoch {
                receiveJobEvent(event, from: id)
            }
        }

        do {
            let result = try await submitter.submit(handoff, as: id, events: sink)
            // Drained before the end, or a step still in the pump lands
            // after it and opens an orphan row.
            sink.finish()
            await pump.value
            finishJob(ok: !result.isError, id: id)
            guard historyEpoch == epoch else { return }
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
            await pump.value
            finishJob(ok: false, id: id)
            guard historyEpoch == epoch else { return }
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
