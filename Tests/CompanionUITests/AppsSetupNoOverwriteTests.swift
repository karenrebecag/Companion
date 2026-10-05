import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import Testing

// A wrong key or address typed over a working setup used to be written to
// the Keychain and defaults before the function had seen it, so the setup
// that worked was gone the moment the function said no.

private let workingHost = "fn.vercel.app"
private let workingEndpoint = "https://fn.vercel.app"
private let otherHost = "fn2.vercel.app"
private let otherEndpoint = "https://fn2.vercel.app"
private let working = String(repeating: "w", count: 64)
private let rotated = String(repeating: "r", count: 64)
private let wrong = String(repeating: "x", count: 64)
private let wrongAgain = String(repeating: "y", count: 64)

/// The deployed function as the tests drive it: which hosts answer, which
/// keys get past its guard, an outage switch, catalog calls that park until
/// released, and a log of which key asked for what.
private final class Deployment: @unchecked Sendable {
    private let lock = NSLock()
    private var _hosts: Set<String> = [workingHost]
    private var _keys: Set<String> = [working, rotated]
    private var _failure: AppsFailure?
    private var _gateOnce: Set<String> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var _calls: [String] = []

    var failure: AppsFailure? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }

    var calls: [String] { lock.withLock { _calls } }
    var parked: Int { lock.withLock { waiters.count } }

    func addHost(_ host: String) { lock.withLock { _ = _hosts.insert(host) } }
    func revoke(_ key: String) { lock.withLock { _ = _keys.remove(key) } }
    /// The next `op` call made with `key` parks until `release()`.
    func gateOnce(_ key: String, op: String = "catalog") { lock.withLock { _ = _gateOnce.insert("\(op):\(key)") } }

    func release() {
        let all = lock.withLock { let parked = waiters; waiters = []; return parked }
        for waiter in all { waiter.resume() }
    }

    func clearCalls() { lock.withLock { _calls = [] } }

    fileprivate func enter(_ op: String, key: String) async {
        let gated = lock.withLock {
            _calls.append("\(op):\(key.prefix(1))")
            return _gateOnce.remove("\(op):\(key)") != nil
        }
        // Ignores cancellation on purpose: a response that lands right as the
        // caller is dismissed must still not be stored by the model.
        if gated { await withCheckedContinuation { cont in lock.withLock { waiters.append(cont) } } }
    }

    fileprivate func verdict(host: String?, key: String) -> AppsFailure? {
        lock.withLock {
            if let _failure { return _failure }
            guard let host, _hosts.contains(host) else { return .unreachable }
            return _keys.contains(key) ? nil : .unauthorized
        }
    }
}

/// Each key serves its own two-page catalog, so a test can tell which key
/// produced the list on screen.
private func page(for key: String, after: String?) -> CatalogPage {
    let tag = key.prefix(1)
    let slug = after == nil ? "app-\(tag)" : "app-\(tag)2"
    return CatalogPage(apps: [CatalogApp(slug: slug, name: "App", description: nil, icon: nil)],
                       total: 2, next: after == nil ? "c-\(tag)" : nil)
}

/// The account each key's function reports, connected.
private func account(for key: String) -> ConnectedAccount {
    let tag = key.prefix(1)
    return ConnectedAccount(id: "acc-\(tag)", app: "app-\(tag)", name: nil, state: .connected)
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
}

private struct Function: AppsService {
    let url: URL
    let key: String
    let deployment: Deployment

    func catalog(query: String, after: String?) async throws -> CatalogPage {
        await deployment.enter("catalog", key: key)
        if let failure = deployment.verdict(host: url.host, key: key) { throw failure }
        return page(for: key, after: after)
    }

    func accounts() async throws -> [ConnectedAccount] {
        await deployment.enter("accounts", key: key)
        if let failure = deployment.verdict(host: url.host, key: key) { throw failure }
        return [account(for: key)]
    }

    func connectLink(app: String) async throws -> URL {
        await deployment.enter("connectLink", key: key)
        if let failure = deployment.verdict(host: url.host, key: key) { throw failure }
        return URL(string: "https://pipedream.com/_static/connect.html?app=\(app)")!
    }

