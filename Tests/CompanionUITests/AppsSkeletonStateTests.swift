import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// When the Apps page shows its skeleton. Incredible 0.2.36 draws
// `connectors-skeleton` while its catalog fetch is in flight
// (main-BL-DABKy.js @1138275, `k=w.loading||...`). Its catalog is fetched
// by an app-wide provider and searched on the client, so the only time that
// fetch runs with nothing on screen is a load with an empty list. Here a
// search never touches the phase; only `load()` does.

struct ContentRow: Sendable, CustomTestStringConvertible {
    let phase: Phase
    let hasApps: Bool
    let editing: Bool
    let expected: Expected

    enum Phase: Sendable { case setup, loading, ready, failedNotConfigured }
    enum Expected: Sendable { case setup, skeleton, catalog, failedNotConfigured }

    var testDescription: String { "\(phase) hasApps:\(hasApps) editing:\(editing) -> \(expected)" }
}

private let rows: [ContentRow] = [
    // Editing wins over every phase: the form is what the user asked for.
    ContentRow(phase: .setup, hasApps: false, editing: true, expected: .setup),
    ContentRow(phase: .setup, hasApps: true, editing: true, expected: .setup),
    ContentRow(phase: .loading, hasApps: false, editing: true, expected: .setup),
    ContentRow(phase: .loading, hasApps: true, editing: true, expected: .setup),
    ContentRow(phase: .ready, hasApps: false, editing: true, expected: .setup),
    ContentRow(phase: .ready, hasApps: true, editing: true, expected: .setup),
    ContentRow(phase: .failedNotConfigured, hasApps: false, editing: true, expected: .setup),
    ContentRow(phase: .failedNotConfigured, hasApps: true, editing: true, expected: .setup),
    ContentRow(phase: .setup, hasApps: false, editing: false, expected: .setup),
    ContentRow(phase: .setup, hasApps: true, editing: false, expected: .setup),
    ContentRow(phase: .loading, hasApps: false, editing: false, expected: .skeleton),
    ContentRow(phase: .loading, hasApps: true, editing: false, expected: .catalog),
    ContentRow(phase: .ready, hasApps: false, editing: false, expected: .catalog),
    ContentRow(phase: .ready, hasApps: true, editing: false, expected: .catalog),
    ContentRow(phase: .failedNotConfigured, hasApps: false, editing: false, expected: .failedNotConfigured),
    ContentRow(phase: .failedNotConfigured, hasApps: true, editing: false, expected: .failedNotConfigured),
]

@Test(arguments: rows)
@MainActor func appsContentKindCoversEveryState(_ row: ContentRow) {
    let failure = AppsFailure.notConfigured(["X"])
    let phase: AppsModel.Phase = switch row.phase {
    case .setup: .setup
    case .loading: .loading
    case .ready: .ready
    case .failedNotConfigured: .failed(failure)
    }
    let expected: AppsContentKind = switch row.expected {
    case .setup: .setup
    case .skeleton: .skeleton
    case .catalog: .catalog
    case .failedNotConfigured: .failed(failure)
    }
    #expect(AppsContentKind.of(phase: phase, hasApps: row.hasApps, editing: row.editing) == expected)
}

@Test @MainActor func aRefreshOverALoadedListKeepsTheList() {
    let walk: [(AppsModel.Phase, Bool)] = [(.setup, false), (.loading, false), (.ready, true), (.loading, true)]
    let kinds = walk.map { AppsContentKind.of(phase: $0.0, hasApps: $0.1, editing: false) }
    #expect(kinds == [.setup, .skeleton, .catalog, .catalog])
}

/// Answers each query from `pages`; once `stall` is set, every later call
/// hangs, which holds the model on `.loading` for as long as a test needs.
private final class QueryApps: AppsService, @unchecked Sendable {
    var pages: [String: [CatalogApp]] = [:]
    var stall = false
    func catalog(query: String, after: String?) async throws -> CatalogPage {
        if stall { try await Task.sleep(for: .seconds(3600)) }
        let apps = pages[query] ?? []
        return CatalogPage(apps: apps, total: apps.count, next: nil)
    }
    func accounts() async throws -> [ConnectedAccount] { [] }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}

@Test @MainActor func aReloadAfterASearchWithNoResultsShowsTheSkeleton() async throws {
    let service = QueryApps()
    service.pages[""] = [CatalogApp(slug: "slack", name: "Slack", description: nil, icon: nil)]
    let apps = AppsModel(
        secrets: TestSecretStore(), hostSecrets: TestHostSecretStore(),
        defaults: UserDefaults(suiteName: "apps-state-\(UUID().uuidString)")!,
        makeService: { _, _ in service })
    #expect(apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64)))
    await apps.load()
    await apps.search("zzz")
    // The empty answer is an answer: it reads "no app matches", not a wait.
    #expect(AppsContentKind.of(phase: apps.phase, hasApps: !apps.apps.isEmpty, editing: false) == .catalog)
    service.stall = true
    let reload = Task { await apps.load() }
    defer { reload.cancel() }
    try await waitForLoading(apps)
    #expect(AppsContentKind.of(phase: apps.phase, hasApps: !apps.apps.isEmpty, editing: false) == .skeleton)
}

@MainActor private func waitForLoading(_ apps: AppsModel) async throws {
    for _ in 0..<1000 where apps.phase != .loading { await Task.yield() }
    try #require(apps.phase == .loading, "the model never reached .loading")
}

// SwiftUI's accessibilityReduceMotion cannot be set from a test, so the
// wiring is checked the way ChromeMotionTests checks the window chrome: the
// pure decision, plus every value SkeletonPulse hands its content going
// through that decision with the environment's flag.
@Test @MainActor func skeletonPulseHandsOutFullStrengthUnderReduceMotion() {
    for t in [0.25, 1, 1.75, 3] {
        #expect(SkeletonMotion.opacity(elapsed: t, reduceMotion: true) == 1)
    }
    #expect(SkeletonMotion.opacity(elapsed: 1, reduceMotion: false) < 0.6, "control: the pulse dims without it")
    guard let root = Conformance.repoRoot() else { return }
    let lines = Conformance.logicalLines(
        of: root.appendingPathComponent("Sources/CompanionUI/DesignSystem/Skeleton.swift"))
    #expect(lines.contains { $0.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion") })
    let handOuts = lines.filter { $0.contains("content(") && !$0.contains("let content") }
    #expect(handOuts.count == 2, "the moving and the still branch")
    #expect(handOuts.allSatisfy { $0.contains("SkeletonMotion.opacity(") && $0.contains("reduceMotion: reduceMotion") },
            "no branch hands out an opacity that skips the decision: \(handOuts)")
}

@Test @MainActor func loaderArcAndPulseHoldAtTheirEdges() {
    #expect(LoaderArcMotion.degrees(elapsed: 1.0) == 0, "a full turn lands back at the start")
    #expect(LoaderArcMotion.degrees(elapsed: -0.5) == 0, "a clock that runs backwards never spins backwards")
    #expect(abs(LoaderArcMotion.degrees(elapsed: 1_000_000.25) - 90) < 1e-3)
    #expect(SkeletonMotion.opacity(elapsed: -0.5) == 1)
    #expect(abs(SkeletonMotion.opacity(elapsed: 2 - 1e-9) - 1) < 1e-6, "just before the cycle closes")
    #expect(abs(SkeletonMotion.opacity(elapsed: 1 - 1e-9) - 0.5) < 1e-6, "just before the dim keyframe")
    #expect(abs(SkeletonMotion.opacity(elapsed: 1_000_001) - 0.5) < 1e-6)
}
