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
    package func attachDecision(_ gate: DecisionGate) {
        classic.decide = { [weak self] utterance, canDelegate in
            guard let self else { return .passThrough(.disabled) }
            return await self.routeThroughDecisionGate(
                utterance, canDelegate: canDelegate, gate: gate)
        }
    }

    /// The "Decidir en local" toggle (DM1c-3) is read fresh here, not at
    /// attach time, so it can flip live without a new session. Zero
    /// `DecisionProvider` calls while it is off (measured in
    /// `dm1cDecisionOffNeverAsksTheProvider`).
    private func routeThroughDecisionGate(
        _ utterance: String, canDelegate: Bool, gate: DecisionGate
    ) async -> DecisionOutcome {
        guard configProvider.current.decision.enabled else { return .passThrough(.disabled) }
        // 15c-4/15c-7: the fast brain (Cerebras) already picked the tool by
        // commit; N1's own cascade added up to 0.9s and never won a hold
        // against it (wave-15c §1) — `gate` is not even called.
        guard lastStack?.hasFastBrain != true else {
            Log.chat("decision: pass reason=\(DecisionPassReason.fastBrain.rawValue)")
            return .passThrough(.fastBrain)
        }
        // Classic never marked `.committed` before DM1c-2: `commitTimeline`
        // is the model-in-the-loop path's own mark (`commitTurnFromNative`),
        // which the classic hold never calls. This is the first mark either
        // way — `mark` itself is idempotent, so a repeat costs nothing.
        commitTimeline()
        // DM1c-4: a still-open "¿vacío la papelera?" answers from THIS
        // turn's own words before N1 ever sees them — a "sí" here must not
        // be reclassified as a fresh order.
        if let confirmed = await gate.answerConfirmation(utterance) {
            markTool(.decision)
            if case .passThrough = confirmed {} else { markTool(.toolDone) }
            return confirmed
        }
        let step = await gate.plan(utterance, canDelegate: canDelegate)
        markTool(.decision)
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
}