    func tools(app: String) async throws -> [AppAction] {
        await deployment.enter("tools", key: key)
        if let failure = deployment.verdict(host: url.host, key: key) { throw failure }
        return []
    }

    func disconnect(account: String) async throws {
        await deployment.enter("disconnect", key: key)
        if let failure = deployment.verdict(host: url.host, key: key) { throw failure }
    }
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}

@MainActor
private struct Setup {
    let apps: AppsModel
    let defaults: UserDefaults
    let secrets: TestSecretStore
    let hostSecrets: TestHostSecretStore
    let deployment: Deployment
    let notified: Counter
    let opened: Counter

    func key(at host: String) -> String? {
        do {
            return try hostSecrets.read(.appsKey, host: host)
        } catch {
            return nil
        }
    }

    var storedKey: String? { key(at: workingHost) }
    var storedEndpoint: String? { defaults.string(forKey: AppsModel.endpointDefault) }

    /// The next launch: a new model over the same stores, so it can only
    /// use what was actually persisted.
    func relaunch() -> AppsModel {
        let deployment = deployment
        return AppsModel(
            secrets: secrets, hostSecrets: hostSecrets, defaults: defaults,
            makeService: { url, key in Function(url: url, key: key, deployment: deployment) })
    }
}

/// `working`: seeded straight into the stores, as a previous launch left it.
/// `keyless`: the endpoint is stored but no key is.
@MainActor
private func makeSetup(working seeded: Bool, keyless: Bool = false) throws -> Setup {
    let defaults = UserDefaults(suiteName: "apps-key-\(UUID().uuidString)")!
    let secrets = TestSecretStore()
    let hostSecrets = TestHostSecretStore()
    let deployment = Deployment()
    let notified = Counter()
    let opened = Counter()
    if seeded {
        defaults.set(workingEndpoint, forKey: AppsModel.endpointDefault)
        if !keyless { try hostSecrets.write(.appsKey, host: workingHost, value: working) }
    }
    let apps = AppsModel(
        secrets: secrets, hostSecrets: hostSecrets, defaults: defaults,
        makeService: { url, key in Function(url: url, key: key, deployment: deployment) },
        openBrowser: { _ in opened.bump() },
        notifyAppsChanged: { notified.bump() })
    return Setup(apps: apps, defaults: defaults, secrets: secrets, hostSecrets: hostSecrets,
                 deployment: deployment, notified: notified, opened: opened)
}

/// What the page shows; a rejected setup must not move any of it.
private struct Screen: Equatable {
    // Described, not stored: Phase is Equatable only on the MainActor.
    let phase: String
    let slugs: [String]
    let total: Int
    let hasMore: Bool
    let state: ConnectedAccount.State?
}

@MainActor
private func screen(_ apps: AppsModel) -> Screen {
    Screen(phase: String(describing: apps.phase), slugs: apps.apps.map(\.slug), total: apps.total,
           hasMore: apps.hasMore, state: apps.state(of: "app-w"))
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
}

@Test @MainActor func aWrongKeyNeverReplacesAWorkingOne() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    #expect(setup.apps.phase == .ready)
    setup.deployment.clearCalls()

    let outcome = await setup.apps.configure(endpoint: workingEndpoint, key: wrong)

    #expect(outcome == .rejected(.unauthorized), "la función la rechazó y el formulario lo dice")
    #expect(setup.storedKey == working, "la clave que funcionaba sigue en el llavero")
    #expect(setup.storedEndpoint == workingEndpoint)
    #expect(setup.deployment.calls == ["catalog:x"], "solo la clave nueva habló con la función")
    let next = setup.relaunch()
    await next.load()
    #expect(next.phase == .ready, "al relanzar, la configuración que funcionaba sigue entrando")
    #expect(next.apps.map(\.slug) == ["app-w"])
}

