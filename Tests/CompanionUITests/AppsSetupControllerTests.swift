import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import Foundation
import Testing

// The form's orchestration against a real AppsModel: what VoiceOver hears
// on each outcome, and that the key survives a failure and is dropped only
// once the function has answered.

private let goodEndpoint = "https://companion-apps.vercel.app"
private let goodKey = String(repeating: "k", count: 64)

private final class AnsweringApps: AppsService, @unchecked Sendable {
    let failure: AppsFailure?
    init(failing failure: AppsFailure? = nil) { self.failure = failure }
    func catalog(query: String, after: String?) async throws -> CatalogPage {
        if let failure { throw failure }
        return CatalogPage(apps: [], total: 0, next: nil)
    }
    func accounts() async throws -> [ConnectedAccount] { [] }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}

/// Holds the first catalog call until released, so a second save can arrive
/// while the model is still checking the first.
private final class ParkedApps: AppsService, @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var parkedCount = 0
    var parked: Int { lock.withLock { parkedCount } }
    func release() { lock.withLock { waiter }?.resume() }
    func catalog(query: String, after: String?) async throws -> CatalogPage {
        await withCheckedContinuation { continuation in
            lock.withLock { waiter = continuation; parkedCount += 1 }
        }
        return CatalogPage(apps: [], total: 0, next: nil)
    }
    func accounts() async throws -> [ConnectedAccount] { [] }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] { [] }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        throw AppsFailure.unexpected
    }
}

@MainActor private final class Spoken {
    var lines: [String] = []
}

@MainActor private func controller(
    service: AnsweringApps = AnsweringApps(), hostSecrets: TestHostSecretStore = TestHostSecretStore(),
    byKey: [String: any AppsService] = [:], spoken: Spoken
) -> (AppsSetupController, AppsModel) {
    let apps = AppsModel(
        secrets: TestSecretStore(), hostSecrets: hostSecrets,
        defaults: UserDefaults(suiteName: "apps-setup-controller-\(UUID().uuidString)")!,
        makeService: { _, key in byKey[key] ?? service })
    let made = AppsSetupController(apps: apps, endpoint: "", announce: { spoken.lines.append($0) })
    return (made, apps)
}

@Suite("apps setup controller") @MainActor struct AppsSetupControllerTests {
    @Test func anInvalidSubmitSaysTheFirstThingToFix() async {
        let spoken = Spoken()
        let (form, _) = controller(spoken: spoken)
        form.key = "short"
        await form.submit()
        #expect(spoken.lines == [AppsSetupCopy.issue(.endpointEmpty)])
        #expect(form.flow.phase == .editing)
    }

    @Test func aRefusedKeyComesBackToTheFormWithTheKeyKept() async {
        let spoken = Spoken()
        let (form, apps) = controller(service: AnsweringApps(failing: .unauthorized), spoken: spoken)
        form.endpoint = goodEndpoint
        form.key = goodKey
        await form.submit()
        #expect(apps.phase == .failed(.unauthorized), "the real configure + load ran")
        #expect(form.flow.phase == .failed(.server(.unauthorized)))
        #expect(spoken.lines == [AppsCopy.failure(.unauthorized)])
        #expect(form.key == goodKey, "the person fixes the key, they do not retype it")
        #expect(form.endpoint == goodEndpoint)
    }

    @Test func aKeychainThatRefusesTheWriteIsAStorageFailure() async {
        let spoken = Spoken()
        let store = TestHostSecretStore()
        store.failWrites = true
        let (form, _) = controller(hostSecrets: store, spoken: spoken)
        form.endpoint = goodEndpoint
        form.key = goodKey
        await form.submit()
        #expect(form.flow.phase == .failed(.storage), "configure returned false on values the rules accept")
        #expect(spoken.lines == [AppsSetupCopy.failure(.storage)])
        #expect(form.key == goodKey)
    }

    @Test func anAnsweringFunctionConfirmsAndDropsTheKey() async {
        let spoken = Spoken()
        let (form, apps) = controller(spoken: spoken)
        form.endpoint = goodEndpoint
        form.key = goodKey
        await form.submit()
        #expect(apps.phase == .ready)
        #expect(form.flow.phase == .confirmed)
        #expect(spoken.lines == [AppsSetupCopy.doneTitle])
        #expect(form.key.isEmpty, "the key leaves the view's state once it is stored and proven")
    }

    /// A typo in the address answers as unreachable; every refusal reaches
    /// the form as the function's own failure, not one generic line.
    @Test(arguments: [AppsFailure.unauthorized, .unreachable, .rateLimited, .notConfigured(["COMPANION_APP_KEY"])])
    func aRefusedReplacementKeepsTheWorkingSetupAndSaysWhy(_ failure: AppsFailure) async {
        let spoken = Spoken()
        let wrongKey = String(repeating: "w", count: 64)
        let (form, apps) = controller(byKey: [wrongKey: AnsweringApps(failing: failure)], spoken: spoken)
        #expect(await apps.configure(endpoint: goodEndpoint, key: goodKey) == .saved)
        form.endpoint = goodEndpoint
        form.key = wrongKey
        await form.submit()
        #expect(form.flow.phase == .failed(.server(failure)), "the function refused the new pair")
        #expect(spoken.lines == [AppsCopy.failure(failure)])
        #expect(form.key == wrongKey, "the person fixes the key, they do not retype it")
        await apps.load()
        #expect(apps.phase == .ready, "the working setup still answers")
    }

    @Test func aKeychainThatRefusesAReplacementKeepsTheWorkingKey() async throws {
        let spoken = Spoken()
        let store = TestHostSecretStore()
        let nextKey = String(repeating: "n", count: 64)
        let (form, apps) = controller(hostSecrets: store, spoken: spoken)
        #expect(await apps.configure(endpoint: goodEndpoint, key: goodKey) == .saved)
        store.failWrites = true
        form.endpoint = goodEndpoint
        form.key = nextKey
        await form.submit()
        #expect(form.flow.phase == .failed(.storage), "checked and accepted, then the Keychain refused")
        #expect(spoken.lines == [AppsSetupCopy.failure(.storage)])
        #expect(form.key == nextKey)
        #expect(try store.read(.appsKey, host: "companion-apps.vercel.app") == goodKey)
    }

    @Test func aSaveWhileAnotherCheckRunsLeavesTheFormEditable() async throws {
        let spoken = Spoken()
        let parked = ParkedApps()
        let hostSecrets = TestHostSecretStore()
        let firstKey = String(repeating: "a", count: 64)
        let secondKey = String(repeating: "b", count: 64)
        let (form, apps) = controller(hostSecrets: hostSecrets, byKey: [firstKey: parked], spoken: spoken)
        #expect(await apps.configure(endpoint: goodEndpoint, key: goodKey) == .saved)
        let first = Task { await apps.configure(endpoint: goodEndpoint, key: firstKey) }
        // Bounded, so a check that never reaches the probe fails here
        // instead of hanging the suite.
        let deadline = ContinuousClock.now + .seconds(2)
        while parked.parked == 0, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(parked.parked == 1, "the first check is parked in the probe")
        form.endpoint = goodEndpoint
        form.key = secondKey
        await form.submit()
        #expect(form.flow.phase == .editing, "refused, not saving forever: the form stays usable")
        #expect(!form.flow.isReadOnly)
        #expect(spoken.lines.isEmpty, "the check already running will answer")
        #expect(form.key == secondKey)
        parked.release()
        #expect(await first.value == .saved, "the refused submit did not disturb the running check")
        #expect(try hostSecrets.read(.appsKey, host: "companion-apps.vercel.app") == firstKey)
    }
}
