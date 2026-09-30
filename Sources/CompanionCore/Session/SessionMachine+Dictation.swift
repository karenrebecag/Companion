import Foundation

// The dictation result card's clock (16m-4). Kept out of SessionMachine.swift:
// that file is already past the size the gates warn about.
extension SessionMachine {
    /// The most a card stays up under a pointer. Hover-out is an event that
    /// can be lost (a window that closes under the pointer), and the words
    /// may be private.
    // HACK: fixed 60 s ceiling. Make it a preference if someone reads long
    // dictations with the pointer parked on the card.
    package static let dictationHoverCap: TimeInterval = 60

    /// The card is what Completed is showing: Completed with the pasted words.
    var showsDictationCard: Bool {
        projection.kind == .processing(.completed) && projection.dictatedText != nil
    }

    /// Every road into Completed arms its clock here, so no path can arm the
    /// 1.5 s beat over a card that needs its 12 s (a warm muted snapshot
    /// re-enters Completed through `rest()`). A held card arms the long cap.
    func completedExpiry() -> [SessionEffect] {
        guard projection.dictatedText != nil else { return [.scheduleCompletedExpiry(Self.completedDelay)] }
        return [.scheduleCompletedExpiry(dictationHeld ? Self.dictationHoverCap : Self.dictationCardDelay)]
    }

    /// The pointer over the card holds it to the cap; leaving, or copying
    /// while the pointer is away, gives the reader a fresh 12 s.
    mutating func dictationCardEffects(_ event: SessionEvent) -> [SessionEffect] {
        guard showsDictationCard else { return [] }
        switch event {
        case .dictationCardHover(true):
            dictationHeld = true
            return completedExpiry()
        case .dictationCardHover:
            dictationHeld = false
            return completedExpiry()
        case .dictationCardCopied:
            return completedExpiry()
        default:
            return []
        }
    }
}
