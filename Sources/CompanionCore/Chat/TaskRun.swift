import Foundation

/// The real work state of a task (spec 16j-3): Home and the detail sheet read
/// this instead of guessing from the last message. A terminal state sticks, so
/// a late "finished" can never paper over a failure that already landed.
package struct TaskRun: Sendable, Equatable {
    package enum State: String, Sendable {
        case running, done, failed
    }

    package let state: State
    package let startedAt: Date
    package let finishedAt: Date?

    package init(state: State, startedAt: Date, finishedAt: Date? = nil) {
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    package static func begin(at date: Date) -> TaskRun {
        TaskRun(state: .running, startedAt: date)
    }

    package func finishing(at date: Date) -> TaskRun { settled(.done, at: date) }

    package func failing(at date: Date) -> TaskRun { settled(.failed, at: date) }

    /// A task saved as running that no turn is working on any more (the app
    /// quit mid-turn) did not finish: showing it as running forever would lie.
    package func shown(live: Bool) -> TaskRun {
        guard state == .running, !live else { return self }
        return TaskRun(state: .failed, startedAt: startedAt, finishedAt: nil)
    }

    /// Nil for a task interrupted without an end time: a made-up duration
    /// would read as real.
    package func duration(now: Date) -> TimeInterval? {
        switch state {
        case .running: max(now.timeIntervalSince(startedAt), 0)
        case .done, .failed: finishedAt.map { max($0.timeIntervalSince(startedAt), 0) }
        }
    }

    private func settled(_ next: State, at date: Date) -> TaskRun {
        guard state == .running else { return self }
        return TaskRun(state: next, startedAt: startedAt, finishedAt: date)
    }
}
