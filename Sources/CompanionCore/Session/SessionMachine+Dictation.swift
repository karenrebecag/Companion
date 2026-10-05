import Foundation

// The dictation result card's clock (16m-4). Kept out of SessionMachine.swift:
// that file is already past the size the gates warn about.
extension SessionMachine {
    /// The card is what Completed is showing: Completed with the pasted words.
    var showsDictationCard: Bool {
        projection.kind == .processing(.completed) && projection.dictatedText != nil
    }

    /// Every road into Completed arms its clock here, so no path can arm the
    /// short beat over a card (a warm muted snapshot re-enters Completed
    /// through `rest()`). A pointer already on the card freezes that clock.
    /// The model runs what was left once the pause hits its ceiling, so a
    /// hover-out that never arrives cannot leave the words up forever.
    func completedExpiry() -> [SessionEffect] {
        guard projection.dictatedText != nil else { return [.scheduleCompletedExpiry(Self.completedDelay)] }
        if dictationHeld { return [.pauseCompletedExpiry] }
        return [.scheduleCompletedExpiry(Self.dictationCardDelay)]
    }

    /// The pointer pauses the clock already running. Leaving continues it.
    /// Copying arms a fresh delay; under the pointer that delay starts paused.
    mutating func dictationCardEffects(_ event: SessionEvent) -> [SessionEffect] {
        guard showsDictationCard else { return [] }
        switch event {
        case .dictationCardHover(true):
            guard !dictationHeld else { return [] }
            dictationHeld = true
            return [.pauseCompletedExpiry]
        case .dictationCardHover(false):
            guard dictationHeld else { return [] }
            dictationHeld = false
            return [.resumeCompletedExpiry]
        case .dictationCardCopied:
            guard dictationHeld else { return [.scheduleCompletedExpiry(Self.dictationCardDelay)] }
            return [.scheduleCompletedExpiry(Self.dictationCardDelay), .pauseCompletedExpiry]
        default:
            return []
        }
    }

    /// Same rule the notice card uses. A lifetime on screen is not enough:
    /// `.chatError` counts down in the view and must not pause here.
    package static func pausesOnHover(_ notice: SessionCard) -> Bool { fades(notice) }

    /// Countdown notices only. The reducer remembers the pointer, because a
    /// second identical notice does not change `content` and the view will
    /// not send hover again: the new clock has to be born paused.
    mutating func noticeCardEffects(_ event: SessionEvent) -> [SessionEffect] {
        guard case .noticeCardHover(let over) = event else { return [] }
        guard let notice = projection.notice, Self.pausesOnHover(notice) else {
            if !over { noticeHeld = false }
            return []
        }
        if over {
            guard !noticeHeld else { return [] }
            noticeHeld = true
            return [.pauseNoticeExpiry]
        }
        guard noticeHeld else { return [] }
        noticeHeld = false
        return [.resumeNoticeExpiry]
    }

    /// A fading notice armed while the pointer is already over it starts
    /// paused. The flag is dropped once the notice is gone or does not pause.
    mutating func pausingHeldNotice(_ effects: [SessionEffect]) -> [SessionEffect] {
        guard let notice = projection.notice, Self.pausesOnHover(notice) else {
            noticeHeld = false
            return effects
        }
        guard noticeHeld else { return effects }
        let schedules = effects.contains {
            if case .scheduleNoticeExpiry = $0 { true } else { false }
        }
        guard schedules, !effects.contains(.pauseNoticeExpiry) else { return effects }
        var effects = effects
        effects.append(.pauseNoticeExpiry)
        return effects
    }
}
