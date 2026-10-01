import CompanionCore
import Foundation

/// The mouths read the pace synchronously on every request, with no `await`,
/// so it lives in a lock-guarded box rather than in an actor. Memory only:
/// it dies with the voice session and is never persisted.
package final class ConversationSpeedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var speed = ConversationSpeed.base

    package init() {}

    package var current: ConversationSpeed { lock.withLock { speed } }

    package var factor: Double { current.factor }

    package func set(factor: Double) {
        lock.withLock { speed = ConversationSpeed(factor: factor) }
    }

    package func reset() {
        lock.withLock { speed = .base }
    }
}
