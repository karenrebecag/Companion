import Foundation

/// What MicCapture.start() should do given its current state. Pure so the
/// idempotency rule is tested without a real AVAudioEngine (installing a
/// second tap on an already-running engine raises an uncatchable ObjC
/// exception — live crash 2026-09-23).
package enum MicStartAction: Sendable, Equatable {
    case start
    case alreadyRunning
}

package enum MicStartPlan: Sendable {
    package static func decide(running: Bool, tapInstalled: Bool) -> MicStartAction {
        running && tapInstalled ? .alreadyRunning : .start
    }
}
