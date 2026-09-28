import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 16k-1: the Apps page's state. Without the function set up the page
// asks for it; set up, it lists, searches, pages and marks what is connected.

private final class FakeApps: AppsService, @unchecked Sendable {
    var pages: [String: CatalogPage] = [:]
    var accountsResult: Result<[ConnectedAccount], AppsFailure> = .success([])
    var catalogFailure: AppsFailure?
    var queries: [(String, String?)] = []
    var connectFailure: AppsFailure?
    var slowPages = false
    var toolsResult: Result<[AppAction], AppsFailure> = .success([])
    var toolsCalls: [String] = []
    /// Wave 16k-2a review (HIGH): accounts() lagging behind catalog() is the
    /// shape of the load() race.
    var accountsHang = false

    func catalog(query: String, after: String?) async throws -> CatalogPage {
        queries.append((query, after))
        if slowPages { try await Task.sleep(for: .milliseconds(50)) }
        if let catalogFailure { throw catalogFailure }
        return pages["\(query)|\(after ?? "")"] ?? CatalogPage(apps: [], total: 0, next: nil)
    }

    func accounts() async throws -> [ConnectedAccount] {
        if accountsHang { try await Task.sleep(for: .milliseconds(50)) }
        return try accountsResult.get()
    }

    func connectLink(app: String) async throws -> URL {
        if let connectFailure { throw connectFailure }
        return URL(string: "https://pipedream.com/_static/connect.html?app=\(app)")!
    }

    func tools(app: String) async throws -> [AppAction] {
        toolsCalls.append(app)
        return try toolsResult.get()
    }
}

private func app(_ slug: String) -> CatalogApp {
    CatalogApp(slug: slug, name: slug.capitalized, description: nil, icon: nil)
}

@MainActor
private func model(_ fake: FakeApps, secrets: TestSecretStore = TestSecretStore()) -> (AppsModel, UserDefaults) {
    let defaults = UserDefaults(suiteName: "apps-\(UUID().uuidString)")!
    return (AppsModel(secrets: secrets, defaults: defaults, makeService: { _, _ in fake }), defaults)
}

@Test @MainActor func appsPageAsksForTheFunctionFirst() async {
    let fake = FakeApps()
    let (apps, _) = model(fake)
    await apps.load()
    #expect(apps.phase == .setup, "sin función: la página la pide")
    #expect(fake.queries.isEmpty, "y no llama a nadie")
    #expect(!apps.configure(endpoint: "http://x.vercel.app", key: String(repeating: "k", count: 64)),
            "http no")
    #expect(!apps.configure(endpoint: "https://x.vercel.app", key: "corta"), "clave corta no")
    #expect(apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64)))
}

@Test @MainActor func appsPageListsSearchesAndPages() async {
    let fake = FakeApps()
    fake.pages["|"] = CatalogPage(apps: [app("slack"), app("gmail")], total: 1734, next: "c2")
    fake.pages["|c2"] = CatalogPage(apps: [app("notion")], total: 1734, next: nil)
    fake.pages["sla|"] = CatalogPage(apps: [app("slack")], total: 1, next: nil)
    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    let secrets = TestSecretStore()
    let (apps, _) = model(fake, secrets: secrets)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    #expect(apps.phase == .ready)
    #expect(apps.apps.map(\.slug) == ["slack", "gmail"])
    #expect(apps.total == 1734)
    #expect(apps.remaining == 1732, "Mostrar más (N restantes)")
    #expect(apps.state(of: "slack") == .connected)
    #expect(apps.state(of: "gmail") == nil)
    await apps.more()
    #expect(apps.apps.map(\.slug) == ["slack", "gmail", "notion"])
    #expect(!apps.hasMore)
    await apps.search("sla")
    #expect(apps.apps.map(\.slug) == ["slack"], "buscar reemplaza la lista")
    #expect((try? secrets.read(.companionApps)) == String(repeating: "k", count: 64), "la clave va al llavero")
}

@Test @MainActor func appsPageSaysWhatFailed() async {
    let fake = FakeApps()
    fake.catalogFailure = .notConfigured(["PIPEDREAM_CLIENT_ID"])
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    #expect(apps.phase == .failed(.notConfigured(["PIPEDREAM_CLIENT_ID"])))
    fake.catalogFailure = nil
    fake.accountsResult = .failure(.upstream)
    await apps.load()
    #expect(apps.phase == .ready, "sin cuentas la página igual lista el catálogo")
}

