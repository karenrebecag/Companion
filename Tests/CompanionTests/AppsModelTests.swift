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
    /// Wave 16k-2b: how many times the poll loop actually asked, and a gate
    /// so a test can hold one call open to prove a late answer is discarded.
    private(set) var accountsCallCount = 0
    var gateAccounts = false
    private var accountsWaiters: [CheckedContinuation<Void, Never>] = []

    func catalog(query: String, after: String?) async throws -> CatalogPage {
        queries.append((query, after))
        if slowPages { try await Task.sleep(for: .milliseconds(50)) }
        if let catalogFailure { throw catalogFailure }
        return pages["\(query)|\(after ?? "")"] ?? CatalogPage(apps: [], total: 0, next: nil)
    }

    func accounts() async throws -> [ConnectedAccount] {
        accountsCallCount += 1
        if gateAccounts {
            await withCheckedContinuation { accountsWaiters.append($0) }
        }
        if accountsHang { try await Task.sleep(for: .milliseconds(50)) }
        return try accountsResult.get()
    }

    var gatedAccountsCallCount: Int { accountsWaiters.count }

    func releaseAccounts() {
        let waiters = accountsWaiters
        accountsWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    /// Only the named apps' connectLink calls park — lets a test hold one
    /// app's attempt open while another's runs to completion around it.
    var gateConnectLinkFor: Set<String> = []
    /// Same idea, but consumed on the first park: a same-app double-tap
    /// needs attempt A's call held while attempt B's (same slug) goes
    /// straight through, which a set keyed only by slug cannot tell apart.
    var gateConnectLinkOnceFor: Set<String> = []
    private var connectLinkWaiters: [CheckedContinuation<Void, Never>] = []
    var gatedConnectLinkCallCount: Int { connectLinkWaiters.count }

    func releaseConnectLink() {
        let waiters = connectLinkWaiters
        connectLinkWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    func connectLink(app: String) async throws -> URL {
        if gateConnectLinkFor.contains(app) || gateConnectLinkOnceFor.remove(app) != nil {
            await withCheckedContinuation { connectLinkWaiters.append($0) }
            // A real URLSession/Task request cancelled mid-flight throws,
            // not returns — the same shape `AppsManualSleeper.sleep` uses.
            try Task.checkCancellation()
        }
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
private func model(
    _ fake: FakeApps, secrets: TestSecretStore = TestSecretStore(),
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
    now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
    openBrowser: @escaping @Sendable (URL) -> Void = { _ in }
) -> (AppsModel, UserDefaults) {
    let defaults = UserDefaults(suiteName: "apps-\(UUID().uuidString)")!
    return (AppsModel(
        secrets: secrets, defaults: defaults, makeService: { _, _ in fake },
        sleep: sleep, now: now, openBrowser: openBrowser), defaults)
}

/// A manual clock so a global-timeout test can jump straight past the cap
/// instead of driving 40 real poll cycles. Named apart from VoiceSessionFakes'
/// own `TestClock` (a different shape, module-visible) to avoid colliding.
private final class PollClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    init(_ value: TimeInterval = 0) { self.value = value }

    func set(_ value: TimeInterval) { lock.withLock { self.value = value } }
    func now() -> TimeInterval { lock.withLock { value } }
}

/// A thread-safe sink for URLs `openBrowser` records — the closure itself
/// must be `@Sendable`, so a plain captured `var` cannot mutate inside it.
private final class URLSink: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []

    func append(_ url: URL) { lock.withLock { urls.append(url) } }
}

/// A manual sleeper (mirrors SessionModelTests' own `ManualSleeper`, same
/// name space clash as `TestClock` above): `sleep` parks until the test
/// releases it, so a poll loop's 3 s interval never actually waits real time.
private final class AppsManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var pending: Int { lock.withLock { waiters.count } }

    func sleep(_ seconds: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            lock.withLock { waiters.append(continuation) }
        }
        try Task.checkCancellation()
    }

    func fire() {
        let all = lock.withLock { let w = waiters; waiters = []; return w }
        for waiter in all { waiter.resume() }
    }
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

// Wave 16k-2b: the connecting modal's loop — connectLink, open the browser,
// then ConnectPoll driven by /api/accounts every 3 s (here: every `fire()`).

