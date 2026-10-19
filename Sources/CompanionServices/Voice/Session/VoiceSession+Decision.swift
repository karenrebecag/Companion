import CompanionCore
import Foundation

/// DM1c-2 (wave-dm1-router.md §8): wires `DecisionGate` into the classic
/// hold's `ClassicRuntime.decide` seam. Split out of VoiceSession — the
/// actor is at the 800-line gate (Wave DM0) and this delivery must not add
/// to it — the same pattern `VoiceSessionTimeline` already uses: not
/// `private`, but still actor-isolated by the actor itself, not by access
/// level.
extension VoiceSession {
    /// Composition-root call, once: `classic.decide` stays nil until this
    /// runs, and a nil `decide` is `ClassicRuntime.submit`'s "today,
    /// unchanged" path (DM1c-2 §"Files").
    /// `judge` is the same provider `gate` asks; passing it lets a hosted
    /// judge run the router past the local-only guards and feed the
    /// delegation head. Nil keeps the router local-only, as before.
    package func attachDecision(_ gate: DecisionGate, judge: DecisionJudge? = nil) {
        attachedDecision = (gate, judge)
        classic.decide = { [weak self] utterance, canDelegate in
            guard let self else { return .passThrough(.disabled) }
            var turn: DecisionJudge?
            if let judge { turn = await self.turnJudge(utterance, judge) }
            return await self.routeThroughDecisionGate(
                utterance, canDelegate: canDelegate, gate: gate, judge: turn)
        }
        if let judge {
            classic.delegationVerdict = { [weak self] utterance in
                guard let self else { return nil }
                let turn = await self.turnJudge(utterance, judge)
                return await gate.delegationVerdict(utterance, judge: turn)?.value
            }
        }
    }

    /// Both seams of one hold ask for the same utterance within moments;
    /// the second gets the first's pin. The window keeps a repeat of the
    /// same words later on from inheriting a key that was since removed.
    func turnJudge(_ utterance: String, _ judge: DecisionJudge) -> DecisionJudge {
        if let pinned = pinnedJudge, pinned.utterance == utterance,
           Date().timeIntervalSince(pinned.at) < 10 {
            return pinned.judge
        }
        let held = judge.pinned()
        pinnedJudge = (utterance, Date(), held)
        return held
    }

