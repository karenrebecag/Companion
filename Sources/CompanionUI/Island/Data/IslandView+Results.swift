import CompanionCore
import Foundation

// The "Ver →" cards under the reply: which earlier replies earn one.
// local reference; brief isla-ciclo-y-legibilidad K6.
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

    /// A fence the popup draws (.card or .diagram) is a result. A gallery
    /// fence stays code, and a choice draws nothing, so neither earns a row:
    /// "Ver" would open raw JSON or an empty popup. A card on its own channel
    /// is a result only when the popup will draw that payload. The window
    /// never paints the channel, so a row for anything else would open nothing.
    static func islandResult(for message: ChatMessage) -> IslandResult? {
        if popupDrawsFence(message.text),
           let parsed = IslandResult(reply: message.text) {
            return parsed
        }
        if let card = channelCard(on: message) {
            return IslandResult(reply: ChatCopy.cardShown(card))
        }
        return nil
    }

    /// The channel card the popup will draw. Nil when the message has none,
    /// or when the payload is a gallery.
    static func channelCard(on message: ChatMessage) -> Card? {
        message.card.flatMap { popupCanDraw($0) ? $0 : nil }
    }

    /// excluded on purpose: GalleryCard loads and opens file paths from the card; pending the same validation fence galleries wait for (AnswerBlocks.swift:155).
    // HACK: gallery payloads stay out of the popup. Upgrade trigger: CompanionBlocks
    // validates the gallery (https-only, path allowlist), the fence AnswerBlocks.fencePayload waits on.
    static func popupCanDraw(_ card: Card) -> Bool {
        switch card.payload {
        case .gallery: false
        case .locations, .stats, .table, .chart: true
        }
    }

    /// What the notch draws inline for a reply: its drawable channel card
    /// and the cards and diagrams in its text. A gallery fence stays code,
    /// so it is not here.
    static func inlineVisuals(_ message: ChatMessage) -> (card: Card?, blocks: [AnswerBlock]) {
        let blocks = windowBlocks(message.text).filter { block in
            switch block {
            case .card, .diagram: true
            default: false
            }
        }
        return (channelCard(on: message), blocks)
    }

    static func drawsInline(_ message: ChatMessage) -> Bool {
        let visuals = inlineVisuals(message)
        return visuals.card != nil || !visuals.blocks.isEmpty
    }

    /// "Ver" opens the popup only when that popup has something to show.
    /// A drawable channel card or fence does. A gallery with nothing else
    /// the popup draws does not: opening it would show raw JSON.
    static func opensInPopup(_ message: ChatMessage) -> Bool {
        if channelCard(on: message) != nil { return true }
        let blocks = windowBlocks(message.text)
        if popupDraws(blocks) { return true }
        if galleryHeldBack(message, blocks: blocks) { return false }
        return AnswerBlocks.isRich(blocks)
    }

    private static func popupDrawsFence(_ text: String) -> Bool {
        popupDraws(windowBlocks(text))
    }

    private static func windowBlocks(_ text: String) -> [AnswerBlock] {
        AnswerBlocks.blocks(from: String(text.prefix(MarkdownSplitter.islandWindow)))
    }

    /// `.card` and `.diagram` are what the popup paints. A gallery fence is
    /// `.code` until the validation fence, so it does not count.
    private static func popupDraws(_ blocks: [AnswerBlock]) -> Bool {
        blocks.contains { block in
            switch block {
            case .card, .diagram: true
            default: false
            }
        }
    }

    private static func galleryHeldBack(_ message: ChatMessage, blocks: [AnswerBlock]) -> Bool {
        if case .gallery = message.card?.payload { return true }
        return blocks.contains { block in
            if case .code(let language, _) = block {
                return language == CompanionBlocks.galleryLanguage
            }
            return false
        }
    }

    var results: [(id: UUID, result: IslandResult)] {
        Self.resultRows(chat.messages, limit: Self.maxResults)
    }
}