@Test @MainActor func appsModelConnectsOpensTheBrowserPollsAndCompletes() async {
    let fake = FakeApps()
    let sleeper = AppsManualSleeper()
    let opened = URLSink()
    let (apps, _) = model(fake, sleep: sleeper.sleep, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    let slack = app("slack")

    apps.start(slack)
    await pumpUntil("connect: llega a waiting(0)") { apps.connectPhase == .waiting(attempts: 0) }
    #expect(apps.connecting == slack)
    #expect(opened.urls == [URL(string: "https://pipedream.com/_static/connect.html?app=slack")!],
            "connect: el navegador abre el enlace de la función")

    await pumpUntil("connect: primer plazo armado") { sleeper.pending == 1 }
    sleeper.fire()
    await pumpUntil("connect: primer intento sin cuenta") { apps.connectPhase == .waiting(attempts: 1) }
    #expect(apps.state(of: "slack") == nil, "connect: todavía no aparece")

    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    await pumpUntil("connect: segundo plazo armado") { sleeper.pending == 1 }
    sleeper.fire()
    await pumpUntil("connect: completa") { apps.connectPhase == .complete }
    #expect(apps.state(of: "slack") == .connected, "connect: las cuentas se refrescan al completar")

    apps.finishConnecting()
    #expect(apps.connecting == nil, "vamos: cierra el modal")
    #expect(apps.state(of: "slack") == .connected, "vamos: el panel/las tarjetas quedan en conectado")
}

@Test @MainActor func appsModelNeverPollsAfterClose() async {
    let fake = FakeApps()
    let sleeper = AppsManualSleeper()
    let (apps, _) = model(fake, sleep: sleeper.sleep)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    apps.start(app("slack"))
    await pumpUntil("cierre: primer plazo armado") { sleeper.pending == 1 }

    apps.finishConnecting()
    sleeper.fire()
    await settle()
    #expect(fake.accountsCallCount == 0, "cierre: cancelado antes de preguntar de nuevo")
}

// A poll landing after close must not resurrect the phase or mark the app
// connected on a stale answer — close, not the network's timing, decides.
@Test @MainActor func appsModelDiscardsAPollResultThatLandsAfterClose() async {
    let fake = FakeApps()
    fake.gateAccounts = true
    let sleeper = AppsManualSleeper()
    let (apps, _) = model(fake, sleep: sleeper.sleep)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    let slack = app("slack")
    apps.start(slack)
    await pumpUntil("descarte: primer plazo armado") { sleeper.pending == 1 }
    sleeper.fire()
    await pumpUntil("descarte: la llamada queda detenida en la compuerta") { fake.gatedAccountsCallCount == 1 }

    apps.finishConnecting()
    fake.accountsResult = .success([ConnectedAccount(id: "apn_1", app: "slack", name: nil, state: .connected)])
    fake.releaseAccounts()
    await settle()

    #expect(apps.connecting == nil, "descarte: sigue cerrado")
    #expect(apps.connectPhase == .initiating, "descarte: nada revive el modal")
    #expect(apps.state(of: "slack") == nil, "descarte: la respuesta tardía no marca conectado")
}

