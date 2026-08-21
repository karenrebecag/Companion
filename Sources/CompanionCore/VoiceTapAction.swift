/// Determines what action to perform when the user taps the mic button.
/// This is a pure function, making it easy to test and reason about.
public enum VoiceTapAction: Sendable, Equatable {
    case start, interrupt, hangUp

    /// Determines the tap action based on the current voice state.
    /// - Parameter state: The current TurnState.
    /// - Returns: The action to perform.
    public static func forState(_ state: TurnState) -> VoiceTapAction {
        switch state {
        case .idle, .error:
            // In idle or error, tap should start or retry.
            .start
        case .connecting, .listening, .thinking:
            // While actively listening or processing, tap should hang up.
            .hangUp
        case .speaking:
            // While agent is speaking, tap should interrupt (barge-in).
            .interrupt
        }
    }

    /// Returns the label for the mic button based on the current state.
    /// - Parameter state: The current TurnState.
    /// - Returns: A localized label for the button.
    public static func label(forState state: TurnState) -> String {
        switch forState(state) {
        case .start:
            "Hablar"
        case .hangUp:
            "Colgar"
        case .interrupt:
            "Interrumpir"
        }
    }
}
