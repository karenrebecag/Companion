import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// The voice session's harness and scripted ports, shared by every voice
// test file; split out of VoiceSessionTests.swift to keep it under 800 lines.

struct VoiceHarness {
    let session: VoiceSession
    let transport: ScriptedVoiceTransport
    let mic: ScriptedMic
    let player: ScriptedPlayer
    let transcriber: ScriptedTranscriber
    let thread: ScriptedThread
    let clock: TestClock
    let watch: SnapWatch
    let synth: ScriptedSynth
    let chat: ScriptedChat
    let secrets: ScriptedSecrets
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
    realtimeEar: (any Transcriber)? = nil,
    parentTools: (any ParentToolExecuting)? = nil,
    onJobEvent: (@Sendable (JobEvent) -> Void)? = nil,
    sensor: (any ContextSensing)? = nil,
    memoryStore: (any MemoryStore)? = nil,
    approvals: (any ApprovalsProvider)? = nil,
    session sessionModel: SessionModel? = nil,
    // Wave 12e: where a hold may dictate instead of talking.
    voiceMode: VoiceMode = .automatic,
    fieldProbe: (any FocusedFieldProbing)? = nil,
    injector: (any TextInjecting)? = nil,
    // 15d-2: zero keeps every older test's release instantaneous; the
    // tail's own tests pass it explicitly.
    releaseTail: TimeInterval = 0,
    screen: (any ScreenSeeing)? = nil,
    debugTranscripts: Bool = false
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
        Config(voice: VoiceSettings(mode: voiceMode), ownerFirstName: "Karen", language: language,
               debugTranscripts: debugTranscripts))
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
        memoryStore: memoryStore,
        parentTools: parentTools,
        sensor: sensor,
        approvals: approvals,
        fieldProbe: fieldProbe,
        injector: injector,
        screen: screen,
        reachability: ScriptedReachability(online),
        echoFreeProbe: { echoFreeOutput },
        micSilenceTimeout: micSilenceTimeout,
        releaseTail: releaseTail,
        now: { clock.now },
        readyTimeout: readyTimeout)
    let watch = SnapWatch(session.snapshots)
    if onJobEvent != nil || sessionModel != nil {
        // Wave 12a: the closure became a stream; the harness keeps its shape.
        // One pump: an AsyncStream has one consumer.
        Task {
            for await event in session.events {
                if case .job(let jobEvent, _) = event { onJobEvent?(jobEvent) }
                if let sessionModel {
                    await MainActor.run { sessionModel.send(event) }
                }
            }
        }
    }
    return VoiceHarness(
        session: session, transport: transport, mic: mic, player: player,
        transcriber: transcriber, thread: thread, clock: clock, watch: watch,
        synth: synth, chat: chat, secrets: secrets)
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
    var prewarmed = false, accessAsked = false
    var hasEchoCancellation = false
    /// How many times `start()` ran, and whether one of those ran while the
    /// previous session was still live (no `stop()` in between) — the shape
    /// of the real MicCapture crash (double `installTap`, live 2026-09-23).
    var startCount = 0
    var startedWithoutStop = false
    var receivedBufferValue = true
    /// Seconds `receivedBuffer` takes to answer: the only way a test can
    /// slip a call into the session's suspension points.
    var receivedBufferDelay: TimeInterval = 0
    var receivedBuffer: Bool {
        get async {
            if receivedBufferDelay > 0 {
                try? await Task.sleep(for: .seconds(receivedBufferDelay))
            }
            return receivedBufferValue
        }
    }
    var startError: VoiceTransportError?
    private let box = StreamBox<MicFrame>()
    var frames: AsyncStream<MicFrame> { box.stream }

    func requestAccess() async -> Bool {
        accessAsked = true
        return granted
    }
    func prewarm() async { prewarmed = true }
    /// Seconds `start()` takes: lets a test land a release or a discard
    /// while the mic is still coming up.
    var startDelay: TimeInterval = 0
    func start() async throws {
        if startDelay > 0 { try? await Task.sleep(for: .seconds(startDelay)) }
        if let startError { throw startError }
        if started, !stopped { startedWithoutStop = true }
        started = true
        stopped = false
        startCount += 1
    }
    func stop() async { stopped = true }
    func disableVoiceProcessing() async { hasEchoCancellation = false }
    func yield(_ frame: MicFrame) {
        receivedBufferValue = true
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
    var stops = 0
    var appended: [MicFrame] = []
    var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    var partials: AsyncStream<String> { box.stream }
    var currentText: String { stoppedText }

    /// Seconds the speech prompt takes to answer.
    var authorizationDelay: TimeInterval = 0
    func requestAuthorization() async -> Bool {
        if authorizationDelay > 0 { try? await Task.sleep(for: .seconds(authorizationDelay)) }
        authorized = grantsAuthorization
        return authorized
    }
    /// Seconds the on-device ear takes to come up after the mic.
    var startDelay: TimeInterval = 0
    func start(localeIdentifier: String) async throws {
        if startDelay > 0 { try? await Task.sleep(for: .seconds(startDelay)) }
        locale = localeIdentifier
        started = true
        running = true
    }
    /// Like `AnalyzerTranscriber`, which drops a frame while it has no
    /// live run: audio that reaches the ear before `start()` returned is
    /// lost, so only the early-audio path can deliver it.
    func append(_ frame: MicFrame) async {
        guard running else { return }
        appended.append(frame)
    }
    var clearOnStop = false
    /// Seconds `stop()` waits for the recognizer's final, like the real
    /// ear's `TranscriptFinalizer` bound; `running` goes false only after
    /// it, the way the real `halt()` kills whatever recognition is live
    /// by then — including one a newer hold started meanwhile.
    var stopDelay: TimeInterval = 0
    /// Per-call delays, consumed in order before `stopDelay` applies: a
    /// slow first stop followed by an instant one.
    var stopDelays: [TimeInterval] = []
    private(set) var running = false
    func stop() async -> String {
        stops += 1
        let text = stoppedText
        let delay = stopDelays.isEmpty ? stopDelay : stopDelays.removeFirst()
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        running = false
        if clearOnStop { stoppedText = "" }
        return text
    }
    /// 12c: a new hypothesis from the ear; `currentText` follows it.
    func yieldPartial(_ text: String) {
        stoppedText = text
        box.yield(text)
    }
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
    var spoken: String?, speakingNow = ""
    /// Written from the runtime's task, read from the test's: behind a lock
    /// so a read from any task is never a race (review 16h-2 L3).
    private let lock = NSLock()
    private var sentences: [String] = []
    var queue: [String] { lock.withLock { sentences } }
    private let box = StreamBox<SpeechEvent>()
    var events: AsyncStream<SpeechEvent> { box.stream }
    func begin() async { began = true }
    func enqueue(_ sentence: String) async { lock.withLock { sentences.append(sentence) } }
    func finish() async { finished = true }
    func stop() async { stopped = true }
    func spokenSoFar() async -> String? { spoken }
    func yield(_ event: SpeechEvent) { box.yield(event) }
}

