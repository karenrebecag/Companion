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

@MainActor private final class Spoken {
    var lines: [String] = []
}

@MainActor private func controller(
    service: AnsweringApps = AnsweringApps(), hostSecrets: TestHostSecretStore = TestHostSecretStore(),
    spoken: Spoken
) -> (AppsSetupController, AppsModel) {
    let apps = AppsModel(
        secrets: TestSecretStore(), hostSecrets: hostSecrets,
        defaults: UserDefaults(suiteName: "apps-setup-controller-\(UUID().uuidString)")!,
        makeService: { _, _ in service })
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
}
