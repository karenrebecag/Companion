import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

/// Tests for silent voice session dropout fixes (FIX 1-5).
@Test @MainActor func voiceSilentDropoutTests() async {
    await testTransportEmitsErrorOnFailure()
    await testStreamEndUnexpectedlyStopsListening()
    await testReconnectOnceWithNetwork()
    await testReconnectFailureEndsSession()
    await testSilentDropoutOfflineNoReconnect()
    await testUnknownEventPreservesTypeName()
}

/// FIX 1: receiveFailed() should emit .serverError before finishing stream.
/// This is verified indirectly through FIX 2: when stream ends after error, VoiceSession
/// should receive the error event and transition to error state.
@MainActor func testTransportEmitsErrorOnFailure() async {
    let h = makeVoiceHarness(autoEvents: [.sessionCreated, .sessionUpdated])

    await h.session.start()
    await pumpUntil("FIX1: listening") { h.watch.latest.state == .listening }

    // Emit a server error that includes "session" to trigger failure handling
    h.transport.yield(.serverError("session timeout error"))
    await settle(0.05)

    // Session should transition to error state when session error arrives
    expect(h.watch.latest.state == .error,
           "FIX1: session should react to server error event")
}

/// FIX 2: pumpEvents() must detect stream end and leave listening state.
@MainActor func testStreamEndUnexpectedlyStopsListening() async {
    let h = makeVoiceHarness(
        autoEvents: [.sessionCreated, .sessionUpdated],
        online: false
    )

    await h.session.start()
    await pumpUntil("dropout: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    // Simulate abrupt stream termination without explicit transport.close()
    await h.transport.simulateStreamEnd()

    // Session should not remain in .listening after stream ends (offline → error, no reconnect)
    await pumpUntil("dropout: state changed", timeout: 1) {
        h.watch.latest.state != .listening
    }

    expect(h.watch.latest.state == .error,
           "FIX2: session should be in error state after stream ends mid-session (offline)")
}

/// FIX 3: Reconnect once with network, not infinitely.
@MainActor func testReconnectOnceWithNetwork() async {
    let h = makeVoiceHarness(
        autoEvents: [.sessionCreated, .sessionUpdated],
        online: true
    )

    await h.session.start()
    await pumpUntil("reconnect: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }

    let firstOpenCount = h.transport.openCount

    // Simulate transport failure (as if socket died mid-conversation)
    h.transport.yield(.speechStarted)
    await pumpUntil("reconnect: speech started") { h.watch.latest.speechOpen }

    // Kill transport
    await h.transport.simulateReceiveFailure()
    await settle(0.1)

    // With network available, transport should attempt reconnect ONCE
    await pumpUntil("reconnect: attempted reconnect", timeout: 1) {
        h.transport.openCount > firstOpenCount
    }

    // But no infinite loop: reconnect count should be exactly 1 more
    expect(h.transport.openCount == firstOpenCount + 1,
           "FIX3: reconnect should be attempted exactly once, not looping")
}

/// FIX 3 variant: Reconnect fails → session degrades to error.
@MainActor func testReconnectFailureEndsSession() async {
    let h = makeVoiceHarness(online: true)

    await h.session.start()
    await pumpUntil("reconnect-fail: listening") { h.watch.latest.state == .listening }

    // Make transport fail on reconnect
    h.transport.openError = .unreachable

    // Kill current connection
    await h.transport.simulateReceiveFailure()
    await settle(0.1)

    // Should attempt reconnect, fail, and degrade to error state
    await pumpUntil("reconnect-fail: error after failed reconnect", timeout: 1) {
        h.watch.latest.state == .error
    }

    expect(h.watch.latest.pipeline == nil,
           "FIX3: pipeline cleared after reconnect failure")
}

/// FIX 3 variant: No network → error without reconnect attempt.
@MainActor func testSilentDropoutOfflineNoReconnect() async {
    let h = makeVoiceHarness(
        autoEvents: [.sessionCreated, .sessionUpdated],
        online: false
    )

    await h.session.start()
    await pumpUntil("offline: listening") { h.watch.latest.state == .listening }

    let beforeDropout = h.transport.openCount

    // Kill transport while offline
    await h.transport.simulateReceiveFailure()
    await settle(0.1)

    // No reconnect should be attempted
    expect(h.transport.openCount == beforeDropout,
           "FIX3: no reconnect attempted when offline")

    // Should transition to error state
    await pumpUntil("offline: error") { h.watch.latest.state == .error }
}

/// FIX 5: Unknown event types should preserve the type name for observability.
@MainActor func testUnknownEventPreservesTypeName() async {
    let json = #"{"type":"hypothetical.future.event","data":"x"}"#

    let event = RealtimeCodec.parse(json)

    // Event should preserve type name in traceName for debugging
    let traceName = event.traceName
    expect(traceName.contains("hypothetical.future.event") ||
           traceName.contains("hypothetical"),
           "FIX5: traceName should contain the unknown type name, got: \(traceName)")
}

@Test @MainActor func sendSpamTests() async {
    await testDeadTransportStopsSending()
}

/// A dead socket used to log once per audio frame; the session must go quiet.
@MainActor func testDeadTransportStopsSending() async {
    let transport = FailingSendTransport()
    let runtime = RealtimeRuntime(
        transport: transport, player: SilentPlayer(), thread: SilentThread())
    for _ in 0 ..< 20 {
        await runtime.append(MicFrame(pcm16le24k: Data([1, 2, 3, 4]), rms: 0.2))
    }
    expectEq(transport.attempts, 1,
             "transporte caído: deja de intentar tras el primer fallo")
    runtime.reset()
    await runtime.append(MicFrame(pcm16le24k: Data([1, 2, 3, 4]), rms: 0.2))
    expectEq(transport.attempts, 2, "sesión nueva: vuelve a intentar")
}

private final class FailingSendTransport: VoiceTransport, @unchecked Sendable {
    private(set) var attempts = 0
    func events() -> AsyncStream<RealtimeEvent> { AsyncStream { $0.finish() } }
    func open(key: String, url: URL) async throws {}
    func send(_ json: String) async throws {
        attempts += 1
        throw VoiceTransportError.closed
    }
    func close() async {}
}

private final class SilentPlayer: PCMPlaying, @unchecked Sendable {
    func setVolume(_ volume: Double) async {}
    func start(sharedEngine: Bool) async throws {}
    func play(_ pcm16le24k: Data) async {}
    func flush() async {}
    func stop() async {}
    var hasPending: Bool { get async { false } }
    var drained: AsyncStream<Void> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<Double> { AsyncStream { $0.finish() } }
}

private final class SilentThread: ConversationPresenting, @unchecked Sendable {
    func historyTurns() async -> [Turn] { [] }
    func appendUser(_ text: String) async {}
    func appendAssistant(_ text: String) async {}
    func appendStatus(_ text: String) async {}
    func showStream(_ text: String) async {}
    func finishStream() async {}
}
