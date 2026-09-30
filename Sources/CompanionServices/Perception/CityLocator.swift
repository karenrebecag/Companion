import CompanionCore
import Foundation

/// Resolves the system city once per launch and keeps it in memory (16h-3).
/// Concurrent callers share one lookup PER kind: a lookup allowed to put up
/// the permission dialog never joins one that is not, or it would wait for a
/// dialog nobody may show. A miss (no permission yet, no fix) is never
/// cached, so a grant made later still works.
// HACK: the city is cached for the life of the process. Upgrade trigger: a
// user reports a stale city after travelling — re-resolve on a timer or on
// a significant location change.
package final class CachedCityLocator: UserLocating, @unchecked Sendable {
    private let inner: any UserLocating
    private let lock = NSLock()
    private var cached: UserLocation?
    private var inflight: [Bool: Task<UserLocation?, Never>] = [:]

    package init(_ inner: any UserLocating) {
        self.inner = inner
    }

    package func current(prompting: Bool) async -> UserLocation? {
        let task: Task<UserLocation?, Never> = lock.withLock {
            if let cached { return Task { cached } }
            if let running = inflight[prompting] { return running }
            let inner = self.inner
            let started = Task { await inner.current(prompting: prompting) }
            inflight[prompting] = started
            return started
        }
        let result = await task.value
        lock.withLock {
            // Only the slot's own task clears it: a later lookup that took the
            // slot while this one finished must keep it.
            if inflight[prompting] == task { inflight[prompting] = nil }
            if let result { cached = result }
        }
        return result
    }
}
