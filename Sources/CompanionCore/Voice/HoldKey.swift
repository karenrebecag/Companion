import Foundation

/// What the hold key did. The pointer and FN fire `pressed` on the way
/// down (latency, 15d-1); the dictation key waits for `confirm` so typing a
/// symbol with its modifier never opens the mic.
package enum HoldKeyEvent: Sendable, Equatable {
    case pressed, released, tapped
    /// 15d-1: the key came up as a tap, or chorded, after the mic already
    /// opened on the way down — drop the audio, say nothing.
    case cancelled
    /// A press armed on the way down outlived the tap threshold: from here
    /// on it is a hold, so work that leaves the machine may start.
    case confirmed
}

/// Tap versus hold, by duration. Pure; the event tap feeds it timestamps.
package struct HoldKeyClassifier: Sendable, Equatable {
    package var tapThreshold: TimeInterval
    private var downAt: TimeInterval?
    private var armed = false
    private var chorded = false
    /// Armed by `press`: a short up or a chord is `.cancelled`, not a tap.
    private var armedOnDown = false
    /// `.confirmed` is said once per press.
    private var confirmedOnDown = false

    package init(tapThreshold: TimeInterval = 0.25) {
        self.tapThreshold = tapThreshold
    }

    /// The pointer or key is held right now.
    package var isDown: Bool { downAt != nil }

    /// Pointer path: press fires on the way down.
    package mutating func down(at now: TimeInterval) -> HoldKeyEvent? {
        guard downAt == nil else { return nil }
        downAt = now
        armed = true
        chorded = false
        armedOnDown = false
        return .pressed
    }

    /// Keyboard path, 15d-1: the mic opens on the way down.
    package mutating func press(at now: TimeInterval) -> HoldKeyEvent? {
        guard downAt == nil else { return nil }
        downAt = now
        armed = true
        chorded = false
        armedOnDown = true
        confirmedOnDown = false
        return .pressed
    }

    /// Keyboard path: remember the down, do not arm the mic yet.
    package mutating func begin(at now: TimeInterval) -> HoldKeyEvent? {
        guard downAt == nil else { return nil }
        downAt = now
        armed = false
        chorded = false
        armedOnDown = false
        return nil
    }

    /// Keyboard path: past the tap threshold with the key still alone.
    /// Armed on the way down, the mic is already open and this only says
    /// the press is a hold now; otherwise this is what arms it.
    package mutating func confirm(at now: TimeInterval) -> HoldKeyEvent? {
        guard let start = downAt, !chorded, now - start >= tapThreshold else { return nil }
        if armedOnDown {
            guard !confirmedOnDown else { return nil }
            confirmedOnDown = true
            return .confirmed
        }
        guard !armed else { return nil }
        armed = true
        return .pressed
    }

    /// FN+another key is a shortcut, not a hold. Drops an unarmed begin.
    /// If the mic was already armed, returns `.tapped` so the session
    /// stops without committing.
    package mutating func chord() -> HoldKeyEvent? {
        guard downAt != nil else { return nil }
        if !armed {
            downAt = nil
            chorded = false
            return nil
        }
        downAt = nil
        armed = false
        chorded = false
        return armedOnDown ? .cancelled : .tapped
    }

    /// Nil without a matching down. A chord that never armed is silence.
    package mutating func up(at now: TimeInterval) -> HoldKeyEvent? {
        guard let start = downAt else { return nil }
        let wasChorded = chorded
        let wasArmed = armed
        downAt = nil
        armed = false
        chorded = false
        if wasChorded && !wasArmed { return nil }
        guard now - start < tapThreshold else { return .released }
        return armedOnDown ? .cancelled : .tapped
    }
}