@Test @MainActor func aWrongAddressNeverReplacesAWorkingOne() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()

    let outcome = await setup.apps.configure(endpoint: "https://typo.vercel.app", key: rotated)

    #expect(outcome == .rejected(.unreachable))
    #expect(setup.storedEndpoint == workingEndpoint, "la dirección que funcionaba sigue guardada")
    #expect(setup.storedKey == working, "y su clave no se borró al cambiar de host")
    #expect(setup.key(at: "typo.vercel.app") == nil, "nada quedó en el host nuevo")
    #expect(setup.apps.endpoint == workingEndpoint)
    let next = setup.relaunch()
    await next.load()
    #expect(next.phase == .ready)
    #expect(next.apps.map(\.slug) == ["app-w"])
}

@Test @MainActor func aKeyTheFunctionAcceptsReplacesTheOldOne() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()

    let outcome = await setup.apps.configure(endpoint: workingEndpoint, key: rotated)

    #expect(outcome == .saved)
    #expect(setup.storedKey == rotated)
    #expect(setup.apps.endpoint == workingEndpoint)
    setup.deployment.revoke(working)
    await setup.apps.load()
    #expect(setup.apps.phase == .ready, "con la vieja revocada, la página ya usa la nueva")
    #expect(setup.apps.apps.map(\.slug) == ["app-r"])
    let next = setup.relaunch()
    await next.load()
    #expect(next.phase == .ready)
    #expect(next.apps.map(\.slug) == ["app-r"], "al relanzar entra con la nueva")
}

@Test @MainActor func anAcceptedHostChangeMovesTheKey() async throws {
    let setup = try makeSetup(working: true)
    setup.deployment.addHost(otherHost)
    await setup.apps.load()

    let outcome = await setup.apps.configure(endpoint: otherEndpoint, key: rotated)

    #expect(outcome == .saved)
    #expect(setup.key(at: otherHost) == rotated, "la clave queda ligada al host nuevo")
    #expect(setup.apps.endpoint == otherEndpoint)
    #expect(setup.key(at: workingHost) == nil, "el host que se reemplazó ya no guarda clave")
    let next = setup.relaunch()
    await next.load()
    #expect(next.phase == .ready)
    #expect(next.apps.map(\.slug) == ["app-r"])
}

/// No setup to protect: the first one is stored as before, without asking
/// the function first, and a wrong first key shows up on the first load.
@Test @MainActor func aFirstSetupIsStoredAsBefore() async throws {
    let first = try makeSetup(working: false)
    #expect(await first.apps.configure(endpoint: workingEndpoint, key: working) == .saved)
    #expect(first.storedKey == working)
    #expect(first.storedEndpoint == workingEndpoint)
    #expect(first.deployment.calls.isEmpty, "la primera vez no se le pregunta a la función")
    await first.apps.load()
    #expect(first.apps.phase == .ready)
}

/// The wrong first key is stored, but it is then a setup like any other:
/// another wrong key cannot replace it, and the right one can.
@Test @MainActor func aWrongFirstKeyCanStillBeFixed() async throws {
    let setup = try makeSetup(working: false)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: wrong) == .saved)
    await setup.apps.load()
    #expect(setup.apps.phase == .failed(.unauthorized), "la primera clave mala se ve al cargar")

    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: wrongAgain) == .rejected(.unauthorized))
    #expect(setup.storedKey == wrong)

    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: working) == .saved)
    #expect(setup.storedKey == working)
    await setup.apps.load()
    #expect(setup.apps.phase == .ready)
}

/// An address saved without its key still counts as a setup: the new pair
/// is checked before anything is written.
@Test @MainActor func aStoredEndpointWithoutAKeyIsStillChecked() async throws {
    let setup = try makeSetup(working: true, keyless: true)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: wrong) == .rejected(.unauthorized))
    #expect(setup.storedKey == nil)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: working) == .saved)
    #expect(setup.storedKey == working)
}

enum StartingScreen: String, CaseIterable, Sendable { case ready, failed, setup }

