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
    }

    /// HACK: a bounded window, not every id ever seen. A peer that has
    /// burned this many ids since can reuse the oldest one; the rate
    /// budgets cap how fast that can happen. Upgrade trigger: ids proven
    /// to be non-monotonic and long-lived, then keep a high-water mark.
    public static let capacity = 256

    private enum Entry: Sendable, Equatable {
        case running
        case done(String)
    }

    private var entries: [Int: Entry] = [:]
    private var order: [Int] = []

    public init() {}

    public var count: Int { entries.count }

    /// Marks `id` as running when it is new; otherwise says what it was.
    public mutating func begin(_ id: Int) -> Begin {
        switch entries[id] {
        case .some(.done(let reply)): return .replay(reply)
        case .some(.running): return .inFlight
        case .none:
            entries[id] = .running
            order.append(id)
            evictOverflow()
            return .fresh
        }
    }

    /// Records the answer for a request `begin` accepted.
    public mutating func finish(_ id: Int, reply: String) {
        guard entries[id] != nil else { return }
        entries[id] = .done(reply)
    }

    /// The request produced nothing to replay (its connection went away).
    public mutating func abandon(_ id: Int) {
        entries.removeValue(forKey: id)
        order.removeAll { $0 == id }
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
        if case .some(.done) = entry { return true }
        return false
    }
}
