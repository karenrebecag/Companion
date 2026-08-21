import Foundation

/// Kickoff decision for the thinking sound: a pure transition rule observed
/// from outside the reducer — zero new effects in TurnMachine.
public enum AmbienceCue: Sendable, Equatable {
    case start, stop, none

    /// The sound belongs to `.thinking` and nothing else: entering starts it,
    /// leaving for ANY state (speaking, error, idle) stops it.
    public static func forTransition(
        from previous: TurnState, to current: TurnState
    ) -> AmbienceCue {
        switch (previous == .thinking, current == .thinking) {
        case (false, true): .start
        case (true, false): .stop
        default: .none
        }
    }
}

/// Port so the observer can be tested without synthesizing audio.
public protocol ThinkingSounding: Sendable {
    func start()
    func stop()
}