@Test(arguments: StartingScreen.allCases)
@MainActor func aRejectedSetupLeavesThePageAsItWas(_ start: StartingScreen) async throws {
    let setup = try makeSetup(working: true)
    switch start {
    case .ready:
        await setup.apps.load()
    case .failed:
        setup.deployment.failure = .upstream
        await setup.apps.load()
        setup.deployment.failure = nil
    case .setup:
        break
    }
    let before = screen(setup.apps)
    setup.deployment.clearCalls()

    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: wrong) == .rejected(.unauthorized))

    #expect(screen(setup.apps) == before, "nada en pantalla se movió")
    #expect(!setup.deployment.calls.contains { $0.hasSuffix(":w") }, "la configuración vieja no recibió llamadas")
}

/// Offline, a timeout, a rate limit, a function missing its own settings or
/// an answer outside the contract say nothing about the new key: the working
/// setup stays until the function itself accepts the new one.
@Test(arguments: [AppsFailure.unreachable, .rateLimited, .notConfigured(["PIPEDREAM_CLIENT_ID"]), .upstream, .unexpected])
@MainActor func aTransientFailureKeepsTheWorkingSetup(_ failure: AppsFailure) async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    setup.deployment.failure = failure

    let outcome = await setup.apps.configure(endpoint: workingEndpoint, key: rotated)

    #expect(outcome == .rejected(failure))
    #expect(setup.storedKey == working)
    #expect(setup.storedEndpoint == workingEndpoint)
    setup.deployment.failure = nil
    let next = setup.relaunch()
    await next.load()
    #expect(next.apps.map(\.slug) == ["app-w"], "al volver la función, la de antes sigue entrando")
}

/// A caller that cancels its configure mid-check stores nothing, even when
/// the function's yes lands afterwards. (The forms' Tasks are unstructured,
/// so closing them does not cancel; this guards programmatic callers.)
@Test @MainActor func aDismissedCheckKeepsTheWorkingSetup() async throws {
    let setup = try makeSetup(working: true)
    setup.deployment.gateOnce(rotated)

    let attempt = Task { await setup.apps.configure(endpoint: workingEndpoint, key: rotated) }
    await waitUntil { setup.deployment.parked == 1 }
    attempt.cancel()
    setup.deployment.release()
    let outcome = await attempt.value

    #expect(outcome == .rejected(.unexpected))
    #expect(setup.storedKey == working)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved,
            "el cancelado no dejó el modelo bloqueado")
}

/// One check at a time: a second setup while the first is still being
/// checked is refused, whatever either would have answered.
@Test(arguments: [(rotated, wrong), (wrong, rotated)])
@MainActor func aSecondSetupWhileOneIsCheckedIsRefused(_ first: String, _ second: String) async throws {
    let setup = try makeSetup(working: true)
    setup.deployment.gateOnce(first)

    let attempt = Task { await setup.apps.configure(endpoint: workingEndpoint, key: first) }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: second) == .busy)
    #expect(setup.storedKey == working, "la segunda no escribió nada")
    setup.deployment.release()
    let outcome = await attempt.value

    let firstWins = first == rotated
    #expect(outcome == (firstWins ? .saved : .rejected(.unauthorized)))
    #expect(setup.storedKey == (firstWins ? rotated : working), "la rechazada nunca gana")
    setup.deployment.revoke(firstWins ? working : rotated)
    await setup.apps.load()
    #expect(setup.apps.apps.map(\.slug) == [firstWins ? "app-r" : "app-w"], "y la página usa la que ganó")
}

@Test @MainActor func aRefusedSecondHostNeverCostsTheSurvivingKey() async throws {
    let setup = try makeSetup(working: true)
    setup.deployment.addHost(otherHost)
    setup.deployment.gateOnce(rotated)

    let attempt = Task { await setup.apps.configure(endpoint: otherEndpoint, key: rotated) }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: "https://fn3.vercel.app", key: working) == .busy)
    setup.deployment.release()
    #expect(await attempt.value == .saved)

    #expect(setup.apps.endpoint == otherEndpoint)
    #expect(setup.key(at: otherHost) == rotated, "la clave del host que quedó sigue ahí")
    #expect(setup.key(at: "fn3.vercel.app") == nil)
}

