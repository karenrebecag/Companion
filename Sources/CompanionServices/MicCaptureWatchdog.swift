import Foundation

/// What the mic should do when the Voice Processing watchdog fires.
public enum WatchdogAction: Sendable, Equatable {
    case none
    case vetoAndRetry
}

/// Pure decision behind the watchdog, so the rule is tested without starting a
/// real AVAudioEngine. MicCapture owns the facts; this owns the rule.
public enum MicWatchdog: Sendable {
    /// VPIO can start clean and still never fire the tap. One retry without
    /// Voice Processing is the recovery; a second one never helped.
    public static func decide(
        running: Bool,
        voiceProcessing: Bool,
        receivedBuffer: Bool,
        alreadyRetried: Bool
    ) -> WatchdogAction {
        guard running, voiceProcessing, !receivedBuffer, !alreadyRetried else {
            return .none
        }
        return .vetoAndRetry
    }
}
