import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 15d perf: Whisper's vocabulary closure used to read /Applications on
// every release — on the path the user is waiting on. The cache answers from
// memory; a stale answer (60 s) schedules a refresh off that path.

@Test @MainActor func installedAppsCacheTests() {
    testReleasePathNeverLoadsSynchronously()
    testStaleAfterSixtySecondsSchedulesOneRefresh()
    testPrewarmLoadsOnceOffThePath()
}

private final class CacheProbe: @unchecked Sendable {
    let lock = NSLock()
    var loads = 0
    var now = Date(timeIntervalSince1970: 1_000)
    var scheduled: [@Sendable () -> Void] = []

    func makeCache() -> InstalledAppsCache {
        InstalledAppsCache(
            load: { [self] in
                lock.withLock { loads += 1 }
                return ["Safari", "Notas"]
            },
            now: { [self] in lock.withLock { now } },
            schedule: { [self] work in lock.withLock { scheduled.append(work) } })
    }

    func runScheduled() {
        let work = lock.withLock {
            let all = scheduled
            scheduled = []
            return all
        }
        for item in work { item() }
    }
}

@MainActor func testReleasePathNeverLoadsSynchronously() {
    let probe = CacheProbe()
    let cache = probe.makeCache()
    expectEq(cache.names(), [], "perf: sin carga previa responde vacío, sin tocar disco")
    expectEq(probe.loads, 0, "perf: names() nunca lee el disco en línea")
    expectEq(probe.scheduled.count, 1, "perf: pide una recarga fuera del camino")
    _ = cache.names()
    expectEq(probe.scheduled.count, 1, "perf: una sola recarga en vuelo")
    probe.runScheduled()
    expectEq(cache.names(), ["Safari", "Notas"], "perf: la siguiente vez ya está en memoria")
    expectEq(probe.loads, 1, "perf: una sola lectura de disco")
    expect(probe.scheduled.isEmpty, "perf: fresco, no vuelve a programar")
}

@MainActor func testStaleAfterSixtySecondsSchedulesOneRefresh() {
    let probe = CacheProbe()
    let cache = probe.makeCache()
    cache.prewarm()
    probe.runScheduled()
    probe.now = probe.now.addingTimeInterval(59)
    _ = cache.names()
    expect(probe.scheduled.isEmpty, "perf: a los 59 s sigue fresco")
    probe.now = probe.now.addingTimeInterval(2)
    expectEq(cache.names(), ["Safari", "Notas"], "perf: viejo, responde lo que tiene")
    expectEq(probe.scheduled.count, 1, "perf: y programa una recarga")
    probe.runScheduled()
    expectEq(probe.loads, 2, "perf: como mucho una lectura cada 60 s")
}

@MainActor func testPrewarmLoadsOnceOffThePath() {
    let probe = CacheProbe()
    let cache = probe.makeCache()
    cache.prewarm()
    cache.prewarm()
    expectEq(probe.loads, 0, "perf: prewarm no lee en línea")
    expectEq(probe.scheduled.count, 1, "perf: un solo prewarm en vuelo")
    probe.runScheduled()
    expectEq(probe.loads, 1, "perf: prewarm carga una vez")
}
