import CompanionCore
import Foundation

/// Incredible's `passive_after_secs`: the wait before passive, 0 for never.
package enum PassivePreference {
    static let key = "companion.presence.passiveAfterSecs"

    /// A missing, negative or non-finite value is the default: the wait must never be
    /// negative or endless because of what an older build or a hand edit left.
    package static func seconds(in store: UserDefaults = .standard) -> TimeInterval {
        guard let stored = store.object(forKey: key) as? NSNumber else { return SessionMachine.defaultPassiveAfter }
        let seconds = stored.doubleValue
        return seconds.isFinite && seconds >= 0 ? seconds : SessionMachine.defaultPassiveAfter
    }

    package static func set(_ seconds: TimeInterval, in store: UserDefaults = .standard) {
        store.set(seconds, forKey: key)
    }
}

extension SessionModel {
    /// At launch the wait toward passive starts, not at the first interaction.
    package func armPresence(store: UserDefaults = .standard) {
        send(.passiveAfterChanged(PassivePreference.seconds(in: store)))
    }
}
