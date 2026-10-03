import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// P1: Incredible's `passive_after_secs`, stored like the other hold preferences.

@Test @MainActor func thePassiveWaitIsTenMinutesUntilTheUserChangesIt() {
    let suite = "passive-preference-tests"
    let store = UserDefaults(suiteName: suite)!
    store.removePersistentDomain(forName: suite)
    expectEq(PassivePreference.seconds(in: store), SessionMachine.defaultPassiveAfter, "600 por defecto")
    PassivePreference.set(0, in: store)
    expectEq(PassivePreference.seconds(in: store), 0, "0 es nunca y se respeta")
    PassivePreference.set(90, in: store)
    expectEq(PassivePreference.seconds(in: store), 90, "lo que eligio")
    store.removePersistentDomain(forName: suite)
}

// A value written by hand or by an older build must never make the wait negative or endless.
@Test @MainActor func aBrokenStoredWaitFallsBackToTheDefault() {
    let suite = "passive-preference-broken-tests"
    let store = UserDefaults(suiteName: suite)!
    store.removePersistentDomain(forName: suite)
    for broken: Any in [-5.0, Double.infinity, Double.nan, "diez"] {
        store.set(broken, forKey: PassivePreference.key)
        expectEq(PassivePreference.seconds(in: store), SessionMachine.defaultPassiveAfter, "\(broken): por defecto")
    }
    store.removePersistentDomain(forName: suite)
}

/// Each sleep the model asks for waits here until the test lets it go.
private actor Sleeps {
    private(set) var requested: [TimeInterval] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ delay: TimeInterval) async {
        requested.append(delay)
        await withCheckedContinuation { waiting.append($0) }
    }

    func release(_ index: Int) {
        waiting[index].resume()
    }

    func count() -> Int { requested.count }
}

@MainActor private func eventually(_ done: () async -> Bool) async {
    for _ in 0..<400 where !(await done()) {
        do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
    }
}

// QA review (P1): the model really runs the wait the reducer arms, and a replaced
// wait that finishes late changes nothing.
@Test @MainActor func theModelRunsTheWaitAndAReplacedOneDoesNothing() async {
    let sleeps = Sleeps()
    let model = SessionModel(jobs: nil, approvals: nil, sleep: { await sleeps.sleep($0) })
    model.send(.passiveAfterChanged(600))
    await eventually { await sleeps.count() == 1 }
    expectEq(await sleeps.requested, [600], "pide esperar lo que armo el reductor")
    // Hover arms no other clock (a tap also starts the hold hint's), so the second
    // sleep is the new wait.
    model.send(.hoverEntered)
    await eventually { await sleeps.count() == 2 }
    expectEq(await sleeps.requested, [600, 600], "la interaccion pide una espera nueva")
    await sleeps.release(0)
    do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
    expectEq(model.projection.presence, .active, "la espera reemplazada termina y no cuenta")
    await sleeps.release(1)
    await eventually { model.projection.presence == .passive }
    expectEq(model.projection.presence, .passive, "la vigente si")
}

// QA review (P1): what the app does at launch, so removing it is a red test.
@Test @MainActor func armingAtLaunchUsesTheStoredWait() async {
    let suite = "passive-preference-arm-tests"
    let store = UserDefaults(suiteName: suite)!
    store.removePersistentDomain(forName: suite)
    PassivePreference.set(90, in: store)
    let sleeps = Sleeps()
    let model = SessionModel(jobs: nil, approvals: nil, sleep: { await sleeps.sleep($0) })
    model.armPresence(store: store)
    await eventually { await sleeps.count() == 1 }
    expectEq(await sleeps.requested, [90], "arranca con la espera guardada")
    store.removePersistentDomain(forName: suite)
}
