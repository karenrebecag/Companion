import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func micCaptureWatchdogTests() {
    testWatchdogNoBuffersVetosVoiceProcessing()
    testWatchdogWithBufferNoVeto()
    testWatchdogRetryLimitedToOnce()
    testWatchdogIgnoresStoppedOrPlainMic()
}

@MainActor func testWatchdogNoBuffersVetosVoiceProcessing() {
    let action = MicWatchdog.decide(
        running: true, voiceProcessing: true,
        receivedBuffer: false, alreadyRetried: false)
    expectEq(action, .vetoAndRetry, "watchdog: sin buffers ⇒ veta VP y reintenta")
}

@MainActor func testWatchdogWithBufferNoVeto() {
    let action = MicWatchdog.decide(
        running: true, voiceProcessing: true,
        receivedBuffer: true, alreadyRetried: false)
    expectEq(action, .none, "watchdog: llegó audio ⇒ no toca nada")
}

@MainActor func testWatchdogRetryLimitedToOnce() {
    let action = MicWatchdog.decide(
        running: true, voiceProcessing: true,
        receivedBuffer: false, alreadyRetried: true)
    expectEq(action, .none, "watchdog: ya reintentó ⇒ no hay segundo intento")
}

@MainActor func testWatchdogIgnoresStoppedOrPlainMic() {
    expectEq(
        MicWatchdog.decide(
            running: false, voiceProcessing: true,
            receivedBuffer: false, alreadyRetried: false),
        .none,
        "watchdog: mic detenido ⇒ no reinicia")
    expectEq(
        MicWatchdog.decide(
            running: true, voiceProcessing: false,
            receivedBuffer: false, alreadyRetried: false),
        .none,
        "watchdog: sin VP no hay nada que vetar")
}
