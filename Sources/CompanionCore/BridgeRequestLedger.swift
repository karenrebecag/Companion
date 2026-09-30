import Foundation

/// Request ids one bridge connection has used (20c D6, M8a). An id spent on
/// a connection is spent for every tool: repeating it returns the first
/// answer instead of running the call again, so a resend, a retry or a
/// replay cannot double an action, and a read or state tool is covered the
/// same as a write. Pure and per connection: the session starts a new one
/// whenever a connection starts or ends.
public struct BridgeRequestLedger: Sendable, Equatable {
    public enum Begin: Sendable, Equatable {
        case fresh
        /// Already answered: the reply to send again.
        case replay(String)
        /// Still running: no second copy may start beside it.
        case inFlight
        /// Already answered, but the answer was too big to keep: nothing is
        /// replayed and nothing runs again.
        case tooLargeToReplay
    }

    /// What became of a request `begin` accepted. Typed by the caller, which
    /// knows what it built, instead of read back out of the reply text.
    public enum Outcome: Sendable, Equatable {
        /// The call reached its tool (or its gate) and this is the answer.
        case answered(String)
        /// Refused before anything ran: the id stays free.
        case refused
        /// Nothing to send (the connection went away): the id stays free.
        case dropped
    }

    /// The largest answer kept for replay. `see` and `look` frames are the
    /// big ones; a repeat of one of those costs an error line, not memory
    /// held for the life of the connection.
    public static let maxReplayBytes = 16 * 1024

    /// HACK: a bounded window, not every id ever seen. A peer that has
    /// burned this many ids since can reuse the oldest one; the rate
    /// budgets cap how fast that can happen. Upgrade trigger: ids proven
    /// to be non-monotonic and long-lived, then keep a high-water mark.
    public static let capacity = 256

    private enum Entry: Sendable, Equatable {
        case running
        case done(String)
        case tooLarge
    }

    private var entries: [Int: Entry] = [:]
    private var order: [Int] = []

    public init() {}

    public var count: Int { entries.count }

    /// Bytes of replies currently held.
    public var retainedBytes: Int {
        entries.values.reduce(0) { total, entry in
            if case .done(let reply) = entry { return total + reply.utf8.count }
            return total
        }
    }

    /// Marks `id` as running when it is new; otherwise says what it was.
    public mutating func begin(_ id: Int) -> Begin {
        switch entries[id] {
        case .some(.done(let reply)): return .replay(reply)
        case .some(.running): return .inFlight
        case .some(.tooLarge): return .tooLargeToReplay
        case .none:
            entries[id] = .running
            order.append(id)
            evictOverflow()
            return .fresh
        }
    }

    /// Records what became of a request `begin` accepted.
    public mutating func finish(_ id: Int, outcome: Outcome) {
        guard entries[id] != nil else { return }
        switch outcome {
        case .answered(let reply):
            entries[id] = reply.utf8.count > Self.maxReplayBytes ? .tooLarge : .done(reply)
        case .refused, .dropped:
            entries.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
    }

    /// Only answered ids are dropped: one still running must stay findable.
    private mutating func evictOverflow() {
        while order.count > Self.capacity,
              let index = order.firstIndex(where: { isDone(entries[$0]) }) {
            entries.removeValue(forKey: order[index])
            order.remove(at: index)
        }
    }

    private func isDone(_ entry: Entry?) -> Bool {
        if case .some(.running) = entry { return false }
        return entry != nil
    }
}
