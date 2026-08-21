import CompanionCore
import Foundation
import Testing

@Test @MainActor func voicePortsTests() {
    testMicFrame()
    testVoiceTransportError()
    testSpeechEvent()
    testVoiceLevels()
    testVoiceTransportFake()
    testMicCapturingFake()
    testPCMPlayingFake()
    testTranscriberFake()
    testSpeechSynthesizerFake()
    testVoiceControllingFake()
    testConversationPresentingFake()
}

@MainActor func testMicFrame() {
    let empty = MicFrame(pcm16le24k: Data(), rms: 0)
    expectEq(empty, MicFrame(pcm16le24k: Data(), rms: 0), "frame: vacío Equatable")
    expectEq(empty.rms, 0, "frame: rms 0")

    let hola = MicFrame(pcm16le24k: Data("hola".utf8), rms: 0.5)
    expectEq(hola.pcm16le24k, Data("hola".utf8), "frame: pcm viaja")
    expect(hola != MicFrame(pcm16le24k: Data("hola".utf8), rms: 0.6),
           "frame: rms distinto")
    expect(hola != MicFrame(pcm16le24k: Data("adiós".utf8), rms: 0.5),
           "frame: pcm distinto")

    let unicode = MicFrame(pcm16le24k: Data("ñoño — café 👋".utf8), rms: 1)
    expectEq(unicode.pcm16le24k, Data("ñoño — café 👋".utf8), "frame: unicode")

    let binary = MicFrame(pcm16le24k: Data([0x00, 0xFF, 0x7F, 0x80]), rms: -1)
    expectEq(binary.pcm16le24k, Data([0x00, 0xFF, 0x7F, 0x80]), "frame: binario")
    expectEq(binary.rms, -1, "frame: rms negativo")
    let large = Data(repeating: 0xAB, count: 10_000)
    expectEq(MicFrame(pcm16le24k: large, rms: 99).pcm16le24k.count, 10_000,
             "frame: 10k bytes")
}

@MainActor func testVoiceTransportError() {
    expectEq(VoiceTransportError.timeout, .timeout, "ws: timeout")
    expectEq(VoiceTransportError.unauthorized, .unauthorized, "ws: 401")
    expectEq(VoiceTransportError.closed, .closed, "ws: closed")
    expectEq(VoiceTransportError.unreachable, .unreachable, "ws: unreachable")
    expect(VoiceTransportError.timeout != .unauthorized, "ws: timeout ≠ 401")
    expect(VoiceTransportError.closed != .unreachable, "ws: closed ≠ unreachable")
    expect(VoiceTransportError.timeout != .closed, "ws: timeout ≠ closed")
    let boxed: Error = VoiceTransportError.timeout
    expectEq(boxed as? VoiceTransportError, .timeout, "ws: viaja como Error")
}

@MainActor func testSpeechEvent() {
    expectEq(SpeechEvent.finished, .finished, "speech: finished")
    expectEq(SpeechEvent.failed, .failed, "speech: failed")
    expect(SpeechEvent.finished != .failed, "speech: finished ≠ failed")
    expectEq(SpeechEvent.level(0), .level(0), "speech: level 0")
    expect(SpeechEvent.level(0) != .level(1), "speech: levels distintos")
    expect(SpeechEvent.level(-0.5) != .finished, "speech: level ≠ finished")
    expectEq(SpeechEvent.chunkStarted(text: "", duration: 0),
             .chunkStarted(text: "", duration: 0), "speech: chunk vacío")
    expect(SpeechEvent.chunkStarted(text: "hola", duration: 0)
           != .chunkStarted(text: "hola", duration: 1), "speech: duration")
    expect(SpeechEvent.chunkStarted(text: "hola", duration: 1)
           != .chunkStarted(text: "Hola", duration: 1), "speech: texto exacto")
    expectEq(SpeechEvent.chunkStarted(text: "ñoño 👋", duration: 2.5),
             .chunkStarted(text: "ñoño 👋", duration: 2.5), "speech: unicode")
}

@MainActor func testVoiceLevels() {
    let zero = VoiceLevels(mic: 0, agent: 0)
    expectEq(zero, VoiceLevels(mic: 0, agent: 0), "levels: Equatable")
    expectEq(zero.mic, 0, "levels: mic 0")
    expect(VoiceLevels(mic: 1, agent: 0) != VoiceLevels(mic: 0, agent: 1),
           "levels: mic ≠ agent")
    let mixed = VoiceLevels(mic: 0.25, agent: -1)
    expectEq(mixed.mic, 0.25, "levels: fracción")
    expectEq(mixed.agent, -1, "levels: negativo")
}