@Test @MainActor func appsModelOpenAgainReopensTheSameLink() async {
    let fake = FakeApps()
    let sleeper = AppsManualSleeper()
    let opened = URLSink()
    let (apps, _) = model(fake, sleep: sleeper.sleep, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    apps.start(app("slack"))
    await pumpUntil("abrir de nuevo: primer plazo armado") { sleeper.pending == 1 }
    #expect(opened.urls.count == 1)
    apps.openAgain()
    #expect(opened.urls.count == 2)
    #expect(opened.urls[0] == opened.urls[1], "abrir de nuevo: el mismo enlace, no uno nuevo")
}

@Test @MainActor func appsModelRetryStartsAFreshAttemptAfterATimeout() async {
    let fake = FakeApps()
    let sleeper = AppsManualSleeper()
    let clock = PollClock(0)
    let opened = URLSink()
    let (apps, _) = model(fake, sleep: sleeper.sleep, now: clock.now, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    apps.start(app("slack"))
    await pumpUntil("reintentar: primer plazo armado") { sleeper.pending == 1 }

    // Jumps the injected clock past the 150 s global cap (spec §9.5 D2) so
    // the very next check times the attempt out without 40 real cycles.
    clock.set(ConnectPoll.overallTimeout + 1)
    sleeper.fire()
    await pumpUntil("reintentar: se agota") { apps.connectPhase == .timedOut }

    clock.set(ConnectPoll.overallTimeout + 2)
    apps.retryConnecting()
    await pumpUntil("reintentar: vuelve a waiting(0)") { apps.connectPhase == .waiting(attempts: 0) }
    #expect(opened.urls.count == 2, "reintentar: un enlace nuevo (el anterior puede ya estar gastado)")
}

@Test @MainActor func appsModelFailsWhenConnectLinkErrors() async {
    let fake = FakeApps()
    fake.connectFailure = .rateLimited
    let (apps, _) = model(fake)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    apps.start(app("slack"))
    await pumpUntil("falla: connectLink erróneo llega como fallo del modal") {
        if case .failed = apps.connectPhase { return true }
        return false
    }
}

// A stale attempt (start(_:) for one app, then another before the first's
// connectLink even answers) must never paint its late answer over the app
// that actually owns the modal now — including which link the browser opens.
@Test @MainActor func appsModelDiscardsAStaleConnectLinkFromASupersededAttempt() async {
    let fake = FakeApps()
    fake.gateConnectLinkFor = ["slack"]
    let opened = URLSink()
    let (apps, _) = model(fake, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    let slack = app("slack")
    let gmail = app("gmail")

    apps.start(slack)
    await pumpUntil("carrera: connectLink de slack queda detenido") { fake.gatedConnectLinkCallCount == 1 }
    // Switches to gmail before slack's connectLink ever answers; gmail's own
    // call is not gated, so its attempt runs to waiting(0) around slack's.
    apps.start(gmail)
    await pumpUntil("carrera: gmail sigue su propio camino") { apps.connectPhase == .waiting(attempts: 0) }
    #expect(apps.connecting == gmail)

    fake.releaseConnectLink()
    await settle()
    #expect(apps.connecting == gmail, "carrera: slack no recupera el modal")
    #expect(opened.urls == [URL(string: "https://pipedream.com/_static/connect.html?app=gmail")!],
            "carrera: el enlace tardío de slack nunca se abre para el intento de gmail")
}

// Code review + security review (HIGH, same finding independently): `stillConnecting`
// only compared slugs, so a SAME-app double-tap — attempt A still parked in
// connectLink/accounts() while attempt B (same slug) runs — let A's late,
// cancelled resolution pass every guard: a spent link reopened, or a
// spurious `.failed` painted over B's healthy state.
@Test @MainActor func appsModelDiscardsAStaleConnectLinkFromADoubleTappedConectar() async {
    let fake = FakeApps()
    fake.gateConnectLinkOnceFor = ["slack"]
    let opened = URLSink()
    let (apps, _) = model(fake, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    let slack = app("slack")

    apps.start(slack) // attempt A: connectLink parks
    await pumpUntil("doble toque: intento A detenido") { fake.gatedConnectLinkCallCount == 1 }

    apps.start(slack) // attempt B, same slug: A is superseded, not just cancelled-and-gone
    await pumpUntil("doble toque: B llega a waiting(0)") { apps.connectPhase == .waiting(attempts: 0) }
    #expect(opened.urls.count == 1, "doble toque: solo el enlace de B se abrió hasta ahora")

    // A's connectLink resumes now that it is cancelled: a real request would
    // throw, not hand back a link for a task nobody is waiting on anymore.
    fake.releaseConnectLink()
    await settle()

    #expect(opened.urls.count == 1, "doble toque: la respuesta tardía de A nunca reabre el navegador")
    #expect(apps.connectPhase == .waiting(attempts: 0), "doble toque: B sigue sano, sin un .failed espurio")
}

// Same defect, reached through "Reintentar" pressed twice: R1 parked in its
// fresh connectLink while R2 (the second tap) already runs.
@Test @MainActor func appsModelDiscardsAStaleRetryFromADoubleTappedReintentar() async {
    let fake = FakeApps()
    let sleeper = AppsManualSleeper()
    let clock = PollClock(0)
    let opened = URLSink()
    let (apps, _) = model(fake, sleep: sleeper.sleep, now: clock.now, openBrowser: opened.append)
    _ = apps.configure(endpoint: "https://x.vercel.app", key: String(repeating: "k", count: 64))
    apps.start(app("slack"))
    await pumpUntil("reintentar doble: primer plazo armado") { sleeper.pending == 1 }
    clock.set(ConnectPoll.overallTimeout + 1)
    sleeper.fire()
    await pumpUntil("reintentar doble: se agota") { apps.connectPhase == .timedOut }
    #expect(opened.urls.count == 1)

    fake.gateConnectLinkOnceFor = ["slack"]
    clock.set(ConnectPoll.overallTimeout + 2)
    apps.retryConnecting() // R1: connectLink parks
    await pumpUntil("reintentar doble: R1 detenido") { fake.gatedConnectLinkCallCount == 1 }

    clock.set(ConnectPoll.overallTimeout + 3)
    apps.retryConnecting() // R2, same slug: supersedes R1
    await pumpUntil("reintentar doble: R2 llega a waiting(0)") { apps.connectPhase == .waiting(attempts: 0) }
    #expect(opened.urls.count == 2, "reintentar doble: solo el enlace de R2 se sumó")

    fake.releaseConnectLink()
    await settle()

    #expect(opened.urls.count == 2, "reintentar doble: R1 no reabre el navegador al resolver tarde")
    #expect(apps.connectPhase == .waiting(attempts: 0), "reintentar doble: R2 sigue sano")

    // Only R2's loop should be polling: one sleeper cycle is one accounts() call.
    let before = fake.accountsCallCount
    await pumpUntil("reintentar doble: el próximo plazo se arma") { sleeper.pending == 1 }
    sleeper.fire()
    await pumpUntil("reintentar doble: una sola pregunta") { fake.accountsCallCount == before + 1 }
    await settle()
    #expect(fake.accountsCallCount == before + 1, "reintentar doble: ningún segundo bucle duplicó la pregunta")
}