    /// The "Decidir en local" toggle (DM1c-3) is read fresh here, not at
    /// attach time, so it can flip live without a new session. Zero
    /// `DecisionProvider` calls while it is off (measured in
    /// `dm1cDecisionOffNeverAsksTheProvider`).
    ///
    /// A hosted judge passes both guards: the toggle is about running a local
    /// model, and the fast-brain skip was measured against the local 4B
    /// cascade, not one round trip to Jev.
    private func routeThroughDecisionGate(
        _ utterance: String, canDelegate: Bool, gate: DecisionGate, judge: DecisionJudge?
    ) async -> DecisionOutcome {
        let hosted = judge?.usesHostedJudge ?? false
        if let skipped = routerSkip(hosted: hosted) {
            cancelSpeculation()
            if skipped == .fastBrain {
                Log.chat("decision: pass reason=\(DecisionPassReason.fastBrain.rawValue)")
            }
            return .passThrough(skipped)
        }
        // Classic never marked `.committed` before DM1c-2: `commitTimeline`
        // is the model-in-the-loop path's own mark (`commitTurnFromNative`),
        // which the classic hold never calls. This is the first mark either
        // way — `mark` itself is idempotent, so a repeat costs nothing.
        commitTimeline()
        // While a job runs, how the new words relate to it is judged beside
        // the plan and settled before anything runs. A yes/no to the open
        // question answers that question and is never sent out about the job.
        let answering = await gate.answersPendingConfirmation(utterance)
        let relation = answering ? nil : runningObjective.flatMap { objective in
            judge.map { turn in
                (objective, ContinuousClock.now, Task { await turn.relationship(utterance, to: objective) })
            }
        }
        defer { relation?.2.cancel() }
        let route = await gate.route(
            utterance, canDelegate: canDelegate,
            budget: hosted ? configProvider.current.decision.hostedBudget : nil,
            provider: judge,
            prepared: takeSpeculation(matching: utterance, canDelegate: canDelegate, world: gate.world()))
        let step: DecisionStep
        switch route {
        case .answered(let confirmed):
            cancelSpeculation()
            markTool(.decision)
            if case .passThrough = confirmed {} else { markTool(.toolDone) }
            return confirmed
        case .planned(let planned):
            step = planned
        }
        markTool(.decision)
        if let (objective, started, task) = relation, let id = objective.jobID {
            // The budget runs from when the head went out, not from now.
            let budget = configProvider.current.decision.hostedBudget
            let verdict = await DecisionJudge.verdict(
                task, within: max(.zero, budget - started.duration(to: .now)))
            // The job may have ended while the head was out: nothing to stop.
            if runningObjective?.jobID == id {
                switch RelationshipHead.move(verdict, about: objective) {
                case .stop:
                    markTool(.toolDone)
                    return await stopJob(id, goal: objective.goal)
                case .replace:
                    await jobs?.cancel(job: id)
                case .toBrain:
                    // Not sure enough to act: no question, the brain sees the
                    // running job and can stop it itself (`stop_job`).
                    return .passThrough(.unresolved)
                case .none:
                    // Jobs take no steering: an addition is planned as a new
                    // job, which the queue announces.
                    break
                }
            }
        }
        // Only `.execute` runs through the SAME door the parent-tool loop
        // uses (`ParentToolRunner`, inside `gate.run`): the session's own
        // "the parent's hands are moving" signal belongs there, not on a
        // closed-set action or a delegation the router itself decided.
        var acting = false
        if case .execute(let call, _) = step {
            eventBox.yield(.parentActing(targets: [ParentTool.target(of: call)]))
            acting = true
        }
        let outcome = await gate.run(
            step, utterance: utterance, language: configProvider.current.language)
        if acting { eventBox.yield(.parentActed) }
        if case .passThrough = outcome {} else { markTool(.toolDone) }
        return outcome
    }

    /// Only the job the head judged, and only while it still runs: the
    /// queue's other jobs are not hers to lose to one "olvídalo".
    private func stopJob(_ id: JobID, goal: String) async -> DecisionOutcome {
        guard runningObjective?.jobID == id else { return .passThrough(.superseded) }
        await jobs?.cancel(job: id)
        return .said(DecisionCopy.stoppedJob(goal, configProvider.current.language))
    }

    /// The brain's `stop_job` or a spoken "para": the job running now, and
    /// only it, as Incredible's per-agent stop. An id the brain got wrong
    /// still stops that job: a misfilled argument must not be a way not to
    /// stop. With no job known running, the brake falls back to the runner's.
    func stopRunningJob(named: String?) async {
        guard let running = runningObjective?.jobID else {
            await jobs?.cancel()
            return
        }
        if let named, named != running.raw {
            Log.chat("decision: stop_job named an id that is not running; stopping the running one")
        }
        await jobs?.cancel(job: running)
    }

    /// Why the router does not run this hold, or nil when it does.
    func routerSkip(hosted: Bool) -> DecisionPassReason? {
        DecisionGate.skip(
            hosted: hosted, enabled: configProvider.current.decision.enabled,
            fastBrain: lastStack?.hasFastBrain == true)
    }

    /// Follows the job the voice started, for the relationship head.
    func trackObjective(_ event: SessionEvent) {
        switch event {
        case .job(.started(let goal), let id?):
            guard !finishedJobs.contains(id) else { return }
            runningObjective = PendingObjective(
                goal: goal, jobID: id,
                goalFromUser: PendingObjective.isUsersOwn(goal, heard: heardThisHold?.text))
        case .job(.stepStarted(let tool, _, _), let id?) where runningObjective?.jobID == id:
            runningObjective?.currentTool = tool
        case .job(.stepFinished, let id?) where runningObjective?.jobID == id:
            runningObjective?.stepsDone += 1
        case .jobFinished(_, let id?):
            finishedJobs.insert(id)
            if runningObjective?.jobID == id { runningObjective = nil }
        default:
            break
        }
    }
}
