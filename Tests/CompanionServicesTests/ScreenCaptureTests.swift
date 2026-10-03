import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test func screenCaptureTests() async {
    await testCaptureSkipsWhenUntrusted()
    testVisionJSONReadsContent()
    await testCaptureWaitsForAVerifiedGrant()
    await testAFailedCaptureMakesTheGrantStale()
    await testAWorkingCaptureKeepsTheGrantVerified()
    await testAStaleGrantRecoversThroughTheNextCapture()
    await testAFailedCaptureLogsItsCause()
    await testANothingToShowLeavesTheGrantAlone()
}

func testAFailedCaptureLogsItsCause() async {
    let lines = CaptureLog()
    let capture = ScreenCapture(
        bundleID: "test", trusted: { true }, gate: nil,
        shoot: { .failed("The user declined TCCs") }, log: { lines.append($0) })
    expect(await capture.jpeg() == nil, "captura: falla")
    expectEq(lines.all, ["screen: capture failed (The user declined TCCs)"], "captura: la causa queda en el log")
}

func testANothingToShowLeavesTheGrantAlone() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    let lines = CaptureLog()
    let capture = ScreenCapture(
        bundleID: "test", trusted: { true }, gate: gate, shoot: { .skipped }, log: { lines.append($0) })
    expect(await capture.jpeg() == nil, "captura: nada que mostrar")
    expectEq(gate.status, .verified, "captura: una ventana sin contenido no es un permiso perdido")
    expectEq(fake.verifies, 1, "captura: no vuelve a sondear")
    expect(lines.all.isEmpty, "captura: no es una falla")
}

func testCaptureWaitsForAVerifiedGrant() async {
    let box = GrabBox()
    let gate = ScreenRecordingGate(checker: FakeScreenRecording(granted: true, captures: false))
    let capture = ScreenCapture(
        bundleID: "test", trusted: { true }, gate: gate,
        grab: {
            box.hit = true
            return Data([1])
        })
    expect(await capture.jpeg() == nil, "captura: preflight con el sondeo fallando no basta")
    expect(!box.hit, "captura: no intenta antes de verificar")
}

func testAFailedCaptureMakesTheGrantStale() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    fake.captures = false
    let capture = ScreenCapture(bundleID: "test", trusted: { true }, gate: gate, grab: { nil })
    expect(await capture.jpeg() == nil, "captura: falla")
    expect(await settles { gate.status == .stale }, "captura: la falla vuelve a verificar y la marca vieja")
    expect(await capture.jpeg() == nil, "captura: vieja no captura")
}

func testAStaleGrantRecoversThroughTheNextCapture() async {
    let fake = FakeScreenRecording(granted: true, captures: false)
    let clock = CaptureClock()
    let gate = ScreenRecordingGate(checker: fake, reprobeInterval: 30, now: { clock.now })
    let box = GrabBox()
    let capture = ScreenCapture(
        bundleID: "test", trusted: { true }, gate: gate,
        grab: {
            box.hit = true
            return Data([1])
        })
    expect(await capture.jpeg() == nil, "captura: el sondeo falla, no captura")
    expect(!box.hit, "captura: sin verificar no intenta")
    fake.captures = true
    expect(await capture.jpeg() == nil, "captura: dentro del intervalo no vuelve a sondear")
    expectEq(fake.verifies, 1, "captura: sondeo limitado")
    clock.advance(31)
    expectEq(await capture.jpeg(), Data([1]), "captura: pasado el intervalo sondea y vuelve sola")
    expectEq(gate.status, .verified, "captura: verificada otra vez")
}

func testAWorkingCaptureKeepsTheGrantVerified() async {
    let fake = FakeScreenRecording(granted: true, captures: true)
    let gate = ScreenRecordingGate(checker: fake)
    await gate.verify()
    let capture = ScreenCapture(bundleID: "test", trusted: { true }, gate: gate, grab: { Data([1]) })
    expectEq(await capture.jpeg(), Data([1]), "captura: verificada captura")
    expectEq(gate.status, .verified, "captura: sigue verificada")
    expectEq(fake.verifies, 1, "captura: una que funciona no vuelve a sondear")
}

func testCaptureSkipsWhenUntrusted() async {
    let box = GrabBox()
    let capture = ScreenCapture(
        bundleID: "test",
        trusted: { false },
        grab: {
            box.hit = true
            return Data([1])
        })
    let data = await capture.jpeg()
    expect(data == nil, "captura: sin permiso no hay JPEG")
    expect(!box.hit, "captura: ni siquiera intenta")
}

func testVisionJSONReadsContent() {
    let json = """
    {"choices":[{"message":{"content":"SUMMARY: a window\\nSNIPPETS:\\n[Safari] \\"Hi\\""}}]}
    """
    let text = ScreenVision.content(from: Data(json.utf8))
    expect(text?.contains("SUMMARY:") == true, "visión: lee el content")
    let brief = ScreenBriefParser.parse(text ?? "")
    expectEq(brief.summary, "a window", "visión: el parser sigue")
    expectEq(brief.snippets.first?.app, "Safari", "visión: snippet")
}

private final class GrabBox: @unchecked Sendable {
    var hit = false
}

private final class CaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// The re-probe after a failure runs off the caller's path on purpose.
private func settles(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

private final class CaptureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}
