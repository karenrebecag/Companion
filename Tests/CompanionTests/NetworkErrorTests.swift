import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func networkErrorTests() {
    testNetworkUnavailableFailure()
    testNetworkErrorMessage()
}

@discardableResult
private func apply(
    _ machine: inout TurnMachine, _ event: TurnEvent, at now: TimeInterval = 0
) -> [TurnEffect] {
    machine.handle(event, at: now)
}

@MainActor func testNetworkUnavailableFailure() {
    // When a network error occurs (e.g., no internet), the failure reason should be captured.
    var m = TurnMachine()
    _ = apply(&m, .voiceStartFailed(.networkUnavailable))

    expectEq(m.snapshot.state, .error,
             "network: should enter error state")
    expectEq(m.snapshot.failure, .networkUnavailable,
             "network: snapshot should capture networkUnavailable failure")

    // When in conversation and network fails, should recover to listening.
    m = TurnMachine(snapshot: TurnSnapshot(state: .listening, pipeline: .classic, inConversation: true))
    _ = apply(&m, .voiceStartFailed(.networkUnavailable))

    expectEq(m.snapshot.state, .listening,
             "network: should recover to listening in conversation")
    expectEq(m.snapshot.failure, .networkUnavailable,
             "network: should capture failure reason in recovery")
}

@MainActor func testNetworkErrorMessage() {
    // Verify that the error message for network unavailability is clear.
    let message = VoiceCopy.failure(.networkUnavailable)
    expect(message.lowercased().contains("conexión") || message.lowercased().contains("internet"),
           "network: message should mention connection or internet")
    expect(!message.lowercased().contains("técnico") && !message.lowercased().contains("error #"),
           "network: message should be user-friendly, not technical")
}