// Code review 16k-1 (HIGH): a failed Connect is about one card; the page
// keeps its list.
@Test @MainActor func appsPageKeepsTheListWhenAConnectFails() async {
    let fake = FakeApps()
    fake.pages["|"] = CatalogPage(apps: [app("slack")], total: 1, next: nil)
    fake.connectFailure = .rateLimited
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    #expect(await apps.connect("slack") == nil)
    #expect(apps.phase == .ready, "la rejilla sigue")
    #expect(apps.connectError == .rateLimited, "el fallo se dice aparte")
    fake.connectFailure = nil
    #expect(await apps.connect("slack") != nil)
    #expect(apps.connectError == nil)
}

// Wave 16k-2a: the panel opens on a card tap and loads that app's actions —
// but only once it is connected (audit §9.6: unconnected never lists).
@Test @MainActor func appsModelOpensThePanelAndLoadsActionsWhenConnected() async {
    let fake = FakeApps()
    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    let listChannels = AppAction(slug: "slack-list-channels", name: "Slack List Channels",
                                  description: "List channels", group: .leer)
    fake.toolsResult = .success([listChannels])
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    let slack = app("slack")
    apps.open(slack)
    #expect(apps.selected == slack)
    #expect(apps.actionsPhase == .idle, "opening alone does not fetch; the view drives the fetch")
    await apps.actions(of: slack)
    #expect(apps.actionsPhase == .ready([listChannels]))
    #expect(fake.toolsCalls == ["slack"])
    apps.closePanel()
    #expect(apps.selected == nil)
    #expect(apps.actionsPhase == .idle, "closing drops a stale answer for the next app")
}

@Test @MainActor func appsModelNeverListsToolsForAnUnconnectedApp() async {
    let fake = FakeApps()
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    let gmail = app("gmail")
    apps.open(gmail)
    await apps.actions(of: gmail)
    #expect(apps.actionsPhase == .idle, "not connected: no call, no groups")
    #expect(fake.toolsCalls.isEmpty)
}

@Test @MainActor func appsModelSaysWhenActionsFailOrComeBackEmpty() async {
    let fake = FakeApps()
    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    fake.toolsResult = .failure(.upstream)
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    let slack = app("slack")
    apps.open(slack)
    await apps.actions(of: slack)
    #expect(apps.actionsPhase == .failed(.upstream))

    fake.toolsResult = .success([])
    apps.open(slack)
    await apps.actions(of: slack)
    #expect(apps.actionsPhase == .ready([]), "connected but nothing listed is still its own state, not a failure")
}

// Code review 16k-2a (HIGH): the old load() flipped `phase` to .ready right
// after catalog() resolved, before accounts() did. A card tapped in that
// window ran actions(of:) against a still-empty accounts dict, and once
// accounts finally arrived nothing re-triggered the fetch — the panel was
// stuck on ProgressView() forever. The fix awaits both before .ready, so the
// catalog (and its now-tappable cards) never appears ahead of the marks.
@Test @MainActor func appsModelNeverGoesReadyBeforeAccountsResolve() async {
    let fake = FakeApps()
    fake.pages["|"] = CatalogPage(apps: [app("slack")], total: 1, next: nil)
    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    fake.accountsHang = true
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    let loadTask = Task { await apps.load() }
    // The catalog leg resolves fast; accounts() is still hanging here.
    try? await Task.sleep(for: .milliseconds(10))
    #expect(apps.phase != .ready, "phase must not go ready while accounts is still stale")
    let slack = app("slack")
    apps.open(slack)
    await apps.actions(of: slack)
    #expect(apps.actionsPhase == .idle, "not marked connected yet, so no fetch — correct for this instant")
    await loadTask.value
    // Once load() returns, phase and accounts must agree: no leftover window.
    #expect(apps.phase == .ready)
    #expect(apps.state(of: "slack") == .connected)
    await apps.actions(of: slack)
    #expect(apps.actionsPhase != .idle, "now connected, loading actually runs — never stuck")
}

// Code review 16k-1 (HIGH): two taps on "Show more" fetch one page, once.
@Test @MainActor func appsPageFetchesEachPageOnce() async {
    let fake = FakeApps()
    fake.pages["|"] = CatalogPage(apps: [app("slack")], total: 2, next: "c2")
    fake.pages["|c2"] = CatalogPage(apps: [app("gmail")], total: 2, next: nil)
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    await apps.load()
    fake.slowPages = true
    async let first: Void = apps.more()
    async let second: Void = apps.more()
    _ = await (first, second)
    #expect(apps.apps.map(\.slug) == ["slack", "gmail"])
    #expect(fake.queries.filter { $0.1 == "c2" }.count == 1)
}
