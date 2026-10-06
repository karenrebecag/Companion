/// Decides whether a queued "move to the new input" request may still run.
/// Pure so the races are tested without an engine: a request carries the
/// generation it saw when it was raised, and anything that changes what the
/// mic is doing (a stop, a restart already taken) retires older requests.
package struct MicRestartGate: Equatable, Sendable {
    package private(set) var generation = 0

    package init() {}

    /// What a trigger records when it is raised.
    package var ticket: Int { generation }

    /// A stop or any halt from outside: queued restarts must not reopen the mic.
    package mutating func invalidate() { generation += 1 }

    /// A retry stamps its ticket where it decided, after its own halt: a stop
    /// since then has moved the generation and the retry must not reopen.
    package func stillCurrent(_ ticket: Int) -> Bool { ticket == generation }

    /// True at most once per ticket, and only while the mic is running.
    package mutating func admit(ticket: Int, running: Bool) -> Bool {
        guard running, ticket == generation else { return false }
        generation += 1
        return true
    }
}
