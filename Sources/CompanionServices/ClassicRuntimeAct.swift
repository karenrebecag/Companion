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

    /// Runs the round and folds what it learnt into the turn. The one
    /// caller-facing way to act when nothing runs beside it.
    func act(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage
    ) async -> [Turn] {
        let round = await actRound(
            calls, said: text, heard: heard, using: parentTools, language: language,
            unverified: unverifiedTyped)
        absorb(round)
        return round.turns
    }

    func absorb(_ round: ActedRound) {
        unverifiedTyped = round.unverified
        effectLines += round.effectLines
        if round.sawCard { cardThisTurn = true }
    }

    /// Runs the round's parent calls and returns the turns the next round
    /// needs: one assistant turn with every call, one answer per call — or
    /// the model repeats the action it does not know it took. Touches the
    /// ports (tools, thread, events) but never the runtime's turn state.
    func actRound(
        _ calls: [ToolCallRef], said text: String, heard: String,
        using parentTools: any ParentToolExecuting, language: AppLanguage,
        unverified: [TypedAttempt]
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
                    role: .tool, content: "cancelled: the user interrupted", toolCallID: call.id))
                continue
            }
            // A URL the user did not say waits for the sheet (10c 3D).
            let outcome: ParentToolOutcome
            if let denied = await parentGuard.check(
                call, said: heard, language: language, tools: parentTools) {
                outcome = denied
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
        return ActedRound(
            turns: turns, effectLines: effects, sawCard: !cards.isEmpty, unverified: proof.unverified)
    }
}
