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

    func catalog(query: String, after: String?) async throws -> CatalogPage {
        queries.append((query, after))
        if slowPages { try await Task.sleep(for: .milliseconds(50)) }
        if let catalogFailure { throw catalogFailure }
        return pages["\(query)|\(after ?? "")"] ?? CatalogPage(apps: [], total: 0, next: nil)
    }

    func accounts() async throws -> [ConnectedAccount] { try accountsResult.get() }

    func connectLink(app: String) async throws -> URL {
        if let connectFailure { throw connectFailure }
        return URL(string: "https://pipedream.com/_static/connect.html?app=\(app)")!
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
