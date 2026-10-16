import Foundation

/// What a finished reply is for the card. A receipt is a status line that
/// closes by itself; content stays until it is closed by hand, so nobody is
/// timed out of a page they are still reading.
package enum ReplyKind: Sendable, Equatable {
    case receipt
    case content
}

package enum ReadingClock {
    /// A receipt is one line of prose this long at most.
    static let receiptWords = 15
    /// Seconds a receipt stays once the voice stops, with no pointer over it.
    package static let hold: TimeInterval = 1.5
    /// Seconds a receipt waits before its hold when nothing was spoken.
    package static let silentWait: TimeInterval = 6
    /// The most a receipt is ever armed for, whatever the voice did.
    package static let cap: TimeInterval = 30

    /// Nil when there is nothing to read (a reply of only tool calls).
    package static func kind(of markdown: String) -> ReplyKind? {
        let text = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let blocks = AnswerBlocks.blocks(from: text)
        guard blocks.count == 1, let line = singleLine(blocks[0]) else { return .content }
        let words = line.split(whereSeparator: \.isWhitespace).count
        return words <= receiptWords ? .receipt : .content
    }

    /// The receipt's clock. Spoken: it starts when the voice stops. Silent: it
    /// waits the silent wait first. Either way the hold follows, under the cap.
    package static func receiptDelay(voiced: Bool) -> TimeInterval {
        min(cap, (voiced ? 0 : silentWait) + hold)
    }

    private static func singleLine(_ block: AnswerBlock) -> String? {
        switch block {
        case .paragraph(let text), .title(let text):
            text.contains("\n") ? nil : text
        default:
            nil
        }
    }
}