/// A load that was waiting on the old function when a new setup landed must
/// not paint the old function's answer over the new setup.
@Test @MainActor func aSetupThatLandsMidLoadDropsTheStaleAnswer() async throws {
    let setup = try makeSetup(working: true)
    setup.deployment.gateOnce(working)

    let stale = Task { await setup.apps.load() }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()
    await stale.value

    #expect(setup.apps.apps.isEmpty, "la respuesta de la configuración vieja se descarta")
    #expect(setup.apps.phase == .loading, "y no pinta nada: la carga que sigue al guardado decide")
    setup.deployment.revoke(working)
    await setup.apps.load()
    #expect(setup.apps.phase == .ready)
    #expect(setup.apps.apps.map(\.slug) == ["app-r"])
}

@Test @MainActor func aKeychainWriteFailureIsStillReportedAsOne() async throws {
    let setup = try makeSetup(working: true)
    setup.hostSecrets.failWrites = true

    let outcome = await setup.apps.configure(endpoint: workingEndpoint, key: rotated)

    #expect(outcome == .storageFailed)
    #expect(setup.storedEndpoint == workingEndpoint)
    #expect(setup.storedKey == working)

    let first = try makeSetup(working: false)
    first.hostSecrets.failWrites = true
    #expect(await first.apps.configure(endpoint: workingEndpoint, key: working) == .storageFailed)
    #expect(first.storedEndpoint == nil)
}

/// A panel open on the replaced function: its pending tools answer is
/// dropped, and the panel must not stay on a spinner nobody will clear.
@Test @MainActor func aSetupThatLandsMidActionsLeavesNoSpinner() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    let app = try #require(setup.apps.apps.first)
    setup.apps.open(app)
    setup.deployment.gateOnce(working, op: "tools")

    let stale = Task { await setup.apps.actions(of: app) }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(setup.apps.actionsPhase == .loading)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()
    await stale.value

    #expect(setup.apps.actionsPhase == .idle, "ni cargando para siempre ni con la lista vieja")
    #expect(setup.apps.selected == nil, "el panel era de la función reemplazada")
}

@Test @MainActor func aSetupThatLandsMidDisconnectIsDropped() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    let app = try #require(setup.apps.apps.first)
    setup.apps.open(app)
    setup.apps.confirmDisconnect()
    setup.deployment.gateOnce(working, op: "disconnect")

    let stale = Task { await setup.apps.disconnect() }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(setup.apps.disconnectPhase == .disconnecting)
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()
    await stale.value

    #expect(setup.apps.disconnectPhase == .idle, "sin spinner colgado")
    #expect(setup.apps.state(of: "app-w") == .connected, "las cuentas no se refrescaron con la función vieja")
    #expect(setup.notified.value == 0, "y no se avisó a la voz de un cambio que no fue")
}

@Test @MainActor func aSetupThatLandsMidMoreDropsTheStalePage() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    #expect(setup.apps.hasMore)
    setup.deployment.gateOnce(working)

    let stale = Task { await setup.apps.more() }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()
    await stale.value

    #expect(setup.apps.apps.map(\.slug) == ["app-w"], "la segunda página vieja no se anexa")
    #expect(setup.apps.hasMore, "y el cursor no se movió")
}

@Test @MainActor func aSetupThatLandsMidConnectDropsTheLink() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    let app = try #require(setup.apps.apps.first)
    setup.deployment.gateOnce(working, op: "connectLink")

    let link = Task { await setup.apps.connect(app.slug) }
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()

    #expect(await link.value == nil, "el enlace de la función vieja no se usa")
    #expect(setup.apps.connectError == nil)
}

@Test @MainActor func aSetupThatLandsMidConnectingClosesTheAttempt() async throws {
    let setup = try makeSetup(working: true)
    await setup.apps.load()
    let app = try #require(setup.apps.apps.first)
    setup.deployment.gateOnce(working, op: "connectLink")

    setup.apps.start(app)
    await waitUntil { setup.deployment.parked == 1 }
    #expect(await setup.apps.configure(endpoint: workingEndpoint, key: rotated) == .saved)
    setup.deployment.release()
    await waitUntil { false }

    #expect(setup.opened.value == 0, "no se abrió el navegador con el enlace viejo")
    #expect(setup.apps.connecting == nil)
    #expect(setup.apps.connectPhase == .initiating)
}
