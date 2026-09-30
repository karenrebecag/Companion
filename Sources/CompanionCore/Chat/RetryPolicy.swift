import Foundation

/// When to wait and try again instead of moving down the ladder.
///
/// A rate limit used to drop straight to the next provider, and with no next
/// provider the user was told "no provider available" — a temporary condition
/// reported as a configuration fault, which sends someone to fix what is not
/// broken. It is the same family as `noProvider` being reported as "no
/// internet", and the same fix: say what actually happened.
package enum RetryPolicy: Sendable {
    /// Three tries total. Enough to ride out a burst, short enough that a
    /// provider having a bad day does not become a silent hang.
    package static let maxAttempts = 3
    /// Even when the provider asks for longer. An hour-long wait is a polite
    /// way of freezing.
    package static let maxDelay: TimeInterval = 20

    package static func shouldRetry(_ error: ChatError, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }
        switch error {
        // The only one where waiting IS the remedy: the provider said "later"
        // and means it.
        case .rateLimited:
            return true
        // Everything else drops down the ladder instead. A timeout was on the
        // list until the tests showed the cost: `turnTimeout` is 60 s, so
        // three attempts is three minutes of someone waiting for an answer
        // that a different provider could have given at once. A bad key does
        // not improve by insisting, and an empty ladder is not a wait — it is
        // a missing configuration.
        default:
            return false
        }
    }

    /// Exponential from one second.
    ///
    /// HACK: it does NOT honour `Retry-After`, which is what the provider
    /// actually asks for and therefore better than any guess. The header never
    /// reaches here: `ChatTransport` surfaces a status code and a line stream,
    /// no headers, so honouring it means changing the port and every adapter
    /// and fake behind it. Upgrade trigger: the first time a provider's own
    /// backoff differs enough from this curve to matter, widen the port
    /// instead of tuning these numbers.
    package static func delay(attempt: Int) -> TimeInterval {
        min(pow(2.0, Double(max(attempt, 1) - 1)), maxDelay)
    }

    /// The error keeps its identity all the way out. Collapsing an exhausted
    /// rate limit into a generic failure is how the truth got lost the first
    /// time.
    package static func exhausted(_ error: ChatError) -> ChatError { error }
}
