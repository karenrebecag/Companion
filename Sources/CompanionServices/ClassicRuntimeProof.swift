import CompanionCore
import Foundation

/// Wave 16h-1 (H1): a `type_text` says it worked only once a `read_focused`
/// of the same turn shows the field CHANGED: same app, and the text there
/// more times than before it was typed. The prompt already tells the model to
/// read after typing; this is the app noticing that it did.
extension ClassicRuntime {
    struct ToolRun {
        let call: ToolCallRef
        var outcome: ParentToolOutcome
        /// Where its answer sits in the round's turns.
        let turn: Int
    }

    /// A typing no read has confirmed yet.
    struct TypedAttempt: Equatable {
        let text: String
        let pid: Int32?
        let before: Int?
    }

    /// The round's runs with the proven typings marked, and the lines owed to
    /// the thread for typings from EARLIER rounds that a read here confirmed.
    /// Typings still unproven wait for a later read.
    func proving(
        _ runs: [ToolRun], turns: inout [Turn], language: AppLanguage
    ) -> (runs: [ToolRun], late: [String]) {
        var runs = runs
        let reads = runs.filter { $0.call.name == ParentTool.readFocused.rawValue && $0.outcome.ok }
        let confirmed = unverifiedTyped.filter { attempt in reads.contains { Self.confirms($0.outcome, attempt) } }
        unverifiedTyped.removeAll { confirmed.contains($0) }
        let proven = ParentToolOutcome(ok: true, output: "", tool: ParentTool.typeText.rawValue, verified: true)
        let late = confirmed.isEmpty ? [] : [ParentToolCopy.status(ParentTool.typeText.rawValue, proven, language)]
        for index in runs.indices where Self.isTyping(runs[index]) {
            guard let attempt = Self.attempt(runs[index]) else { continue }
            let later = runs[(index + 1)...].contains { run in
                run.call.name == ParentTool.readFocused.rawValue && run.outcome.ok
                    && Self.confirms(run.outcome, attempt)
            }
            guard later else {
                unverifiedTyped.append(attempt)
                continue
            }
            runs[index].outcome.verified = true
            runs[index].outcome.output = runs[index].outcome.output.replacingOccurrences(
                of: TypedProof.unverifiedNote, with: TypedProof.verifiedNote)
            turns[runs[index].turn].content = runs[index].outcome.output
        }
        return (runs, late)
    }

    static func isTyping(_ run: ToolRun) -> Bool {
        run.call.name == ParentTool.typeText.rawValue && run.outcome.ok
    }

    private static func confirms(_ read: ParentToolOutcome, _ attempt: TypedAttempt) -> Bool {
        guard let pid = attempt.pid, read.fieldPID == pid else { return false }
        return TypedProof.verifies(typed: attempt.text, read: read.output, before: attempt.before)
    }

    private static func attempt(_ run: ToolRun) -> TypedAttempt? {
        guard let text = ToolArguments.parse(run.call.arguments)?["text"] as? String else { return nil }
        return TypedAttempt(text: text, pid: run.outcome.fieldPID, before: run.outcome.typedBefore)
    }
}
