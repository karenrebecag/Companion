import CompanionCore
import Foundation

/// How a model step's sheets are asked. The turn engine runs the calls; this
/// decides, before the first one runs, which calls need the person at all: a
/// judge can take a confirm off, a kept "siempre" can cover a host, and the
/// rest share one sheet instead of one each.
extension ChatViewModel {
    enum StepLane: Equatable {
        /// Not settled here: the per-call gate asks, as it always has.
        case gate
        case granted
        case batchApproved
        case batchDenied
    }

    struct StepPlan {
        var lanes: [StepLane]
        /// The bound sheet of each call, asked of the runner once. The gate
        /// reuses it, so a browser or a deliverable parks its ticket once.
        var requests: [ApprovalRequest?]
    }

    private struct Candidate {
        let index: Int
        let request: ApprovalRequest
        let band: ActionBand
        let alwaysAllowed: Bool
    }

    /// Every call's sheet is bound here, in order, before anything runs. A call
    /// that never needed a sheet, or that the gate answers from memory, stays on
    /// `.gate`. QA mode keeps every call on `.gate`, as it always was.
    func planStep(_ calls: [ToolCallRef], said: String, tools: any ParentToolExecuting) async -> StepPlan {
        let epoch = historyEpoch
        var requests: [ApprovalRequest?] = []
        for call in calls {
            guard let asked = tools.approval(for: call, said: said) else {
                requests.append(nil)
                continue
            }
            let bound = await tools.bound(asked)
            // A clear while it waited: nothing of this step may reach the new thread.
            guard historyEpoch == epoch else { return denied(calls.count) }
            requests.append(bound)
        }
        var plan = StepPlan(lanes: [StepLane](repeating: .gate, count: calls.count), requests: requests)
        if let qaGate, await qaGate.isOn() { return plan }
        guard let approvals else { return plan }

        // A kept "siempre" is for a clean turn only: a turn that read her data
        // can send it out through the same host.
        let always = tools.turnIsTainted() ? AlwaysAllowList() : AlwaysAllowPreference.list
        var candidates: [Candidate] = []
        for (index, call) in calls.enumerated() {
            guard let request = requests[index] else { continue }
            if await tools.actsWithoutSheet(call) { continue }
            guard historyEpoch == epoch else { return denied(calls.count) }
            if await approvals.remembered(request) != nil { continue }
            let band = await tools.band(for: call)
            guard historyEpoch == epoch else { return denied(calls.count) }
            candidates.append(Candidate(
                index: index, request: request, band: band, alwaysAllowed: always.allows(request)))
        }
        guard !candidates.isEmpty else { return plan }

        let judged = await judgeCandidates(candidates, said: said)
        guard historyEpoch == epoch else { return denied(calls.count) }
        let targets = candidates.map { ApprovalBatch.target(of: $0.request) }
        let entries = candidates.enumerated().map { offset, candidate in
            SheetEntry(
                band: candidate.band, opinion: judged[offset], alwaysAllowed: candidate.alwaysAllowed,
                repeatedTarget: targets[offset].map { target in targets.filter { $0 == target }.count > 1 } ?? false)
        }
        let lanes = SheetLane.of(entries)
        let pending = candidates.enumerated().filter { lanes[$0.offset] == .ask }.map(\.element)
        // Only confirms share one sheet. A critical, an MCP call, or a lone
        // confirm keeps the gate's own sheet with its whole preview.
        let shared = pending.filter { ApprovalBatch.shareable($0.band, isMCP: $0.request.isMCP) }
        var answered = false
        if shared.count >= 2 {
            answered = await askTogether(shared.map(\.request))
            guard historyEpoch == epoch else { return denied(calls.count) }
        }
        // Tickets are granted only once the step is settled: a step that is
        // cut midway leaves none behind for calls that will not run.
        for (offset, candidate) in candidates.enumerated() {
            switch lanes[offset] {
            case .free:
                tools.granted(candidate.request)
                plan.lanes[candidate.index] = .granted
            case .ask where shared.count >= 2 && shared.contains(where: { $0.index == candidate.index }):
                plan.lanes[candidate.index] = answered ? .batchApproved : .batchDenied
                if answered { tools.granted(candidate.request) }
            case .ask:
                continue
            }
        }
        return plan
    }

    /// The outcome of a call the step already settled, without a gate.
    func settledOutcome(_ lane: StepLane, call: ToolCallRef) -> (ParentToolOutcome?, GateDecision) {
        switch lane {
        case .gate, .granted, .batchApproved:
            return (nil, GateDecision())
        case .batchDenied:
            let denied = ParentToolOutcome.failed(
                .deniedByUser(config.language), target: ParentTool.target(of: call), tool: call.name)
            return (denied, GateDecision())
        }
    }

    private func denied(_ count: Int) -> StepPlan {
        StepPlan(
            lanes: [StepLane](repeating: .batchDenied, count: count),
            requests: [ApprovalRequest?](repeating: nil, count: count))
    }

    /// The judge sees the whole step at once, and only when it could change a
    /// sheet: a confirm that no kept "siempre" already covers, with her words in hand.
    private func judgeCandidates(_ candidates: [Candidate], said: String) async -> [JudgeOpinion?] {
        let unjudged = [JudgeOpinion?](repeating: nil, count: candidates.count)
        guard let judge, candidates.contains(where: { $0.band == .confirm && !$0.alwaysAllowed }),
              let words = UserWords(heard: said)
        else { return unjudged }
        let asked = candidates.enumerated().map { offset, candidate in
            JudgeCandidate(id: "\(offset)", tool: candidate.request.toolName, argumentsJSON: candidate.request.inputJSON)
        }
        guard let request = ActionJudgeRequest(
            words: words, candidates: asked, maxCandidates: config.judge.maxCandidates)
        else { return unjudged }
        return JudgeGrounding.grounded(await judge.judge(request), candidates: asked, words: words)
    }

    /// One sheet for the step's remaining actions: one yes or one no for all of
    /// them. A clear while it waited answers no, as a single sheet would.
    private func askTogether(_ members: [ApprovalRequest]) async -> Bool {
        guard let approvals, let batch = ApprovalBatch.make(members: members, requestId: UUID().uuidString)
        else { return false }
        let epoch = historyEpoch
        session.send(.job(.approvalRequested(batch)))
        messages.append(ChatMessage(isStatus: true, text: ChatCopy.approvalPending))
        let response = await approvals.request(batch)
        session.send(.approvalSettled(requestId: batch.requestId))
        return response.approved && historyEpoch == epoch
    }
}
