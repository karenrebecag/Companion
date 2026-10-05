import Foundation

// The dictation result card's clock (16m-4). Kept out of SessionMachine.swift:
// that file is already past the size the gates warn about.
extension SessionMachine {
    /// The card is what Completed is showing: Completed with the pasted words.
    var showsDictationCard: Bool {
        projection.kind == .processing(.completed) && projection.dictatedText != nil
    }

    /// Completed with no pasted words: the settle, not the dictation card.
    var showsSettle: Bool {
        projection.kind == .processing(.completed) && projection.dictatedText == nil
    }

    /// Every road into Completed arms its clock here, so no path can arm the
    /// settle over a card (a warm muted snapshot re-enters Completed through
    /// `rest()`). A pointer already on the panel freezes the settle; a pointer
    /// already on the card freezes the card. The freeze holds until the pointer
    /// leaves or a new turn replaces the clock.
    func completedExpiry() -> [SessionEffect] {
        guard projection.dictatedText != nil else {
            // A notice, a sheet or an open answer is what is on screen.
            // The settle would close the island over it. The dictation card
            // below keeps its own clock even when a notice is up.
            if settleBlocked { return [] }
            var effects: [SessionEffect] = [
                .scheduleCompletedExpiry(Self.settleDelay, floor: Self.settleFloor)]
            if settleHeld { effects.append(.pauseCompletedExpiry) }
            return effects
        }
        if dictationHeld { return [.pauseCompletedExpiry] }
        return [.scheduleCompletedExpiry(Self.dictationCardDelay, floor: nil)]
    }

    /// Something the settle must not close the island over.
    var settleBlocked: Bool {
        projection.notice != nil || projection.approval != nil || answerOpen
    }

    /// Completed stays open while a blocker is up and nothing re-arms the
    /// settle when the last one leaves, so any event that does it arms the
    /// settle, state-based so no list of events can miss a road (a stop, a
    /// finished job). Only the transition inside Completed counts: a blocker
    /// that held nothing back must not restart a clock already running, and a
    /// turn that re-enters Completed through `rest()` is armed by `rest()`.
    func settleOnceUnblocked(wasCompleted: Bool, wasBlocked: Bool) -> [SessionEffect] {
        guard wasCompleted, wasBlocked, !settleBlocked, showsSettle else { return [] }
        return completedExpiry()
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
            guard dictationHeld else {
                return [.scheduleCompletedExpiry(Self.dictationCardDelay, floor: nil)]
            }
            return [.scheduleCompletedExpiry(Self.dictationCardDelay, floor: nil), .pauseCompletedExpiry]
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
