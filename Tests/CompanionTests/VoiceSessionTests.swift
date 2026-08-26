import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func voiceSessionTests() async {
    await testStartWithKeyListensRealtime()
    await testMuteAfterSpeechCommitsNativeText()
    await testUserTurnPreemptsActiveResponse()
    await testSegmentingEarDrivesTheTurn()
    await testSpeakerEchoIsDroppedButRealInterruptionCuts()
    await testMuteWithoutSpeechDoesNotCommit()
    await testUnmuteClearsAudio()
    await testSpeakingSpeechStartedCancels()
    await testNoKeyClassicListen()
    await testDenyingSpeechIsNotBlamedOnTheVoice()
    await testOpenTimeoutFallsBackClassic()
    await testOfflineStaysInErrorWithoutFallback()
    await testEchoFreeBargeInWhileSpeaking()
    await testSilentMicFailsLoud()
    await testLiveMicSurvivesSilenceWatchdog()
    await testHangUpClosesTransport()
    await testNoBargeInWithoutAEC()
    await testFunctionCallRefusal()
}

@MainActor func testStartWithKeyListensRealtime() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("start: listening realtime") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    expect(h.transport.key == "sk-test", "start: abre con la key")
    expectEq(h.transport.url, RealtimeCodec.url(), "start: URL realtime")
    expect(h.mic.started, "start: micrófono arranca")
    expectEq(h.player.shared, false, "start: AEC off → player propio")
    expect(hasMessage(h.transport.sent, type: "session.update"),
           "start: manda session.update")
    expect(hasVoiceInSessionUpdate(h.transport.sent),
           "start: la primera update lleva voz")
}

/// 9j-1: with a segmenting ear the server's VAD owns the turns — a finished
/// segment commits AS the turn's text, with no local endpointer involved. And
/// over the agent, a one-word segment is a backchannel and is dropped.
@MainActor func testSegmentingEarDrivesTheTurn() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.start()
    await pumpUntil("segmento: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    ear.yieldTurn(.speechStarted)
    await pumpUntil("segmento: speechOpen") { h.watch.latest.speechOpen }
    ear.yieldTurn(.finished(text: "crea prueba dos en el desktop"))
    await pumpUntil("segmento: el texto del segmento ES el turno") {
        Array(h.transport.sent.dropFirst(before))
            .contains { $0.contains("crea prueba dos en el desktop") }
    }
    expect(hasMessage(Array(h.transport.sent.dropFirst(before)),
                      type: "response.create"),
           "segmento: y pide la respuesta")

    // Un "ajá" sobre el agente no interrumpe ni se vuelve turno.
    h.transport.yield(.audioDelta(Data([0x01, 0x00])))
    await pumpUntil("segmento: speaking") { h.watch.latest.state == .speaking }
    let during = h.transport.sent.count
    ear.yieldTurn(.finished(text: "ajá"))
    await settle(0.1)
    expect(!Array(h.transport.sent.dropFirst(during))
        .contains { $0.contains("ajá") },
           "segmento: un backchannel de una palabra se tira")
}

/// 9j-6a: barge-in on SPEAKERS without AEC. The mic hears the agent; that
/// echo transcribes as the agent's own words and is dropped by text overlap.
/// Words that are NOT the agent's are the user really breaking in.
@MainActor func testSpeakerEchoIsDroppedButRealInterruptionCuts() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.start()
    await pumpUntil("eco: listening") { h.watch.latest.state == .listening }
    // El agente habla: su transcript es la referencia del eco.
    h.transport.yield(.responseCreated)
    h.transport.yield(.assistantTranscriptDelta("te cuento la historia del faro"))
    h.transport.yield(.audioDelta(Data([0x01, 0x00])))
    await pumpUntil("eco: speaking") { h.watch.latest.state == .speaking }

    // Las bocinas devuelven las palabras del agente: eco, se tira.
    let before = h.transport.sent.count
    ear.yieldTurn(.finished(text: "cuento la historia del faro"))
    await settle(0.15)
    expect(!Array(h.transport.sent.dropFirst(before))
        .contains { $0.contains("historia del faro") },
           "eco: las palabras del agente no se vuelven turno del usuario")

    // Palabras que NO son del agente: interrupción real → cancela y commitea.
    ear.yieldTurn(.finished(text: "espera mejor hazlo en otra carpeta"))
    await pumpUntil("eco: la interrupción real se commitea") {
        Array(h.transport.sent.dropFirst(before))
            .contains { $0.contains("espera mejor hazlo") }
    }
    expect(hasMessage(Array(h.transport.sent.dropFirst(before)),
                      type: "response.cancel"),
           "eco: y corta al agente")
}

