import CompanionCore
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Gap 1: Screen Recording counts only once a real capture worked, falls back
// when one fails, recovers when it works again, and never asks on its own.

@Test func screenRecordingGateStartsFromPreflightWithoutProbing() {
    let granted = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: granted)
    expectEq(gate.status, .grantedUnverified, "preflight alone is not proof")
    expect(!gate.sightReady, "no sight before a real capture worked")
    expectEq(granted.verifies, 0, "building the gate does not probe")

    let refused = FakeScreenRecording(granted: false, captures: false)
    expectEq(ScreenRecordingGate(checker: refused).status, .notGranted, "no grant, no sight")
}

@Test func screenRecordingGateVerifiesWithARealCapture() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    expectEq(await gate.verify(), .verified, "a capture that works verifies")
    expect(gate.sightReady, "verified enables sight")

    let broken = FakeScreenRecording(granted: true, captures: false)
    let stuck = ScreenRecordingGate(checker: broken)
    expectEq(await stuck.verify(), .grantedUnverified, "granted but the capture fails")
    expect(!stuck.sightReady, "a switch that is on but captures nothing is a dead end")
}

@Test func screenRecordingGateNeverProbesWithoutTheGrant() async {
    let fake = FakeScreenRecording(granted: false, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    expectEq(await gate.verify(), .notGranted, "not granted stays not granted")
    expectEq(fake.verifies, 0, "without the grant the probe could raise the system prompt")
}

@Test func screenRecordingGateGoesStaleWhenACaptureFails() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let lines = LogLines()
    let gate = ScreenRecordingGate(checker: fake, log: { lines.append($0) })
    await gate.verify()
    fake.captures = false
    expectEq(await gate.captureFailed(), .stale, "lost after it worked")
    expect(!gate.sightReady, "stale disables sight")
    expectEq(fake.verifies, 2, "a failed capture re-verifies")
    expect(lines.all.contains { $0.contains("verified -> stale") }, "the transition is logged: \(lines.all)")
    let logged = lines.all.count
    await gate.captureFailed()
    expectEq(lines.all.count, logged, "staying stale logs nothing new")
    fake.granted = false
    await gate.verify()
    expect(lines.all.last?.contains("stale -> notGranted") == true, "a revoke is logged: \(lines.all)")
}

@Test func screenRecordingGateRecoversWhenTheCaptureWorksAgain() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    fake.captures = false
    await gate.captureFailed()
    fake.captures = true
    expectEq(await gate.verify(), .verified, "stale recovers on the next verify")
    expect(gate.sightReady, "sight is back")
}

@Test func screenRecordingGateKeepsSightAfterAFailureThatWasNotPermission() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    expectEq(await gate.captureFailed(), .verified, "the probe still works: not a lost grant")
}

@Test func screenRecordingGateReadsARevokeAsNotGranted() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    fake.granted = false
    fake.captures = false
    expectEq(await gate.captureFailed(), .notGranted, "revoked in Settings")
}

@Test func screenRecordingGateTakesACaptureThatWorkedAsProof() {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    gate.captureSucceeded()
    expectEq(gate.status, .verified, "a real capture is the proof")
}

@Test func screenRecordingGateNeverRequests() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    fake.captures = false
    await gate.captureFailed()
    fake.granted = false
    await gate.verify()
    await gate.captureFailed()
    gate.captureSucceeded()
    expectEq(fake.requests, 0, "only the user's tap asks; the gate never does")
}

private final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

@Test func screenRecordingGateReprobesOnlyWhenDue() async {
    let fake = FakeScreenRecording(granted: true, captures: false)
    let clock = TestClock()
    let gate = ScreenRecordingGate(checker: fake, reprobeInterval: 30, now: { clock.now })
    expectEq(await gate.reprobeIfDue(), .grantedUnverified, "first ask probes")
    expectEq(fake.verifies, 1, "one probe")
    fake.captures = true
    clock.advance(10)
    expectEq(await gate.reprobeIfDue(), .grantedUnverified, "inside the interval: no probe")
    expectEq(fake.verifies, 1, "throttled")
    clock.advance(25)
    expectEq(await gate.reprobeIfDue(), .verified, "past the interval: probes and recovers")
    expectEq(await gate.reprobeIfDue(), .verified, "verified needs no probe")
    expectEq(fake.verifies, 2, "no probe once verified")
    expectEq(fake.requests, 0, "the re-probe never asks")
}

@Test func screenRecordingGateDropsAProbeOvertakenByANewerResult() async {
    let slow = SlowScreenRecording()
    let gate = ScreenRecordingGate(checker: slow)
    let probe = Task { await gate.verify() }
    await slow.waitUntilProbing()
    gate.captureSucceeded()
    slow.finish(captured: false)
    _ = await probe.value
    expectEq(gate.status, .verified, "a capture that worked after the probe began is newer proof")
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// A probe the test holds open, to land another result while it runs.
private final class SlowScreenRecording: ScreenRecordingChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CheckedContinuation<Bool, Never>?

    func isGranted() -> Bool { true }
    func request() -> Bool { true }

    func verify() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.withLock { pending = continuation }
        }
    }

    func waitUntilProbing() async {
        while lock.withLock({ pending == nil }) { await Task.yield() }
    }

    func finish(captured: Bool) {
        let continuation = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            defer { pending = nil }
            return pending
        }
        continuation?.resume(returning: captured)
    }
}

@Test func screenRecordingGateSignalsALossOncePerLoss() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let losses = LossCount()
    let gate = ScreenRecordingGate(checker: fake)
    gate.onLost { losses.add() }
    await gate.verify()
    fake.captures = false
    await gate.captureFailed()
    expectEq(losses.count, 1, "verified -> stale is a loss")
    await gate.captureFailed()
    expectEq(losses.count, 1, "staying stale is the same loss")
    fake.captures = true
    await gate.verify()
    fake.granted = false
    await gate.captureFailed()
    expectEq(losses.count, 2, "recovered, then revoked: a new loss")

    let never = LossCount()
    let fresh = ScreenRecordingGate(checker: FakeScreenRecording(granted: true, captures: false))
    fresh.onLost { never.add() }
    await fresh.verify()
    expectEq(never.count, 0, "never worked is not a loss: the welcome owns that")
}

private final class LossCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func add() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}
