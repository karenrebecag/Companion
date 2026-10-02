import CompanionCore
import Foundation

/// A round of the parent's own tools. Split from ClassicRuntime.swift for
/// 16h-2 (review S3): the round now runs beside the acknowledgement, so it
/// reports what it learnt instead of writing the runtime's turn state from a
/// child task.
extension ClassicRuntime {
    /// What a round learnt about the turn, for the caller to absorb.
    struct ActedRound: Sendable {
        var turns: [Turn]
        /// The status line of every call that changed something.
        var effectLines: [String]
        /// A tool painted a card this round.
        var sawCard: Bool
        /// Typings still waiting for a read that proves them.
        var unverified: [TypedAttempt]
    }

    /// Runs the round and folds what it learnt into the turn that owns
    /// `mouth`, so two overlapping turns never share that state.
    func act(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage,
        _ mouth: inout TurnMouth
    ) async -> [Turn] {
        let round = await actRound(
            calls, said: text, heard: heard, using: parentTools, language: language,
            unverified: mouth.unverifiedTyped)
        Self.absorb(round, into: &mouth)
        return round.turns
    }

    static func absorb(_ round: ActedRound, into mouth: inout TurnMouth) {
        mouth.unverifiedTyped = round.unverified
        mouth.effectLines += round.effectLines
        if round.sawCard { mouth.cardThisTurn = true }
    }

    /// Runs the round's parent calls and returns the turns the next round
    /// needs: one assistant turn with every call, one answer per call — or
    /// the model repeats the action it does not know it took. Touches the
    /// ports (tools, thread, events) but never the runtime's turn state.
    /// `onParked` hears each sheet right before it shows; nil leaves the
    /// guard exactly as `check` runs it.
    func actRound(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage,
        unverified: [TypedAttempt], onParked: (@Sendable (ApprovalRequest) -> Bool)? = nil
    ) async -> ActedRound {
        var turns = [Turn(role: .assistant, content: text, toolCalls: calls)]
        var cards: [Card] = []
        var runs: [ToolRun] = []
        events?.yield(.parentActing(targets: calls.map { ParentTool.target(of: $0) }))
        defer { events?.yield(.parentActed) }
        for call in calls {
            // A press cut the turn: type_text may have run, but Return after
            // it must not (review 2026-09-25). Every call still gets an
            // answer, or the round is malformed.
            if Task.isCancelled {
                turns.append(Turn(
                    role: .tool, content: ContractError.interrupted.wire, toolCallID: call.id))
                continue
            }
            // A URL the user did not say waits for the sheet (10c 3D).
            let outcome: ParentToolOutcome
            if let denied = await parentGuard.verdict(
                call, said: heard, language: language, tools: parentTools, parked: onParked).denial {
                outcome = denied
            } else if Task.isCancelled {
                // The guard's other awaits (binding, memory) are cut points
                // too, and this is the last one before the effect.
                parentTools.withdraw(call)
                outcome = .failed(.interrupted, target: ParentTool.target(of: call), tool: call.name)
            } else {
                outcome = await parentTools.execute(
                    name: call.name, argumentsJSON: call.arguments)
            }
            if let card = outcome.card { cards.append(card) }
            turns.append(Turn(role: .tool, content: outcome.output, toolCallID: call.id))
            let run = ToolRun(call: call, outcome: outcome, turn: turns.count - 1)
            runs.append(run)
            // At once, so a slow next call never holds this line back. Only a
            // typing waits: whether it was proven depends on a later read.
            if !Self.isTyping(run) {
                await thread.appendStatus(ParentToolCopy.status(call.name, outcome, language))
            }
        }
        let proof = proving(runs, turns: &turns, unverified: unverified, language: language)
        let typings = proof.runs.filter(Self.isTyping)
            .map { ParentToolCopy.status($0.call.name, $0.outcome, language) }
        var emitted = Set<String>()
        for line in proof.late + typings where emitted.insert(line).inserted {
            await thread.appendStatus(line)
        }
        let effects = proof.runs
            .filter { ParentTool(rawValue: $0.call.name)?.changesSomething == true }
            .map { ParentToolCopy.status($0.call.name, $0.outcome, language) }
        for card in cards { events?.yield(.job(.card(card))) }
        // The island's receipt is the effect lines that HAVE proof; an
        // unread typing is an attempt and gets no check (16h-3).
        // `late` are typings an earlier round left waiting and a read here
        // confirmed: proven, and read back.
        let proven = proof.runs.compactMap {
            ReceiptProof.entry(tool: $0.call.name, outcome: $0.outcome, language: language)
        } + proof.late.map { ReceiptLine(text: $0, verified: true) }
        if let receipt = ActionReceipt(entries: proven) { events?.yield(.receipt(receipt)) }
        return ActedRound(
            turns: turns, effectLines: effects, sawCard: !cards.isEmpty, unverified: proof.unverified)
    }
}