@MainActor func testVoiceTransportFake() {
    let fake = FakeTransport()
    let port: any VoiceTransport = fake
    let url = URL(string: "wss://api.openai.com/v1/realtime")!
    runOk("ws feliz") {
        try await port.open(key: "sk-live", url: url)
        try await port.send(#"{"type":"session.update"}"#)
        try await port.send("")
        try await port.send("ñoño — café")
        fake.yield(.speechStarted)
        fake.yield(.speechStopped)
        await port.close()
        expectEq(await drain(port.events()), [.speechStarted, .speechStopped],
                 "ws: events")
    }
    expectEq(fake.key, "sk-live", "ws: key")
    expectEq(fake.url, url, "ws: url")
    expectEq(fake.sent, [#"{"type":"session.update"}"#, "", "ñoño — café"],
             "ws: send vacío y unicode")
    expect(fake.closed, "ws: close")

    for want: VoiceTransportError in [
        .timeout, .unauthorized, .closed, .unreachable,
    ] {
        let failing = FakeTransport()
        failing.openError = want
        expectThrow(want, "ws open \(want)") {
            try await failing.open(key: "", url: URL(string: "wss://x")!)
        }
    }
    let sendFail = FakeTransport()
    sendFail.sendError = .closed
    expectThrow(.closed, "ws send") { try await sendFail.send("x") }
}

@MainActor func testMicCapturingFake() {
    let fake = FakeMic()
    let port: any MicCapturing = fake
    let frame = MicFrame(pcm16le24k: Data("hola".utf8), rms: 0.2)
    let empty = MicFrame(pcm16le24k: Data(), rms: 0)
    runOk("mic feliz") {
        expect(await port.requestAccess(), "mic: access default")
        try await port.start()
        await port.disableVoiceProcessing()
        fake.yield(frame)
        fake.yield(empty)
        await port.stop()
        expectEq(await drain(port.frames), [frame, empty], "mic: frames + vacío")
        expect(!(await port.hasEchoCancellation), "mic: echo default off")
    }
    expect(fake.started && fake.vpDisabled && fake.stopped, "mic: flags")
    expect(fake.receivedBuffer, "mic: receivedBuffer")

    let denied = FakeMic()
    denied.granted = false
    denied.hasEchoCancellation = true
    runOk("mic deny") {
        expect(!(await denied.requestAccess()), "mic: denegado")
        expect(await denied.hasEchoCancellation, "mic: echo on")
    }
    let boom = FakeMic()
    boom.startError = .unreachable
    expectThrow(.unreachable, "mic start") { try await boom.start() }
}

@MainActor func testPCMPlayingFake() {
    let fake = FakePlayer()
    let port: any PCMPlaying = fake
    runOk("pcm feliz") {
        try await port.start(sharedEngine: true)
        await port.play(Data("hola".utf8))
        await port.play(Data())
        fake.yieldLevel(0.4)
        await port.flush()
        await port.stop()
        expectEq((await drain(port.drained)).count, 1, "pcm: drained")
        expectEq(await drain(port.levels), [0.4], "pcm: levels")
    }
    expectEq(fake.shared, true, "pcm: shared true")
    expectEq(fake.played, [Data("hola".utf8), Data()], "pcm: play vacío")
    expect(fake.flushed && fake.stopped && !fake.hasPending, "pcm: flush/stop")

    let solo = FakePlayer()
    runOk("pcm solo") { try await solo.start(sharedEngine: false) }
    expectEq(solo.shared, false, "pcm: shared false")
    runOk("pcm pending") {
        expect(!(await (solo as any PCMPlaying).hasPending), "pcm: sin pending")
    }
}

@MainActor func testTranscriberFake() {
    let fake = FakeTranscriber()
    let port: any Transcriber = fake
    let frame = MicFrame(pcm16le24k: Data([0x01, 0x02]), rms: 0.1)
    fake.stoppedText = "qué hora es"
    runOk("stt feliz") {
        expect(!(await port.isAuthorized), "stt: default no")
        expect(await port.requestAuthorization(), "stt: grant")
        expect(await port.isAuthorized, "stt: queda sí")
        try await port.start(localeIdentifier: "es-MX")
        await port.append(frame)
        await port.append(MicFrame(pcm16le24k: Data(), rms: 0))
        fake.yieldPartial("")
        fake.yieldPartial("ñoño")
        expectEq(await port.stop(), "qué hora es", "stt: stop")
        expectEq(await drain(port.partials), ["", "ñoño"], "stt: partials")
    }
    expectEq(fake.locale, "es-MX", "stt: locale")
    expectEq(fake.appended.count, 2, "stt: dos frames")
    expectEq(fake.appended[1].pcm16le24k, Data(), "stt: frame vacío")
    let emptyLocale = FakeTranscriber()
    runOk("stt locale") { try await emptyLocale.start(localeIdentifier: "") }
    expectEq(emptyLocale.locale, "", "stt: locale vacío")
}

@MainActor func testSpeechSynthesizerFake() {
    let fake = FakeSpeech()
    let port: any SpeechSynthesizer = fake
    runOk("tts feliz") {
        expect(await port.spokenSoFar() == nil, "tts: spoken nil")
        expectEq(await port.speakingNow, "", "tts: speaking vacío")
        await port.begin()
        await port.enqueue("")
        await port.enqueue("ñoño — café 👋")
        await port.finish()
        fake.yield(.chunkStarted(text: "hola", duration: 0.3))
        fake.yield(.level(0.8))
        fake.yield(.finished)
        fake.yield(.failed)
        await port.stop()
        expectEq(await drain(port.events), [
            .chunkStarted(text: "hola", duration: 0.3),
            .level(0.8), .finished, .failed,
        ], "tts: events")
    }
    expect(fake.began && fake.finished && fake.stopped, "tts: flags")
    expectEq(fake.queue, ["", "ñoño — café 👋"], "tts: enqueue")
    fake.spoken = "parcial"
    fake.speakingNow = "ahora"
    runOk("tts spoken") {
        expectEq(await port.spokenSoFar(), "parcial", "tts: spokenSoFar")
        expectEq(await port.speakingNow, "ahora", "tts: speakingNow")
    }
}

@MainActor func testVoiceControllingFake() {
    let fake = FakeVoice()
    let port: any VoiceControlling = fake
    let snap = TurnSnapshot(state: .listening, muted: true)
    let levels = VoiceLevels(mic: 0.2, agent: 0.9)
    runOk("ctrl feliz") {
        await port.start()
        await port.advance()
        await port.toggleMute()
        await port.toggleMute()
        fake.yieldSnapshot(snap)
        fake.yieldSnapshot(.idle)
        fake.yieldLevels(levels)
        await port.hangUp()
        expectEq(await drain(port.snapshots), [snap, .idle], "ctrl: snapshots")
        expectEq(await drain(port.levels), [levels], "ctrl: levels")
    }
    expect(fake.started && fake.advanced && fake.hungUp && !fake.muted,
           "ctrl: flags y mute×2")
}

@MainActor func testConversationPresentingFake() {
    let fake = FakePresenter()
    let port: any ConversationPresenting = fake
    runOk("present feliz") {
        expectEq(await port.historyTurns(), [], "present: vacío")
        await port.appendUser("")
        await port.appendUser("ñoño — café 👋")
        await port.appendAssistant("ok")
        await port.appendStatus("pensando")
        await port.showStream("Ho")
        await port.showStream("")
        await port.finishStream()
        let turns = await port.historyTurns()
        expectEq(turns.map(\.role), [.user, .user, .assistant], "present: roles")
        expectEq(turns.map(\.content), ["", "ñoño — café 👋", "ok"],
                 "present: textos")
    }
    expectEq(fake.status, ["pensando"], "present: status")
    expectEq(fake.stream, "", "present: showStream pisa")
    expect(fake.finished, "present: finishStream")
}

struct StreamBox<T: Sendable>: @unchecked Sendable {
    let stream: AsyncStream<T>
    let cont: AsyncStream<T>.Continuation
    init() { (stream, cont) = AsyncStream.makeStream(of: T.self) }
    func yield(_ value: T) { cont.yield(value) }
    func finish() { cont.finish() }
}

func drain<T: Sendable>(_ stream: AsyncStream<T>) async -> [T] {
    var out: [T] = []
    for await item in stream { out.append(item) }
    return out
}

@MainActor func runOk(_ label: String, _ body: @escaping @Sendable () async throws -> Void) {
    do { try runAsync(body) }
    catch { expect(false, "\(label): no debía tirar \(error)") }
}

@MainActor func expectThrow(
    _ want: VoiceTransportError, _ label: String,
    _ body: @escaping @Sendable () async throws -> Void
) {
    do {
        try runAsync(body)
        expect(false, "\(label): debía tirar \(want)")
    } catch let error as VoiceTransportError {
        expectEq(error, want, label)
    } catch {
        expect(false, "\(label): VoiceTransportError, no \(error)")
    }
}

final class FakeTransport: VoiceTransport, @unchecked Sendable {
    var key: String?, url: URL?, sent: [String] = [], closed = false
    var openError: VoiceTransportError?, sendError: VoiceTransportError?
    private let box = StreamBox<RealtimeEvent>()
    func open(key: String, url: URL) async throws {
        if let openError { throw openError }
        (self.key, self.url) = (key, url)
    }
    func send(_ json: String) async throws { if let sendError { throw sendError }; sent.append(json) }
    func events() -> AsyncStream<RealtimeEvent> { box.stream }
    func close() async { closed = true; box.finish() }
    func yield(_ event: RealtimeEvent) { box.yield(event) }
}

final class FakeMic: MicCapturing, @unchecked Sendable {
    var granted = true, started = false, stopped = false, vpDisabled = false
    var startError: VoiceTransportError?
    var hasEchoCancellation = false, receivedBuffer = false
    private let box = StreamBox<MicFrame>()
    var frames: AsyncStream<MicFrame> { box.stream }
    func requestAccess() async -> Bool { granted }
    func start() async throws { if let startError { throw startError }; started = true }
    func stop() async { stopped = true; box.finish() }
    func disableVoiceProcessing() async { vpDisabled = true }
    func yield(_ frame: MicFrame) { receivedBuffer = true; box.yield(frame) }
}

final class FakePlayer: PCMPlaying, @unchecked Sendable {
    var shared: Bool?, played: [Data] = []
    var flushed = false, stopped = false, hasPending = false
    private let drainBox = StreamBox<Void>()
    private let levelBox = StreamBox<Double>()
    var drained: AsyncStream<Void> { drainBox.stream }
    var levels: AsyncStream<Double> { levelBox.stream }
    func start(sharedEngine: Bool) async throws { shared = sharedEngine }
    func play(_ pcm16le24k: Data) async { played.append(pcm16le24k); hasPending = true }
    func flush() async { flushed = true; hasPending = false; drainBox.yield(()) }
    func stop() async { stopped = true; drainBox.finish(); levelBox.finish() }
    func yieldLevel(_ value: Double) { levelBox.yield(value) }
}

final class FakeTranscriber: Transcriber, @unchecked Sendable {
    var authorized = false, locale = "", stoppedText = ""
    var appended: [MicFrame] = []
    var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    var partials: AsyncStream<String> { box.stream }
    func requestAuthorization() async -> Bool { authorized = true; return authorized }
    func start(localeIdentifier: String) async throws { locale = localeIdentifier }
    func append(_ frame: MicFrame) async { appended.append(frame) }
    func stop() async -> String { box.finish(); return stoppedText }
    func yieldPartial(_ text: String) { box.yield(text) }
}

final class FakeSpeech: SpeechSynthesizer, @unchecked Sendable {
    var began = false, finished = false, stopped = false
    var queue: [String] = [], spoken: String?, speakingNow = ""
    private let box = StreamBox<SpeechEvent>()
    var events: AsyncStream<SpeechEvent> { box.stream }
    func begin() async { began = true }
    func enqueue(_ sentence: String) async { queue.append(sentence) }
    func finish() async { finished = true }
    func stop() async { stopped = true; box.finish() }
    func spokenSoFar() async -> String? { spoken }
    func yield(_ event: SpeechEvent) { box.yield(event) }
}

final class FakeVoice: VoiceControlling, @unchecked Sendable {
    private(set) var speeds: [Double] = []
    func setSpeed(_ speed: Double) async { speeds.append(speed) }

    var started = false, advanced = false, hungUp = false, muted = false
    private let snapBox = StreamBox<TurnSnapshot>()
    private let levelBox = StreamBox<VoiceLevels>()
    var snapshots: AsyncStream<TurnSnapshot> { snapBox.stream }
    var levels: AsyncStream<VoiceLevels> { levelBox.stream }
    func start() async { started = true }
    func advance() async { advanced = true }
    func hangUp() async { hungUp = true; snapBox.finish(); levelBox.finish() }
    func toggleMute() async { muted.toggle() }
    func push(attachment: AttachmentRef) async { pushed.append(attachment) }
    var pushed: [AttachmentRef] = []
    func yieldSnapshot(_ snapshot: TurnSnapshot) { snapBox.yield(snapshot) }
    func yieldLevels(_ value: VoiceLevels) { levelBox.yield(value) }
}

final class FakePresenter: ConversationPresenting, @unchecked Sendable {
    var turns: [Turn] = [], status: [String] = [], stream = "", finished = false
    func historyTurns() async -> [Turn] { turns }
    func appendUser(_ text: String) async { turns.append(Turn(role: .user, content: text)) }
    func appendAssistant(_ text: String) async {
        turns.append(Turn(role: .assistant, content: text))
    }
    func appendStatus(_ text: String) async { status.append(text) }
    func showStream(_ text: String) async { stream = text }
    func finishStream() async { finished = true }
}
