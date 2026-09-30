import CompanionCore
import Foundation

/// Where the island's events wait for the next turn (16h-3): the session
/// model writes, the context sensor drains.
public final class IslandEventBuffer: IslandEventSink, IslandEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var log = IslandEventLog()

    public init() {}

    public func record(_ event: IslandEvent) {
        lock.withLock { log.record(event) }
    }

    public func pending() -> IslandEventBatch {
        lock.withLock { log.peek() }
    }

    public func acknowledge(through: Int) {
        lock.withLock { log.acknowledge(through: through) }
    }
}
