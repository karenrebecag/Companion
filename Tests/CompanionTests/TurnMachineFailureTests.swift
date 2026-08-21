import CompanionCore
import Foundation
import Testing

@Test @MainActor func turnMachineFailureTests() {
    testTurnMachineFailureTracking()
    testTurnMachineFailureClearedOnStart()
    testTurnMachineFailureClearedOnListening()
}

@discardableResult
private func apply(
    _ machine: inout TurnMachine, _ event: TurnEvent, at now: TimeInterval = 0
) -> [TurnEffect] {
    machine.handle(event, at: now)
}

@MainActor func testTurnMachineFailureTracking() {
    var m = TurnMachine()

    // When voiceStartFailed with micDenied, snapshot should capture the failure reason.
    let effects = apply(&m, .voiceStartFailed(.micDenied))
    expectEq(m.snapshot.state, .error, "fail: should be in error state")
    expectEq(m.snapshot.failure, .micDenied,
             "fail: snapshot should capture micDenied failure")
    expect(effects.contains { if case .noteFailure(.micDenied) = $0 { return true }; return false },
           "fail: effects should include noteFailure with reason")

    // When micUnavailable fails.
    m = TurnMachine()
    _ = apply(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.failure, .micUnavailable,
             "fail: snapshot should capture micUnavailable")

    // When sessionDropped fails.
    m = TurnMachine()
    _ = apply(&m, .voiceStartFailed(.sessionDropped))
    expectEq(m.snapshot.failure, .sessionDropped,
             "fail: snapshot should capture sessionDropped")

    // When in conversation and fails, should recover to listening (not pure error).
    m = TurnMachine(snapshot: TurnSnapshot(state: .listening, pipeline: .classic, inConversation: true))
    _ = apply(&m, .voiceStartFailed(.speechEngine))
    expectEq(m.snapshot.state, .listening, "recover: should go to listening in conversation")
    expectEq(m.snapshot.failure, .speechEngine,
             "recover: should still capture speechEngine failure")
    expectEq(m.snapshot.pipeline, .classic, "recover: should stay on classic")
}

@MainActor func testTurnMachineFailureClearedOnStart() {
    // When in error with a failure, starting a new voice session should clear the failure.
    var m = TurnMachine(snapshot: TurnSnapshot(state: .error, failure: .micDenied))
    _ = apply(&m, .startVoice(preferRealtime: true))
    expectEq(m.snapshot.state, .connecting, "clear: should move to connecting")
    expectEq(m.snapshot.failure, nil,
             "clear: failure should be cleared on new startVoice")
}

@MainActor func testTurnMachineFailureClearedOnListening() {
    // When recovered to listening, the failure should be cleared when listener is armed.
    var m = TurnMachine(snapshot: TurnSnapshot(state: .listening, pipeline: .classic, inConversation: true, failure: .speechEngine))
    _ = apply(&m, .classicListenArmed)
    expectEq(m.snapshot.state, .listening, "armed: should stay listening")
    expectEq(m.snapshot.failure, nil,
             "armed: failure should be cleared when listener is armed")
}
