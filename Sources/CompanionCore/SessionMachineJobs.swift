import Foundation

/// 16h-2: the specialist's jobs in the session reducer. Split from
/// SessionMachine.swift: this file is the one place that knows which job an
/// event belongs to, and the one rule for whether a job or her turn is in
/// front of the chrome.
extension SessionMachine {
    /// How many stopped (and, apart, finished) jobs are remembered.
    // HACK: capped list, oldest out. A job stopped this many stops ago that
    // still speaks would reopen its row. Upgrade trigger: the executor
    // reports its own end after cancel, and the list becomes "until its
    // end arrives" instead of a count.
    static let stoppedCap = 32

    /// The single rule (review 16h-2 B2): a running job shows its row unless
    /// a turn of the user's own is in front of it. Read by every place that
    /// picks a kind while a job exists.
    var jobInFront: Bool {
        guard let job = projection.job else { return false }
        return !job.behindTurn
    }

    /// Her turn is over: the job, if any, is in front again. A typed turn
    /// ends with its own reply, not with the voice.
    mutating func turnOver() {
        if !typedBusy { projection.job?.behindTurn = false }
    }

    mutating func observe(_ event: JobEvent, from id: JobID?) -> [SessionEffect] {
        switch event {
        case .approvalRequested(let request):
            return ask(request, from: id)
        case .card(let card):
            projection.cards = [.answer(card)]
        case .approvalDenied(let tool):
            projection.cards = [.approvalAnswered(tool: tool, approved: false, remembered: false)]
        case .approvalRemembered(let tool, let approved):
            projection.cards = [.approvalAnswered(tool: tool, approved: approved, remembered: true)]
        case .started(let goal):
            guard !isOver(id) else { return [] }
            start(goal, id)
        case .stepStarted(let tool, let summary):
            guard !isOver(id) else { return [] }
            append(JobTimeline.step(tool, summary), id)
        case .thought(let text):
            guard !isOver(id) else { return [] }
            append(JobStepInfo(tool: JobSteps.Thinking.tool, label: text), id)
        case .stepFinished(let tool, let ok):
            guard !isOver(id) else { return [] }
            // The runcard paints each step's fate (16m-2): the OLDEST still
            // running step of that tool is the one this answers.
            // HACK: name-only pairing. Parallel runs of one tool that finish
            // out of order mark the wrong row. Upgrade trigger: the first
            // executor that reports a tool-use id — carry it through
            // stepStarted/stepFinished and match on it instead.
            timeline(id) { job in
                if let index = job.steps.firstIndex(where: { $0.tool == tool && !$0.done }) {
                    job.steps[index].done = true
                    job.steps[index].failed = !ok
                }
            }
        }
        return []
    }

    /// The job's end. False when it names no job this machine shows.
    mutating func finish(_ id: JobID?) -> Bool {
        if let id { remember(id, in: &finishedJobs) }
        if let job = projection.job, job.id == id {
            projection.job = nil
            if !projection.queued.isEmpty {
                var next = projection.queued.removeFirst()
                next.behindTurn = job.behindTurn
                projection.job = next
            }
            return true
        }
        guard let index = projection.queued.firstIndex(where: { $0.id == id }) else { return false }
        projection.queued.remove(at: index)
        return false
    }

    /// A job that ended leaves no question on the sheet that nobody waits
    /// on (review 16h-2 round 3): its pending requests are refused.
    mutating func dropApprovals(of id: JobID?) -> [SessionEffect] {
        guard let id else { return [] }
        let dead = projection.approvalQueue.filter { approvalOwners[$0.requestId] == id }
        guard !dead.isEmpty else { return [] }
        projection.approvalQueue.removeAll { approvalOwners[$0.requestId] == id }
        for request in dead { approvalOwners[request.requestId] = nil }
        return dead.map { .resolveApproval(requestId: $0.requestId, approved: false, remember: false) }
    }

