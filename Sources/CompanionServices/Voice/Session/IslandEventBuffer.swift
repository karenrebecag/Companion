import CompanionCore
import Foundation

/// Where the island's events wait for the next turn (16h-3): the session
/// model writes, the context sensor drains.
package final class IslandEventBuffer: IslandEventSink, IslandEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var log = IslandEventLog()

    package init() {}

    package func record(_ event: IslandEvent) {
        lock.withLock { log.record(event) }
    }

    package func pending() -> IslandEventBatch {
        lock.withLock { log.peek() }
    }

    package func acknowledge(through: Int) {
        lock.withLock { log.acknowledge(through: through) }
    }
}