/// Wave 9i: muting mid-utterance commits the turn from the NATIVE transcript —
/// there is no audio buffer at OpenAI to commit any more.
@MainActor func testMuteAfterSpeechCommitsNativeText() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola compa"
    await h.session.start()
    await pumpUntil("mute-speech: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("mute-speech: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("mute-speech: texto nativo enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)),
                   type: "conversation.item.create")
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(added.contains { $0.contains("hola compa") },
           "mute-speech: viaja el texto de Apple, no audio")
    expect(hasMessage(added, type: "response.create"),
           "mute-speech: response.create tras el texto")
    expect(h.watch.latest.pipeline == .realtime, "mute-speech: sigue realtime")
}

/// The server holds ONE response at a time; a user turn committed mid-response
/// used to be rejected ("already has an active response") and the turn's text
/// was left orphaned — "en mi desktop" answered a question nobody processed.
/// The funnel cancels the active response first: the user's voice outranks it.
@MainActor func testUserTurnPreemptsActiveResponse() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "en mi desktop"
    await h.session.start()
    await pumpUntil("preempt: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.responseCreated)
    h.transport.yield(.speechStarted)
    await pumpUntil("preempt: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()  // commits the turn from the native text
    await pumpUntil("preempt: turno enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)),
                   type: "response.create")
    }
    let added = Array(h.transport.sent.dropFirst(before))
    let cancelAt = added.firstIndex { $0.contains("response.cancel") }
    let createAt = added.firstIndex { $0.contains("response.create") }
    expect(cancelAt != nil, "preempt: cancela la respuesta activa")
    expect(cancelAt! < createAt!,
           "preempt: el cancel viaja ANTES del create del turno nuevo")
}

@MainActor func testMuteWithoutSpeechDoesNotCommit() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("mute-quiet: listening") { h.watch.latest.state == .listening }
    expect(!h.watch.latest.speechOpen, "mute-quiet: sin speechOpen")
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("mute-quiet: muted") { h.watch.latest.muted }
    await settle(0.4)  // past the commit's transcript-settle delay
    let added = Array(h.transport.sent.dropFirst(before))
    expect(!hasMessage(added, type: "conversation.item.create"),
           "mute-quiet: sin turno — no hay texto que mandar")
    expect(!hasMessage(added, type: "response.create"),
           "mute-quiet: sin response.create")
}

@MainActor func testUnmuteClearsAudio() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("unmute: listening") { h.watch.latest.state == .listening }
    await h.session.toggleMute()
    await pumpUntil("unmute: muted") { h.watch.latest.muted }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("unmute: off") { !h.watch.latest.muted }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(hasMessage(added, type: "input_audio_buffer.clear"),
           "unmute: tira el audio rancio")
}

