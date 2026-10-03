import CompanionCore
import CompanionTestKit
import Foundation
import Testing

/// Every refusal is one line that tells the agent what to do next.
@Test func bridgeMessagesNameTheNextAction() {
    let expected: [(String, String)] = [
        (BridgeMessages.rateLimited(waitSeconds: 50), "then retry"),
        (BridgeMessages.coolingDown(waitSeconds: 400), "before asking again"),
        (BridgeMessages.sheetLimit(waitSeconds: 400), "before asking again"),
        (BridgeMessages.paused, "then retry"),
        (BridgeMessages.sheetOpen, "then retry"),
        (BridgeMessages.anotherAgent, "then send hello again"),
        (BridgeMessages.needsAccessibility, "then retry"),
        (BridgeMessages.screenRecordingRequired, "then retry"),
        (BridgeMessages.screenLocked, "then call look before retrying"),
        (BridgeMessages.lockedDuringAction, "outcome is unknown"),
        (BridgeMessages.selfInFront, "to the front"),
        (BridgeMessages.foregroundUnavailable, "call look before retrying"),
    ]
    for (message, nextStep) in expected {
        expect(!message.contains("\n"), "one line: \(message)")
        expect(message.contains(nextStep), "names what to do next: \(message)")
    }
    expect(BridgeMessages.rateLimited(waitSeconds: 50).contains("50 s"), "says how long to wait")
    expect(BridgeMessages.coolingDown(waitSeconds: 400).contains("7 min"), "minutes past one minute")
    expect(!BridgeMessages.sheetLimit(waitSeconds: 400).contains("turned down"),
           "the sheet limit counts sheets, not denials")
    expect(BridgeMessages.needsAccessibility.contains("Privacy & Security > Accessibility"),
           "names where the switch is")
}

@Test func bridgeMessageDurations() {
    let cases: [(Int, String)] = [(-5, "1 s"), (0, "1 s"), (1, "1 s"), (59, "59 s"), (60, "1 min"),
                                  (61, "2 min"), (400, "7 min")]
    for (seconds, text) in cases {
        expect(BridgeMessages.rateLimited(waitSeconds: seconds).contains("Wait \(text),"),
               "\(seconds) s reads as \(text)")
    }
}
