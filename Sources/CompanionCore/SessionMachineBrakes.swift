import Foundation

/// 16q-1: the brakes of the session reducer. Incredible has no single brake:
/// the voice's stops the turn and leaves the jobs, each job has its own stop
/// (`stopJob`, in SessionMachineJobs.swift), and the menu bar's is total.
/// They share what a brake does to the voice (`silenceVoice`) and to the
/// turn (`endTurn`). Split from SessionMachine.swift when it crossed the
/// 400-line warning; like SessionMachineJobs it is the reducer, so the gate
/// that keeps a single writer of the projection lists it.
extension SessionMachine {
    /// Which pending requests a brake refuses. The voice's brake leaves a
    /// job's own requests to the job: it keeps running, and its sheet stays.
    enum Denial { case everything, theTurnsOwn }

    /// A request nobody owns (an MCP tool, the parent's gate, the bridge's
    /// grant) can wait on the sheet while the chrome rests: a brake must
    /// still reach it.
    var hasUnownedRequest: Bool {
        projection.approvalQueue.contains { approvalOwners[$0.requestId] == nil }
    }

    /// Whether the voice's brake has anything to do. At rest a job's end may
    /// still be talking, and a sheet may still wait on the turn.
    var voiceBrakeApplies: Bool {
        projection.kind != .idle || projection.announcing || hasUnownedRequest
    }

    var totalBrakeApplies: Bool {
        projection.kind != .idle || projection.announcing || !projection.approvalQueue.isEmpty
    }

    /// What every brake does to the voice: cut what it thinks or says, drop
    /// the hold in progress. The model is told the user interrupted only when
    /// something was interrupted (`always` for the total brake, which has
    /// always said so).
    mutating func silenceVoice(always: Bool) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        if voice.state == .thinking || voice.state == .speaking || projection.announcing {
            effects.append(.cancelVoiceOutput)
        }
        // Inside the release tail the voice still listens: the commit
        // has not left yet, and Esc must be what stops it.
        if projection.holding || inReleaseTail {
            effects.append(.stopListening(commit: false))
        }
        provisional = false
        if always || typedBusy || !effects.isEmpty { effects.append(.islandEvent(.interrupted)) }
        return effects
    }

    /// The total brake (the menu bar's): every job, running and waiting,
    /// and everything the sheet waits on.
    mutating func stop() -> [SessionEffect] {
        var effects: [SessionEffect] = []
        if projection.job != nil || !projection.queued.isEmpty {
            effects.append(.cancelJob)
            noteStopped()
        }
        effects += endTurn(denying: .everything)
        return effects
    }

    /// What every brake does to the turn itself: refuse what the turn waited
    /// on, close a typed turn, and land the chrome on the row of the job
    /// that still runs, if one does.
    mutating func endTurn(denying denial: Denial) -> [SessionEffect] {
        let refused = projection.approvalQueue.filter {
            denial == .everything || approvalOwners[$0.requestId] == nil
        }
        let effects = refused.map {
            SessionEffect.resolveApproval(requestId: $0.requestId, approved: false, remember: false)
        }
        projection.approvalQueue.removeAll { queued in
            refused.contains { $0.requestId == queued.requestId }
        }
        for request in refused { approvalOwners[request.requestId] = nil }
        // A typed turn in flight is abandoned too; a flag left true kept the
        // chrome painting the voice's last phase for ever (code review
        // 2026-09-06).
        typedBusy = false
        projection.holding = false
        projection.targets = []
        projection.interruption = .userStopped
        turnOver()
        projection.kind = projection.job != nil ? .processing(.subAgentRunning) : .idle
        return effects
    }

    mutating func remove(_ requestId: String) -> ApprovalRequest? {
        guard let index = projection.approvalQueue.firstIndex(where: { $0.requestId == requestId })
        else { return nil }
        approvalOwners[requestId] = nil
        return projection.approvalQueue.remove(at: index)
    }
}
