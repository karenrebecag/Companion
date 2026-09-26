import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15g-5 (spec §3b). Vision never holds the brain unless the order
// points at the screen; when it lands late it rides the next turn instead
// of being thrown away. And the timeline says how long the context took,
// apart from the model.

@Test @MainActor func sightCarryTests() async {
    await testALateVisionRidesTheNextTurn()
    await testACarriedVisionIsUsedOnce()
    await testFinishHonoursItsWait()
    await testAPendingVisionReachesTheNextTurnsContext()
    await testTheTimelineLineCarriesCommitToContext()
    await testACarriedVisionIsMarkedStale()
    await testADifferentAppNeverGetsTheOldCarry()
    await testACarryOlderThan30sIsDropped()
}

@MainActor private func slowSight(
    summary: String, hang: UInt64, ax: [String] = []
) -> ScreenSight {
    let transport = ScriptedTransport()
    transport.stub(
        url: ProviderDescriptor.openAI.endpoint!.absoluteString,
        ScriptedReply(
            status: 200,
            body: Data("""
            {"choices":[{"message":{"content":"SUMMARY: \(summary)\\nSNIPPETS:\\n[Safari] \\"\(summary)\\""}}]}
            """.utf8),
            hangNanoseconds: hang))
    return ScreenSight(
        capture: ScreenCapture(bundleID: "test", trusted: { true }, grab: { Data([0xFF, 0xD8]) }),
        vision: ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport),
        axHarvest: { _ in ax },
        pid: { 4242 },
        appName: { "Safari" })
}

/// Turn N does not wait and gets `pending`; its vision finishes after the
/// turn; turn N+1's vision is late again, yet N's summary is in its brief.
@MainActor func testALateVisionRidesTheNextTurn() async {
    let sight = slowSight(summary: "a Safari window", hang: 150_000_000)
    sight.begin(app: "Safari")
    let first = await sight.finish(wait: .zero)
    expect(first.pending, "15g-5: turno N sin esperar queda pending")
    await settle(0.4)
    sight.begin(app: "Safari")
    let second = await sight.finish(wait: .zero)
    expectEq(second.summary, "a Safari window",
             "15g-5: la visión tardía del turno N entra en el turno N+1")
    expect(!second.pending, "15g-5: con un resumen en mano el bloque lo muestra, no pending")
}

/// A carried summary describes an older screen: one turn, then gone. And
/// the AX text read now beats the old vision's snippets.
@MainActor func testACarriedVisionIsUsedOnce() async {
    let transport = ScriptedTransport()
    let url = ProviderDescriptor.openAI.endpoint!.absoluteString
    func reply(_ summary: String, hang: UInt64) -> ScriptedReply {
        ScriptedReply(
            status: 200,
            body: Data("""
            {"choices":[{"message":{"content":"SUMMARY: \(summary)\\nSNIPPETS:\\n[Safari] \\"\(summary)\\""}}]}
            """.utf8),
            hangNanoseconds: hang)
    }
    transport.stub(url: url, reply("old screen", hang: 150_000_000))
    let sight = ScreenSight(
        capture: ScreenCapture(bundleID: "test", trusted: { true }, grab: { Data([0xFF, 0xD8]) }),
        vision: ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport),
        axHarvest: { _ in ["fresh AX line"] },
        pid: { 4242 },
        appName: { "Safari" })
    sight.begin(app: "Safari")
    _ = await sight.finish(wait: .zero)
    await settle(0.4)
    transport.stub(url: url, reply("never lands", hang: 5_000_000_000))
    sight.begin(app: "Safari")
    let second = await sight.finish(wait: .zero)
    expectEq(second.summary, "old screen", "15g-5: el turno N+1 lleva la visión del N")
    expectEq(second.snippets.first?.text, "fresh AX line",
             "15g-5: el texto AX de ahora gana a los snippets viejos")
    sight.begin(app: "Safari")
    let third = await sight.finish(wait: .zero)
    expect(third.summary == nil, "15g-5: un resumen viejo se usa una sola vez")
    expect(third.pending, "15g-5: sin nada en mano, sigue pending")
    sight.cancel()
}

/// The old race was a task group whose child only awaited `task.value`:
/// the group waited for vision whatever `wait` said, so "no wait" still
/// paid the whole vision call.
@MainActor func testFinishHonoursItsWait() async {
    let sight = slowSight(summary: "slow", hang: 2_000_000_000)
    sight.begin(app: "Safari")
    let start = Date()
    let brief = await sight.finish(wait: .milliseconds(50))
    let elapsed = Date().timeIntervalSince(start)
    expect(brief.pending, "15g-5: la visión lenta queda pending")
    expect(elapsed < 1, "15g-5: finish vuelve en su espera, no en la de la visión (\(elapsed) s)")
    sight.cancel()
}

