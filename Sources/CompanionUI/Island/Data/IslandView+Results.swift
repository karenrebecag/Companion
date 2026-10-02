import CompanionCore
import Foundation

// The "Ver →" cards under the reply: which earlier replies earn one (K6).
extension IslandView {
    /// Newest first, the earlier replies that brought a result, each keyed by
    /// its message so a card keeps its identity as newer ones push it down.
    /// The latest reply is left out by identity: the panel already shows it,
    /// and dropping the first row would drop the wrong one once prose
    /// replies make no rows (K6).
    static func resultRows(_ messages: [ChatMessage], limit: Int) -> [(id: UUID, result: IslandResult)] {
        let replies = messages.filter { $0.role == .assistant && !$0.isStatus }
        let latest = replies.last?.id
        // Lazy: a long conversation stops at the first `limit` results
        // instead of parsing every earlier reply on each render.
        return replies.reversed().lazy
            .filter { $0.id != latest }
            .compactMap { message in islandResult(for: message).map { (id: message.id, result: $0) } }
            .prefix(limit)
            .map { $0 }
    }

    /// A data card, from its own channel or a `companion:` fence, is a result;
    /// prose alone is an answer the panel already gave (K6).
    static func islandResult(for message: ChatMessage) -> IslandResult? {
        if let card = message.card { return IslandResult(reply: ChatCopy.cardShown(card)) }
        let window = String(message.text.prefix(MarkdownSplitter.islandWindow))
        guard !MarkdownSplitter.reportCut(window).cards.isEmpty else { return nil }
        return IslandResult(reply: message.text)
    }

    var results: [(id: UUID, result: IslandResult)] {
        Self.resultRows(chat.messages, limit: Self.maxResults)
    }
}