    /// Stop brakes everything that runs or waits (review 16h-2 B1); their
    /// late events are recognised by id from here on.
    mutating func noteStopped() {
        for id in [projection.job?.id].compactMap({ $0 }) + projection.queued.compactMap(\.id) {
            remember(id, in: &stoppedJobs)
        }
        projection.job = nil
        projection.queued = []
    }

    private func remember(_ id: JobID, in list: inout [JobID]) {
        list.append(id)
        if list.count > Self.stoppedCap { list.removeFirst(list.count - Self.stoppedCap) }
    }

    /// A tagged job is over when it was stopped or has ended: its late
    /// events (they travel on their own task) are leftovers, never a new
    /// row (review 16h-2 round 3). An untagged one cannot be told apart, so
    /// the old rule stands: after a Stop and before anything new starts,
    /// whatever speaks can only be the job just stopped.
    private func isOver(_ id: JobID?) -> Bool {
        guard let id else { return projection.interruption == .userStopped && projection.job == nil }
        return stoppedJobs.contains(id) || finishedJobs.contains(id)
    }

    private mutating func ask(_ request: ApprovalRequest, from id: JobID?) -> [SessionEffect] {
        // A stopped (or ended) job's request dies with it instead of
        // reopening the sheet (security review 2026-09-06). Only a tagged request can be
        // told to be that job's: an untagged one (the parent's gates, the
        // bridge's session grant) is nobody's job, and Stop's stale
        // `userStopped` was silently denying every such grant at rest (seen
        // live 2026-09-28; review 16h-2 round 3).
        if let id, isOver(id) {
            return [.resolveApproval(requestId: request.requestId, approved: false, remember: false)]
        }
        projection.approvalQueue.append(request)
        if let id { approvalOwners[request.requestId] = id }
        projection.cards = [.approval(request)]
        return []
    }

    /// Whether answering `request` answers the job in the row. By owner
    /// (review 16h-2 round 3): "a job is running" is not "this is its
    /// request" once a grant, a gate or a finished job's leftover shares the
    /// queue.
    func isActiveJobs(_ request: ApprovalRequest, owner: JobID?) -> Bool {
        guard let owner, let job = projection.job else { return false }
        return owner == job.id && ParentTool(rawValue: request.toolName) == nil
    }

    private mutating func start(_ goal: String, _ id: JobID?) {
        guard let job = projection.job else {
            projection.job = JobTimeline(goal: goal, id: id)
            begin()
            projection.kind = .processing(.subAgentRunning)
            return
        }
        if job.id == id {
            // A second announcement only names the job; its approvals so far
            // still count, and her turn, if in front, stays there.
            projection.job?.goal = goal
            if jobInFront { projection.kind = .processing(.subAgentRunning) }
            return
        }
        if let index = projection.queued.firstIndex(where: { $0.id == id }) {
            projection.queued[index].goal = goal
        } else {
            projection.queued.append(JobTimeline(goal: goal, id: id))
        }
    }

    /// A voice-born job only exists as events: a step before its name still
    /// opens the card, nameless rather than not at all — unless another job
    /// holds the row, whose card must never show a stranger's step.
    private mutating func append(_ step: JobStepInfo, _ id: JobID?) {
        if timeline(id, { $0.steps.append(step) }) { return }
        guard projection.job == nil else { return }
        projection.job = JobTimeline(goal: nil, steps: [step], id: id)
        projection.kind = .processing(.subAgentRunning)
    }

    /// Edits the timeline of job `id`, running or queued. False when no
    /// timeline carries that id.
    @discardableResult
    private mutating func timeline(_ id: JobID?, _ edit: (inout JobTimeline) -> Void) -> Bool {
        if var job = projection.job, job.id == id {
            edit(&job)
            projection.job = job
            return true
        }
        guard let index = projection.queued.firstIndex(where: { $0.id == id }) else { return false }
        edit(&projection.queued[index])
        return true
    }
}
