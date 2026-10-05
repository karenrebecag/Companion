import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// The popover is owned by the view; the reducer only knows what it is told.
// This is the one function every open and close goes through.

@Test @MainActor func k1R4TheAnswerSignalHoldsAndReleasesTheSettle() {
    let session = SessionModel(jobs: nil, approvals: nil)
    session.send(.typedSubmitted)
    IslandAnswerSignal.changed(from: nil, to: UUID(), session: session)
    let held = session.send(.typedReplyFinished)
    expect(!held.contains(.scheduleCompletedExpiry(
        SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: con la respuesta abierta el asentamiento no se arma")
    let released = IslandAnswerSignal.changed(from: UUID(), to: nil, session: session)
    expect(released.contains(.scheduleCompletedExpiry(
        SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: cerrarla, también por el descanso de la isla, arma el asentamiento")
}

@Test @MainActor func k1R4AnUnchangedAnswerSendsNothing() {
    let session = SessionModel(jobs: nil, approvals: nil)
    session.send(.typedSubmitted)
    session.send(.typedReplyFinished)
    expectEq(IslandAnswerSignal.changed(from: nil, to: nil, session: session), [],
             "K1: sin respuesta abierta antes ni después no hay evento")
}

@Test @MainActor func k1R5AnAnswerWhoseMessageVanishedIsClosed() {
    let session = SessionModel(jobs: nil, approvals: nil)
    session.send(.typedSubmitted)
    let id = UUID()
    IslandAnswerSignal.changed(from: nil, to: id, session: session)
    session.send(.typedReplyFinished)
    let kept = IslandAnswerSignal.reconcile(open: id, messageExists: true, session: session)
    expectEq(kept.open, id, "K1: con su mensaje la respuesta sigue abierta")
    expectEq(kept.effects, [], "K1: y no se avisa nada")
    let gone = IslandAnswerSignal.reconcile(open: id, messageExists: false, session: session)
    expectEq(gone.open, nil, "K1: sin su mensaje la respuesta se cierra")
    expect(gone.effects.contains(.scheduleCompletedExpiry(
        SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: y el asentamiento se libera")
}
