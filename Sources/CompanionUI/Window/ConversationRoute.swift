import CompanionCore
import Foundation

package extension Notification.Name {
    /// "Seguir en el chat": the window opens on the conversation the island
    /// is in, not on Home. Posted by the island; the root view answers it.
    static let companionOpenConversation = Notification.Name("companion.openConversation")
}

/// Where "Seguir en el chat" lands, decided apart from both views so the
/// routing is checked without a window.
enum ConversationRoute {
    /// The island's conversation as the task the window opens. Its saved
    /// entry when there is one (title and work state); a conversation that
    /// was never saved still opens, named by its first question. Nil when
    /// there is nothing to read yet, and the window stays on Home.
    static func current(
        id: String, recents: [ConversationMeta], messages: [ChatMessage], now: Date, fallbackTitle: String
    ) -> ConversationMeta? {
        guard messages.contains(where: { !$0.isStatus }) else { return nil }
        if let saved = recents.first(where: { $0.id == id }) { return saved }
        let question = messages.first { $0.role == .user && !$0.isStatus }?.text
        return ConversationMeta(
            id: id, title: IslandResultCardModel.title(question: question, fallback: fallbackTitle), updatedAt: now)
    }
}
