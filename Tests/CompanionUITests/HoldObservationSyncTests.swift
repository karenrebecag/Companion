import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Code and security review (b2a): the observer follows the session's hold itself, whatever
// started or ended it (the key, the island pointer, a stop, an error), never key events.

@MainActor private final class SpyObserver: HoldObserving {
    private(set) var calls: [String] = []
    func start(generation: Int, onBatch: @escaping @Sendable (HoldObservationBatch) -> Void) async {
        calls.append("start(\(generation))")
    }

    func stop() async { calls.append("stop") }
}

@MainActor private func sync(_ spy: SpyObserver) -> HoldObservationSync {
    HoldObservationSync(observer: spy, companion: HoldCompanionModel(), words: { 0 })
}

@Test @MainActor func eachHoldStartsItsOwnGenerationAndItsEndStopsIt() async {
    let spy = SpyObserver()
    let holds = sync(spy)
    holds.update(holding: true)
    holds.update(holding: false)
    holds.update(holding: true)
    await holds.settled()
    expectEq(spy.calls, ["start(1)", "stop", "start(2)"], "en orden, aunque el soltar sea inmediato")
}

@Test @MainActor func theSameHoldStateTwiceDoesNothing() async {
    let spy = SpyObserver()
    let holds = sync(spy)
    holds.update(holding: false)
    holds.update(holding: true)
    holds.update(holding: true)
    await holds.settled()
    expectEq(spy.calls, ["start(1)"], "sin flanco no hay llamada")
}

@Test @MainActor func aStopWithNoKeyEventEndsTheObservation() async {
    let spy = SpyObserver()
    let holds = sync(spy)
    let session = SessionModel(jobs: nil, approvals: nil)
    let following = holds.follow(session)
    session.send(.pressed)
    await waitFor { spy.calls == ["start(1)"] }
    session.send(.stop)
    await waitFor { spy.calls == ["start(1)", "stop"] }
    expectEq(spy.calls, ["start(1)", "stop"], "parar desde cualquier lado termina la observacion")
    following.cancel()
}

@Test @MainActor func theTranscriptIsCountedInWords() {
    expectEq(HoldObservationSync.words(in: nil), 0, "sin transcripcion, cero")
    expectEq(HoldObservationSync.words(in: ""), 0, "vacia, cero")
    expectEq(HoldObservationSync.words(in: "  manda \n esto   ya "), 3, "espacios y saltos no son palabras")
}

@MainActor private func waitFor(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 where !condition() {
        do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
    }
}