/// Through the runtime: turn N sends `pending`, turn N+1's request
/// carries N's summary inside its `<context>` block.
@MainActor func testAPendingVisionReachesTheNextTurnsContext() async {
    let sight = slowSight(summary: "a Safari window", hang: 150_000_000)
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let chat = ScriptedChat()
    chat.deltas = [.text("Listo.")]
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat,
        thread: ScriptedThread())
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice))
    runtime.screen = sight

    sight.begin(app: "Safari")
    await runtime.submit(config: Config(language: .en)) { _ in }
    await settle(0.4)
    sight.begin(app: "Safari")
    await runtime.submit(config: Config(language: .en)) { _ in }
    sight.cancel()

    let first = chat.histories.first?.last?.content ?? ""
    let second = chat.histories.last?.last?.content ?? ""
    expect(first.contains("pending=\"true\"") && !first.contains("a Safari window"),
           "15g-5: el turno N no espera la visión y va pending")
    expect(second.contains("<screen_summary stale=\"true\">a Safari window</screen_summary>"),
           "15g-5/M2: el contexto del turno N+1 lleva la visión tardía del N, marcada stale")
}

/// HIGH-2/M2 (security+code review, 2026-09-25): a carried summary must say
/// it is old, not read like a fresh one.
@MainActor func testACarriedVisionIsMarkedStale() async {
    let sight = slowSight(summary: "a Safari window", hang: 150_000_000)
    sight.begin(app: "Safari")
    _ = await sight.finish(wait: .zero)
    await settle(0.4)
    sight.begin(app: "Safari")
    let second = await sight.finish(wait: .zero)
    expect(second.stale, "HIGH-2: un resumen heredado del turno anterior se marca stale")
    sight.cancel()
}

/// M2: the app changed under the carried summary — it must never leak into
/// a turn about a different app.
@MainActor func testADifferentAppNeverGetsTheOldCarry() async {
    final class MutablePid: @unchecked Sendable {
        var value: pid_t = 4242
    }
    let currentPid = MutablePid()
    let transport = ScriptedTransport()
    let url = ProviderDescriptor.openAI.endpoint!.absoluteString
    transport.stub(
        url: url,
        ScriptedReply(
            status: 200,
            body: Data("""
            {"choices":[{"message":{"content":"SUMMARY: old screen\\nSNIPPETS:\\n[Safari] \\"old screen\\""}}]}
            """.utf8),
            hangNanoseconds: 150_000_000))
    let sight = ScreenSight(
        capture: ScreenCapture(bundleID: "test", trusted: { true }, grab: { Data([0xFF, 0xD8]) }),
        vision: ScreenVision(secrets: TestSecretStore([.openAI: "sk-test"]), transport: transport),
        axHarvest: { _ in [] },
        pid: { currentPid.value },
        appName: { "Safari" })
    sight.begin(app: "Safari")
    _ = await sight.finish(wait: .zero)
    await settle(0.4)
    currentPid.value = 9999
    transport.stub(
        url: url,
        ScriptedReply(
            status: 200,
            body: Data(#"{"choices":[{"message":{"content":"SUMMARY: never lands\nSNIPPETS:\n"}}]}"#.utf8),
            hangNanoseconds: 5_000_000_000))
    sight.begin(app: "Mail")
    let second = await sight.finish(wait: .zero)
    expect(second.summary == nil, "M2: la visión vieja de otra app no se hereda a esta")
    expect(second.pending, "M2: sin resumen propio queda pending")
    sight.cancel()
}

/// M2: a carry older than 30 s is stale beyond use, not just beyond trust.
@MainActor func testACarryOlderThan30sIsDropped() async {
    final class MutableClock: @unchecked Sendable {
        var value = Date(timeIntervalSince1970: 1_700_000_000)
    }
    let clock = MutableClock()
    let sight = ScreenSight(
        capture: ScreenCapture(bundleID: "test", trusted: { true }, grab: { Data([0xFF, 0xD8]) }),
        vision: ScreenVision(
            secrets: TestSecretStore([.openAI: "sk-test"]),
            transport: {
                let transport = ScriptedTransport()
                transport.stub(
                    url: ProviderDescriptor.openAI.endpoint!.absoluteString,
                    ScriptedReply(
                        status: 200,
                        body: Data("""
                        {"choices":[{"message":{"content":"SUMMARY: old screen\\nSNIPPETS:\\n"}}]}
                        """.utf8),
                        hangNanoseconds: 150_000_000))
                return transport
            }()),
        axHarvest: { _ in [] },
        pid: { 4242 },
        appName: { "Safari" },
        now: { clock.value })
    sight.begin(app: "Safari")
    _ = await sight.finish(wait: .zero)
    await settle(0.4)
    clock.value = clock.value.addingTimeInterval(31)
    sight.begin(app: "Safari")
    let second = await sight.finish(wait: .zero)
    expect(second.summary == nil, "M2: un resumen de más de 30 s ya no se usa")
    expect(second.pending, "M2: sin nada vigente que ofrecer, pending")
    sight.cancel()
}

/// Spec 15g-5: after a scripted classic turn the flushed line reads
/// `commit→context <ms>`, not a dash.
@MainActor func testTheTimelineLineCarriesCommitToContext() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    h.clock.now = 10
    await h.session.hold()
    await pumpUntil("context: listening") { h.watch.latest.state == .listening }
    h.clock.now = 11
    await h.session.release()
    await pumpUntil("context: el turno viaja") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    let line = await h.session.timeline.line() ?? ""
    expect(line.contains("commit→context ") && !line.contains("commit→context —"),
           "15g-5: la línea lleva commit→context con valor (\(line))")
}