final class ScriptedChat: ChatProvider, @unchecked Sendable {
    var deltas: [ChatDelta] = []
    /// Wave 10b: una lista por ronda; vacía, se repite `deltas` como antes.
    var rounds: [[ChatDelta]] = []
    private(set) var histories: [[Turn]] = []
    private(set) var toolsSeen: [ToolSpec] = []
    /// HIGH-B: a job's end streams again (the summary), so the hold's own
    /// tools are the first entry, not the last.
    private(set) var toolsPerCall: [[ToolSpec]] = []
    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        histories.append(history)
        toolsSeen = tools
        toolsPerCall.append(tools)
        let canned = rounds.isEmpty ? deltas : rounds.removeFirst()
        return AsyncThrowingStream { continuation in
            for delta in canned { continuation.yield(delta) }
            continuation.finish()
        }
    }
    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

final class ScriptedSecrets: SecretStore, @unchecked Sendable {
    var values: [SecretKey: String]
    /// 12c: a Keychain read can be a prompt; prewarm must not count one.
    var reads = 0
    init(_ values: [SecretKey: String] = [:]) { self.values = values }
    func read(_ key: SecretKey) throws -> String? {
        reads += 1
        return values[key]
    }
    func write(_ key: SecretKey, value: String) throws { values[key] = value }
    func delete(_ key: SecretKey) throws { values.removeValue(forKey: key) }
}

final class ScriptedThread: ConversationPresenting, @unchecked Sendable {
    // Locked: a background job writes the thread from its own task while the
    // voice writes it from the session; the bare arrays crashed the suite.
    private let lock = NSLock()
    private var _turns: [Turn] = [], _status: [String] = [], _stream = "", _finished = false
    private var _history: [Turn] = []
    var turns: [Turn] {
        get { lock.withLock { _turns } }
        set { lock.withLock { _turns = newValue } }
    }
    var status: [String] {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }
    var stream: String {
        get { lock.withLock { _stream } }
        set { lock.withLock { _stream = newValue } }
    }
    var finished: Bool {
        get { lock.withLock { _finished } }
        set { lock.withLock { _finished = newValue } }
    }
    /// Like the real presenter: `turns` is what gets painted (raw words),
    /// `history` is what the model sees next turn (compact context line).
    var history: [Turn] {
        get { lock.withLock { _history } }
        set { lock.withLock { _history = newValue } }
    }
    func historyTurns() async -> [Turn] { history }
    func memoryTurns() async -> [Turn] { turns }
    func appendUser(_ text: String) async {
        lock.withLock {
            _turns.append(Turn(role: .user, content: text))
            _history.append(Turn(role: .user, content: text))
        }
    }
    func appendUser(_ text: String, context: TurnContext?) async {
        let remembered = context.map { ContextBlock.compact($0, language: .en) + " " + text } ?? text
        lock.withLock {
            _turns.append(Turn(role: .user, content: text))
            _history.append(Turn(role: .user, content: remembered))
        }
    }
    func appendAssistant(_ text: String) async {
        lock.withLock {
            _turns.append(Turn(role: .assistant, content: text))
            _history.append(Turn(role: .assistant, content: text))
        }
    }
    func appendStatus(_ text: String) async { lock.withLock { _status.append(text) } }
    // Mirrors the REAL contract (ChatViewModel replaces): the old fake
    // accumulated, which is exactly why no test caught the flashing bubble.
    func showStream(_ text: String) async { stream = text }
    func finishStream() async { finished = true }
}
