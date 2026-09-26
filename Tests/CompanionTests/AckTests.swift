import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15b-3. The router's own acknowledgement, spoken from the closed set
// already on disk: the specific reply if it is cached, "Listo."/"Done." if
// not, with the specific text warmed for next time. The reply always still
// reaches the thread in full — only what is SPOKEN is the short form.

@Test @MainActor func ackTests() async {
    testAckPolicyChoosesTheSpecificReplyWhenCached()
    testAckPolicyFallsBackToQuickAckAndWarmsWhenNotCached()
    testAckPolicyNeverCachesOrWarmsPastEightyChars()
    await testPrewarmStoresWithoutSounding()
    await testPrewarmSkipsFetchWhenAlreadyCached()
    await testRespondActedSpeaksTheQuickAckAndThreadsTheFullReplyWhenNotCached()
    await testRespondActedSpeaksTheSpecificReplyWhenCached()
}

@MainActor func testAckPolicyChoosesTheSpecificReplyWhenCached() {
    let choice = AckPolicy.choose(
        specific: "Abrí Safari.", specificCached: true, language: .es)
    expectEq(choice.speak, "Abrí Safari.", "ack: en caché habla la específica")
    expectEq(choice.warm, nil, "ack: en caché no hay nada que calentar")
}

@MainActor func testAckPolicyFallsBackToQuickAckAndWarmsWhenNotCached() {
    let en = AckPolicy.choose(specific: "Opened Safari.", specificCached: false, language: .en)
    expectEq(en.speak, "Done.", "ack: sin caché habla el acuse corto (en)")
    expectEq(en.warm, "Opened Safari.", "ack: sin caché calienta la específica (en)")
    let es = AckPolicy.choose(specific: "Abrí Safari.", specificCached: false, language: .es)
    expectEq(es.speak, "Listo.", "ack: sin caché habla el acuse corto (es)")
    expectEq(es.warm, "Abrí Safari.", "ack: sin caché calienta la específica (es)")
}

@MainActor func testAckPolicyNeverCachesOrWarmsPastEightyChars() {
    let long = String(repeating: "n", count: 81)
    let choice = AckPolicy.choose(specific: long, specificCached: false, language: .en)
    expectEq(choice.speak, "Done.", "ack: >80 igual habla el acuse corto")
    expectEq(choice.warm, nil, "ack: >80 nunca se manda a calentar (PhraseCache lo rechazaría)")
}

/// `runOk`/`withTempDir` block the calling thread on a semaphore while a
/// detached Task runs the body (SpeechSynthesisTests' own pattern) — fine
/// for a body that never needs `@MainActor` itself, but `pumpUntilAsync` is
/// `@MainActor` and would deadlock against that same blocked thread. These
/// two run as plain async tests instead, HoldVoiceTests' own style.
@MainActor func testPrewarmStoresWithoutSounding() async {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (synth, fetch, play, _, cache) = makeTTS(dir)
    await synth.prewarm(["Abrí Safari."])
    await pumpUntilAsync("prewarm: queda en caché") {
        (try? cache.data(for: "Abrí Safari.")) != nil
    }
    expectEq((try? cache.data(for: "Abrí Safari.")) ?? nil, Data("Abrí Safari.".utf8),
              "prewarm: guarda lo que trajo el fetch")
    expectEq(fetch.calls.map(\.text), ["Abrí Safari."], "prewarm: un fetch")
    expect(await play.played.isEmpty, "prewarm: nunca suena")
    expectEq(await synth.speakingNow, "", "prewarm: no toca current")
}

@MainActor func testPrewarmSkipsFetchWhenAlreadyCached() async {
    let dir = makeTempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (synth, fetch, _, _, cache) = makeTTS(dir)
    do {
        try cache.store(Data("ya estaba".utf8), for: "Hola.")
    } catch {
        expect(false, "prewarm cache hit: la preparación no debía tirar \(error)")
    }
    await synth.prewarm(["Hola."])
    await settle(0.1)
    expect(fetch.calls.isEmpty, "prewarm: ya cacheado, cero fetch")
}

func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-ack-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// `respond(.acted)` without a cached specific reply speaks the quick ack,
/// but the thread still gets the full sentence — the corpus never reads a
/// shortened reply back — and warms the specific text for next time.
@MainActor func testRespondActedSpeaksTheQuickAckAndThreadsTheFullReplyWhenNotCached() async {
    let synth = SpyAckSynth()
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: ScriptedChat(), thread: thread)
    runtime.decide = { _, _ in
        .acted(
            ParentToolOutcome(ok: true, output: "", target: "Safari"),
            ToolCallRef(id: "1", name: "open_app", arguments: #"{"name":"Safari"}"#))
    }
    await runtime.submit(config: Config(language: .en)) { _ in }
    expectEq(synth.queue, ["Done."], "respond: sin caché, el sintetizador dice el acuse corto")
    expectEq(thread.turns.last { $0.role == .assistant }?.content, "Opened Safari.",
              "respond: el hilo lleva la respuesta completa")
    expectEq(synth.prewarmed, [["Opened Safari."]],
              "respond: calienta la específica para la próxima")
}

/// The same turn, but the specific reply is already on disk: it is what
/// gets spoken, and nothing new is warmed.
@MainActor func testRespondActedSpeaksTheSpecificReplyWhenCached() async {
    let synth = SpyAckSynth()
    synth.cached = ["Opened Safari."]
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: ScriptedChat(), thread: thread)
    runtime.decide = { _, _ in
        .acted(
            ParentToolOutcome(ok: true, output: "", target: "Safari"),
            ToolCallRef(id: "1", name: "open_app", arguments: #"{"name":"Safari"}"#))
    }
    await runtime.submit(config: Config(language: .en)) { _ in }
    expectEq(synth.queue, ["Opened Safari."], "respond: en caché habla la específica")
    expect(synth.prewarmed.isEmpty, "respond: en caché no hay nada que calentar")
}

/// A minimal port fake, local to this delivery: `ScriptedSynth` (12b's fake,
/// used everywhere else) deliberately keeps using `VoicePorts`' no-op
/// defaults, so `AckPolicy`'s wiring needs its own spy that actually
/// tracks `isCached`/`prewarm`.
final class SpyAckSynth: SpeechSynthesizer, @unchecked Sendable {
    var cached: Set<String> = []
    var queue: [String] = []
    var prewarmed: [[String]] = []
    private let box = StreamBox<SpeechEvent>()
    var events: AsyncStream<SpeechEvent> { box.stream }
    func begin() async {}
    func enqueue(_ sentence: String) async { queue.append(sentence) }
    func finish() async {}
    func stop() async {}
    func spokenSoFar() async -> String? { nil }
    var speakingNow: String { "" }
    func isCached(_ phrase: String) async -> Bool { cached.contains(phrase) }
    func prewarm(_ phrases: [String]) async { prewarmed.append(phrases) }
    func warmConnection() async {}
}
