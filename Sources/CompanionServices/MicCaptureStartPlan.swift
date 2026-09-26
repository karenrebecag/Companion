import Foundation

/// What MicCapture.start() should do given its current state. Pure so the
/// idempotency rule is tested without a real AVAudioEngine (installing a
/// second tap on an already-running engine raises an uncatchable ObjC
/// exception — live crash 2026-09-23).
public enum MicStartAction: Sendable, Equatable {
    case start
    case alreadyRunning
}

public enum MicStartPlan: Sendable {
    public static func decide(running: Bool, tapInstalled: Bool) -> MicStartAction {
        running && tapInstalled ? .alreadyRunning : .start
    }
}
