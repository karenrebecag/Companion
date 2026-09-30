import Foundation

/// Wave 15d perf: Whisper's spelling bias (15d-8) wants the installed app
/// names, and reading /Applications on every release put disk I/O on the
/// path the user waits on. `names()` only ever answers from memory; a stale
/// or empty answer schedules one background refresh for the next hold.
package final class InstalledAppsCache: @unchecked Sendable {
    /// Apps get installed rarely; a minute-old list costs one missed name.
    package static let maxAge: TimeInterval = 60

    private let load: @Sendable () -> [String]
    private let now: @Sendable () -> Date
    private let schedule: @Sendable (@escaping @Sendable () -> Void) -> Void
    private let lock = NSLock()
    private var cached: [String] = []
    private var loadedAt: Date?
    private var refreshing = false

    package init(
        load: @escaping @Sendable () -> [String],
        now: @escaping @Sendable () -> Date = { Date() },
        schedule: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = { work in
            Task.detached(priority: .utility) { work() }
        }
    ) {
        self.load = load
        self.now = now
        self.schedule = schedule
    }

    package func names() -> [String] {
        let (names, stale) = lock.withLock { () -> ([String], Bool) in
            let stale = loadedAt.map { now().timeIntervalSince($0) >= Self.maxAge } ?? true
            return (cached, stale)
        }
        if stale { prewarm() }
        return names
    }

    /// Launch calls this so the first hold already has the list.
    package func prewarm() {
        let start = lock.withLock { () -> Bool in
            guard !refreshing else { return false }
            refreshing = true
            return true
        }
        guard start else { return }
        schedule { [self] in
            let fresh = load()
            lock.withLock {
                cached = fresh
                loadedAt = now()
                refreshing = false
            }
        }
    }
}