@MainActor func testSpeakingSpeechStartedCancels() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("barge-in: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x01, 0x00, 0x02, 0x00])))
    await pumpUntil("barge-in: speaking") { h.watch.latest.state == .speaking }
    expect(!h.player.played.isEmpty, "barge-in: el PCM llega al player")
    let before = h.transport.sent.count
    h.transport.yield(.speechStarted)
    await pumpUntil("barge-in: listening otra vez") {
        h.watch.latest.state == .listening && h.watch.latest.speechOpen
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(hasMessage(added, type: "response.cancel"),
           "barge-in: response.cancel en el json enviado")
    expect(h.player.flushed, "barge-in: flush del player")
}

@MainActor func testNoKeyClassicListen() async {
    let h = makeVoiceHarness(key: nil, autoEvents: [])
    await h.session.start()
    await pumpUntil("classic: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    expectEq(h.transcriber.locale, "en-US",
             "classic: SFSpeech en el idioma del usuario")
    expect(h.transcriber.started, "classic: transcriber.start")
    expect(h.transport.key == nil, "classic: no abre realtime sin key")
    expect(h.transport.sent.isEmpty, "classic: no manda frames al WS")
}

/// Negar el reconocimiento de voz es negar un permiso de ENTRADA, y se
/// reportaba como `.speechEngine`, cuya copy manda a revisar la sintesis:
/// quien acababa de decir "no" a un dialogo del sistema era enviado al lugar
/// equivocado, sin una sola pista del permiso que habia negado.
@MainActor func testDenyingSpeechIsNotBlamedOnTheVoice() async {
    let h = makeVoiceHarness(key: nil, autoEvents: [])
    h.transcriber.grantsAuthorization = false
    await h.session.start()
    await pumpUntil("permiso: la sesión no arranca") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .speechDenied,
             "permiso: el fallo dice que falta un permiso, no que se rompió el TTS")
    expect(!h.transcriber.started,
           "permiso: sin autorización no se arma el reconocedor")
}

@MainActor func testOpenTimeoutFallsBackClassic() async {
    // Online: the realtime server did not answer, but classic still works.
    let h = makeVoiceHarness(autoEvents: [], readyTimeout: 0.05)
    await h.session.start()
    await pumpUntil("timeout: fallback classic") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    expectEq(h.transcriber.locale, "en-US", "timeout: arma el transcriber")
    expect(h.transcriber.started, "timeout: transcriber.start")
    // El aviso ya NO sale de aquí: Services escribía su propia redacción del
    // fallo además de la del catálogo, y el usuario leía dos mensajes para un
    // solo problema. El dueño es VoiceViewModel, que lo emite una vez y en el
    // idioma del catálogo (VoiceViewModelTests lo exige).
    expect(h.thread.status.isEmpty,
           "timeout: Services no escribe copy de usuario")
}

@MainActor func testOfflineStaysInErrorWithoutFallback() async {
    let h = makeVoiceHarness(autoEvents: [], readyTimeout: 0.05, online: false)
    await h.session.start()
    await pumpUntil("offline: estado de error") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .networkUnavailable,
             "offline: la razón es la falta de red")
    expect(!h.transcriber.started,
           "offline: no arma el clásico, que también necesita red")
    expect(h.watch.latest.pipeline != .classic,
           "offline: no cambia de pipeline")
}

@MainActor func testSilentMicFailsLoud() async {
    let h = makeVoiceHarness(micSilenceTimeout: 0.05)
    h.mic.receivedBuffer = false
    await h.session.start()
    await pumpUntil("mic-silencio: error visible") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .micSilent,
             "mic-silencio: la razón es que no entregó audio")
}

@MainActor func testLiveMicSurvivesSilenceWatchdog() async {
    let h = makeVoiceHarness(micSilenceTimeout: 0.05)
    await h.session.start()
    await pumpUntil("mic-vivo: listening") { h.watch.latest.state == .listening }
    await settle(0.15)
    expectEq(h.watch.latest.state, .listening,
             "mic-vivo: el watchdog no dispara con buffers llegando")
}

@MainActor func testHangUpClosesTransport() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("hangup: listening") { h.watch.latest.state == .listening }
    await h.session.hangUp()
    await pumpUntil("hangup: idle") { h.watch.latest.state == .idle }
    expect(h.transport.closed, "hangup: cierra el transporte")
    expect(h.player.stopped, "hangup: para el player")
    expect(h.mic.stopped, "hangup: para el mic")
}

