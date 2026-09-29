import CompanionCore
import Foundation

/// 16m-7: the files she opened lately, from Spotlight's own metadata. Names
/// and paths only, never contents; Spotlight answers without triggering any
/// folder permission dialog. Cached briefly because the selector asks on
/// every keystroke.
///
/// One query at a time, shared by whoever asks, and owned by no caller: the
/// selector cancels its own work on every key, and a cancelled caller must
/// neither abort the query nor leave an empty answer in the cache. A query
/// that failed or ran out of time is never cached.
public final class RecentFiles: @unchecked Sendable {
    /// Own values: two weeks back, forty files, one minute of cache.
    static let days = 14
    static let limit = 40
    static let cacheSeconds: TimeInterval = 60

    typealias Runner = @Sendable (_ days: Int, _ limit: Int) async -> [String]?

    private let lock = NSLock()
    private var cached: [MentionCandidate] = []
    private var stamp = Date.distantPast
    private var inFlight: Task<[MentionCandidate], Never>?
    private let home = NSHomeDirectory()
    private let runner: Runner

    public convenience init() {
        self.init(runner: { days, limit in await SpotlightRecents.paths(days: days, limit: limit) })
    }

    init(runner: @escaping Runner) {
        self.runner = runner
    }

    /// Files Spotlight may return: not a folder, not a package.
    static func predicate(since: Date) -> NSPredicate {
        NSPredicate(
            format: "%K > %@ AND NOT (%K == 'public.folder') AND NOT (%K == 'com.apple.package')",
            NSMetadataItemLastUsedDateKey, since as NSDate,
            NSMetadataItemContentTypeTreeKey, NSMetadataItemContentTypeTreeKey)
    }

    public func candidates() async -> [MentionCandidate] {
        let task = lock.withLock { () -> Task<[MentionCandidate], Never>? in
            if Date().timeIntervalSince(stamp) < Self.cacheSeconds { return nil }
            if let inFlight { return inFlight }
            // Unstructured on purpose: it must not inherit the caller's cancellation.
            let started = Task<[MentionCandidate], Never> { [runner, home] in
                let paths = await runner(Self.days, Self.limit)
                let found = (paths ?? []).compactMap { MentionFiles.candidate(path: $0, home: home) }
                self.finish(found, complete: paths != nil)
                return found
            }
            inFlight = started
            return started
        }
        guard let task else { return lock.withLock { cached } }
        return await task.value
    }

    private func finish(_ found: [MentionCandidate], complete: Bool) {
        lock.withLock {
            if complete {
                cached = found
                stamp = Date()
            }
            inFlight = nil
        }
    }
}

/// NSMetadataQuery lives on the main run loop; one query per call.
@MainActor
enum SpotlightRecents {
    /// Nil when the query could not start or did not finish in time: partial
    /// results would be cached as if they were the whole answer.
    static func paths(days: Int, limit: Int) async -> [String]? {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        query.predicate = RecentFiles.predicate(since: since)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)]
        guard query.start() else { return nil }
        // Polled: the query reports through a run-loop notification whose
        // closure would have to cross actors; a short poll needs none.
        var waited = 0
        while query.isGathering, waited < 40 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            waited += 1
        }
        let finished = !query.isGathering
        query.stop()
        guard finished else { return nil }
        return (0 ..< min(query.resultCount, limit)).compactMap {
            (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
        }
    }
}
