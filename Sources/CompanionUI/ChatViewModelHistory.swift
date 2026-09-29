import CompanionCore
import Foundation

/// Building the bounded history the provider actually receives, distinct from
/// the unbounded thread the reader sees. Split out of ChatViewModel when it
/// crossed the 400-line gate.
extension ChatViewModel {
    /// Test seam: the history the provider would receive, which is now a
    /// different thing from what the thread shows.
    func historyForTests() -> [Turn] { windowedTurns() }

    func windowedTurns() -> [Turn] {
        let turns: [Turn] = messages.compactMap { message in
            // A status line carries no memory of its own — unless it was given
            // one, which is how the delegate call survives in the history.
            if let recall = message.recall {
                return Turn(
                    role: recall.role,
                    content: message.origin == .choice
                        ? ChoiceOrigin.mark(recall.content, language: config.language) : recall.content,
                    attachments: message.attachments,
                    toolCalls: recall.toolCalls,
                    toolCallID: recall.toolCallID)
            }
            if message.isStatus { return nil }
            guard let role = message.role else { return nil }
            // What the assistant said goes through the same filter as a
            // specialist report: card payloads are interface, not context, and
            // the chat layer can emit them too now.
            let content = role == .assistant
                ? ConversationMemory.recall(message.text)
                : message.text
            return Turn(
                role: role,
                content: message.origin == .choice
                    ? ChoiceOrigin.mark(content, language: config.language) : content,
                attachments: message.attachments)
        }
        let window = max(0, config.chat.historyWindow)
        guard window > 0, turns.count > window else { return turns }
        // What falls out of the window leaves a note instead of a hole.
        let kept = Self.dropOrphanedToolTurns(Array(turns.suffix(window)))
        let dropped = Array(turns.prefix(turns.count - window))
        guard let note = ConversationMemory.compaction(
            of: dropped, language: config.language)
        else { return kept }
        return [note] + kept
    }

    /// The window can fall between a delegate call and the result that answers
    /// it. A tool turn whose call was cut away is not merely useless: the
    /// provider rejects the whole request over it, so the turn after a long
    /// conversation would fail outright.
    static func dropOrphanedToolTurns(_ turns: [Turn]) -> [Turn] {
        var known: Set<String> = []
        var kept: [Turn] = []
        for turn in turns {
            for call in turn.toolCalls { known.insert(call.id) }
            if turn.role == .tool {
                guard let id = turn.toolCallID, known.contains(id) else {
                    continue
                }
            }
            kept.append(turn)
        }
        return kept
    }
}