/// Wave 9i: the mic never reaches OpenAI, so barge-in is a LOCAL decision. On
/// echo-free output (headphones), a vetted frame while the agent speaks cuts
/// it — a `response.cancel`. A single loud frame is a backchannel and does not.
@MainActor func testEchoFreeBargeInWhileSpeaking() async {
    let h = makeVoiceHarness(echoFreeOutput: true)
    await h.session.start()
    await pumpUntil("echo-free: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x03, 0x00])))
    await pumpUntil("echo-free: speaking") { h.watch.latest.state == .speaking }
    let before = h.transport.sent.count

    // A single loud frame is a backchannel ("ajá") — must NOT cut the agent.
    h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    await settle(0.05)
    expectEq(cancelCount(Array(h.transport.sent.dropFirst(before))), 0,
             "echo-free: un asentimiento corto no interrumpe")

    // Sustained speech barges in: the agent is cancelled.
    for _ in 0 ..< BackchannelGate.defaultRequiredFrames {
        h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    }
    await pumpUntil("echo-free: hablar sostenido sí interrumpe") {
        cancelCount(Array(h.transport.sent.dropFirst(before))) >= 1
    }
}

/// Without AEC the mic hears the agent (room echo), so sustained frames over
/// the agent must NOT be taken as the user barging in — that would be the
/// agent cutting itself off. No `response.cancel`.
@MainActor func testNoBargeInWithoutAEC() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("echo: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x03, 0x00])))
    await pumpUntil("echo: speaking") { h.watch.latest.state == .speaking }
    let before = h.transport.sent.count

    for _ in 0 ..< BackchannelGate.defaultRequiredFrames * 2 {
        h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    }
    await settle(0.06)
    expectEq(cancelCount(Array(h.transport.sent.dropFirst(before))), 0,
             "echo: sin AEC, hablar sobre el agente no interrumpe (podría ser eco)")
}

@MainActor func testFunctionCallRefusal() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("fn: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    h.transport.yield(
        .functionCall(name: "delegate", arguments: #"{"goal":"x"}"#, callId: "c1"))
    await pumpUntil("fn: output enviado") {
        h.transport.sent.dropFirst(before).contains {
            $0.contains("function_call_output")
        }
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(added.contains { $0.contains("Jobs will be available") },
           "fn: negativa de encargos")
    expect(added.contains { $0.contains("c1") }, "fn: call_id viaja")
    expect(hasMessage(added, type: "response.create"),
           "fn: response.create tras el output")
    expect(!h.watch.latest.awaitingExecutor, "fn: no dispara delegateCallStarted")
}

struct VoiceHarness {
    let session: VoiceSession
    let transport: ScriptedVoiceTransport
    let mic: ScriptedMic
    let player: ScriptedPlayer
    let transcriber: ScriptedTranscriber
    let thread: ScriptedThread
    let clock: TestClock
    let watch: SnapWatch
}

private struct ScriptedReachability: ReachabilityProbing {
    let online: Bool
    init(_ online: Bool) { self.online = online }
    var isOnline: Bool { get async { online } }
}

@MainActor
func makeVoiceHarness(
    key: String? = "sk-test",
    autoEvents: [RealtimeEvent] = [.sessionCreated, .sessionUpdated],
    readyTimeout: TimeInterval = 1,
    aec: Bool = false,
    online: Bool = true,
    micSilenceTimeout: TimeInterval = 10,
    echoFreeOutput: Bool = false,
    jobs: (any JobSubmitter)? = nil,
    language: AppLanguage = .en,
    realtimeEar: (any Transcriber)? = nil
) -> VoiceHarness {
    let transport = ScriptedVoiceTransport()
    transport.autoEvents = autoEvents
    let mic = ScriptedMic()
    mic.hasEchoCancellation = aec
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    var keys: [SecretKey: String] = [:]
    if let key { keys[.openAI] = key }
    let secrets = ScriptedSecrets(keys)
    let thread = ScriptedThread()
    let clock = TestClock()
    let provider = StaticConfigProvider(
        Config(ownerFirstName: "Karen", language: language))
    let session = VoiceSession(
        transport: transport,
        mic: mic,
        player: player,
        transcriber: transcriber,
        synthesizer: synth,
        chat: chat,
        secrets: secrets,
        thread: thread,
        configProvider: provider,
        jobs: jobs,
        realtimeEar: realtimeEar,
        reachability: ScriptedReachability(online),
        echoFreeProbe: { echoFreeOutput },
        micSilenceTimeout: micSilenceTimeout,
        now: { clock.now },
        readyTimeout: readyTimeout)
    let watch = SnapWatch(session.snapshots)
    return VoiceHarness(
        session: session, transport: transport, mic: mic, player: player,
        transcriber: transcriber, thread: thread, clock: clock, watch: watch)
}

private func messageType(_ json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj["type"] as? String
}

func hasMessage(_ sent: [String], type: String) -> Bool {
    sent.contains { messageType($0) == type }
}

private func cancelCount(_ sent: [String]) -> Int {
    sent.filter { messageType($0) == "response.cancel" }.count
}

private func hasVoiceInSessionUpdate(_ sent: [String]) -> Bool {
    for json in sent where messageType(json) == "session.update" {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let session = obj["session"] as? [String: Any],
              let audio = session["audio"] as? [String: Any],
              let output = audio["output"] as? [String: Any],
              let voice = output["voice"] as? String
        else { continue }
        if !voice.isEmpty { return true }
    }
    return false
}

/// Static provider for tests: wraps a Config that never changes.
final class StaticConfigProvider: ConfigProviding, @unchecked Sendable {
    private let config: Config
    init(_ config: Config) { self.config = config }
    var current: Config { config }
}

final class TestClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

final class SnapWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var latestValue = TurnSnapshot.idle

    var latest: TurnSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return latestValue
    }

    init(_ stream: AsyncStream<TurnSnapshot>) {
        Task { [weak self] in
            for await snap in stream { self?.store(snap) }
        }
    }

    private func store(_ snap: TurnSnapshot) {
        lock.lock()
        latestValue = snap
        lock.unlock()
    }
}

final class ScriptedVoiceTransport: VoiceTransport, @unchecked Sendable {
    var key: String?, url: URL?, sent: [String] = [], closed = false
    var openError: VoiceTransportError?
    var autoEvents: [RealtimeEvent] = []
    var openCount = 0
    private let box = StreamBox<RealtimeEvent>()

    func open(key: String, url: URL) async throws {
        if let openError { throw openError }
        openCount += 1
        (self.key, self.url) = (key, url)
        for event in autoEvents { box.yield(event) }
    }

    func send(_ json: String) async throws { sent.append(json) }
    func events() -> AsyncStream<RealtimeEvent> { box.stream }
    func close() async { closed = true }
    func yield(_ event: RealtimeEvent) { box.yield(event) }

    /// Simulate transport pump receiving an error and failing.
    func simulateReceiveFailure() async {
        await Task.yield()
        box.finish()
    }

    /// Simulate stream ending without explicit close (abrupt termination).
    func simulateStreamEnd() async {
        await Task.yield()
        box.finish()
    }
}

final class ScriptedMic: MicCapturing, @unchecked Sendable {
    var granted = true, started = false, stopped = false
    var hasEchoCancellation = false, receivedBuffer = true
    var startError: VoiceTransportError?
    private let box = StreamBox<MicFrame>()
    var frames: AsyncStream<MicFrame> { box.stream }

    func requestAccess() async -> Bool { granted }
    func start() async throws {
        if let startError { throw startError }
        started = true
        stopped = false
    }
    func stop() async { stopped = true }
    func disableVoiceProcessing() async { hasEchoCancellation = false }
    func yield(_ frame: MicFrame) {
        receivedBuffer = true
        box.yield(frame)
    }
}

final class ScriptedPlayer: PCMPlaying, @unchecked Sendable {
    var shared: Bool?, played: [Data] = []
    var flushed = false, stopped = false, hasPending = false
    var volumes: [Double] = []
    private let drainBox = StreamBox<Void>()
    private let levelBox = StreamBox<Double>()
    var drained: AsyncStream<Void> { drainBox.stream }
    var levels: AsyncStream<Double> { levelBox.stream }

    func start(sharedEngine: Bool) async throws { shared = sharedEngine }
    func play(_ pcm16le24k: Data) async {
        played.append(pcm16le24k)
        hasPending = true
    }
    func flush() async {
        flushed = true
        hasPending = false
        drainBox.yield(())
    }
    func stop() async { stopped = true }
    func setVolume(_ volume: Double) async { volumes.append(volume) }
    func yieldDrained() {
        hasPending = false
        drainBox.yield(())
    }
}

final class ScriptedTranscriber: Transcriber, @unchecked Sendable {
    var authorized = false, locale = "", started = false, stoppedText = ""
    var grantsAuthorization = true
    var appended: [MicFrame] = []
    var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    var partials: AsyncStream<String> { box.stream }
    var currentText: String { stoppedText }

    func requestAuthorization() async -> Bool {
        authorized = grantsAuthorization
        return authorized
    }
    func start(localeIdentifier: String) async throws {
        locale = localeIdentifier
        started = true
    }
    func append(_ frame: MicFrame) async { appended.append(frame) }
    func stop() async -> String { stoppedText }
}

/// A segmenting ear (9j-1): the server's VAD decides the turns and hands
/// each finished utterance as final text.
final class ScriptedSegmentingEar: SegmentingTranscriber, @unchecked Sendable {
    var authorized = true, locale = "", started = false, stoppedText = ""
    var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    private let turns = StreamBox<EarTurnEvent>()
    var partials: AsyncStream<String> { box.stream }
    var turnEvents: AsyncStream<EarTurnEvent> { turns.stream }
    var currentText: String { stoppedText }

    func requestAuthorization() async -> Bool { authorized }
    func start(localeIdentifier: String) async throws {
        locale = localeIdentifier
        started = true
    }
    func append(_ frame: MicFrame) async {}
    func stop() async -> String { stoppedText }
    func yieldTurn(_ event: EarTurnEvent) { turns.yield(event) }
}

final class ScriptedSynth: SpeechSynthesizer, @unchecked Sendable {
    var began = false, finished = false, stopped = false
    var queue: [String] = [], spoken: String?, speakingNow = ""
    private let box = StreamBox<SpeechEvent>()
    var events: AsyncStream<SpeechEvent> { box.stream }
    func begin() async { began = true }
    func enqueue(_ sentence: String) async { queue.append(sentence) }
    func finish() async { finished = true }
    func stop() async { stopped = true }
    func spokenSoFar() async -> String? { spoken }
}

final class ScriptedChat: ChatProvider, @unchecked Sendable {
    var deltas: [ChatDelta] = []
    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        let canned = deltas
        return AsyncThrowingStream { continuation in
            for delta in canned { continuation.yield(delta) }
            continuation.finish()
        }
    }
    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

final class ScriptedSecrets: SecretStore, @unchecked Sendable {
    var values: [SecretKey: String]
    init(_ values: [SecretKey: String] = [:]) { self.values = values }
    func read(_ key: SecretKey) throws -> String? { values[key] }
    func write(_ key: SecretKey, value: String) throws { values[key] = value }
    func delete(_ key: SecretKey) throws { values.removeValue(forKey: key) }
}

final class ScriptedThread: ConversationPresenting, @unchecked Sendable {
    var turns: [Turn] = [], status: [String] = [], stream = "", finished = false
    func historyTurns() async -> [Turn] { turns }
    func appendUser(_ text: String) async {
        turns.append(Turn(role: .user, content: text))
    }
    func appendAssistant(_ text: String) async {
        turns.append(Turn(role: .assistant, content: text))
    }
    func appendStatus(_ text: String) async { status.append(text) }
    func showStream(_ text: String) async { stream += text }
    func finishStream() async { finished = true }
}
