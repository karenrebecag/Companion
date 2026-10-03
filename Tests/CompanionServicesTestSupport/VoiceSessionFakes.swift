import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The voice session's harness and scripted ports, shared by every voice
// test file; split out of VoiceSessionTests.swift to keep it under 800 lines.

package struct VoiceHarness {
    package let session: VoiceSession
    package let transport: ScriptedVoiceTransport
    package let mic: ScriptedMic
    package let player: ScriptedPlayer
    package let transcriber: ScriptedTranscriber
    package let thread: ScriptedThread
    package let clock: TestClock
    package let watch: SnapWatch
    package let synth: ScriptedSynth
    package let chat: ScriptedChat
    package let secrets: ScriptedSecrets
}

private struct ScriptedReachability: ReachabilityProbing {
    let online: Bool
    init(_ online: Bool) { self.online = online }
    var isOnline: Bool { get async { online } }
}

/// The scripted transport delivers its ready events or never does, so the
/// handshake budget has nothing to measure here except how starved the test
/// process is. A 1 s budget made a loaded `gates.sh` fall back to classic
/// mid-start (`.listening + .realtime` never came). Tests of the timeout
/// itself pass their own small value.
///
/// Trap: a harness with empty `autoEvents` never gets ready, so with this
/// default `session.start()` blocks for 10 minutes. Whoever expects the
/// timeout must pass an explicit small `readyTimeout`.
package let harnessReadyTimeout: TimeInterval = 600

@MainActor
package func makeVoiceHarness(
    key: String? = "sk-test",
    // Empty means never ready: pair it with an explicit small `readyTimeout`
    // if the test expects the handshake to give up (see `harnessReadyTimeout`).
    autoEvents: [RealtimeEvent] = [.sessionCreated, .sessionUpdated],
    readyTimeout: TimeInterval = harnessReadyTimeout,
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
    session sessionModel: (any SessionEventSink)? = nil,
    // Wave 12e: where a hold may dictate instead of talking.
    voiceMode: VoiceMode = .automatic,
    fieldProbe: (any FocusedFieldProbing)? = nil,
    injector: (any TextInjecting)? = nil,
    // 15d-2: zero keeps every older test's release instantaneous; the
    // tail's own tests pass it explicitly.
    releaseTail: TimeInterval = 0,
    screen: (any ScreenSeeing)? = nil,
    debugTranscripts: Bool = false,
    turnDetection: TurnDetection = .serverVAD(silenceMs: 700)
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
        Config(voice: VoiceSettings(turnDetection: turnDetection, mode: voiceMode), ownerFirstName: "Karen", language: language,
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
package final class StaticConfigProvider: ConfigProviding, @unchecked Sendable {
    private let config: Config
    package init(_ config: Config) { self.config = config }
    package var current: Config { config }
}

package final class TestClock: @unchecked Sendable {
    @Guarded package var now: TimeInterval = 0
}

package final class SnapWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var latestValue = TurnSnapshot.idle

    package var latest: TurnSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return latestValue
    }

    package init(_ stream: AsyncStream<TurnSnapshot>) {
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

package final class ScriptedVoiceTransport: VoiceTransport, @unchecked Sendable {
    package init() {}

    private struct State {
        var key: String?, url: URL?, sent: [String] = [], closed = false
        var openError: VoiceTransportError?
        var autoEvents: [RealtimeEvent] = []
        var openCount = 0
        var box = StreamBox<RealtimeEvent>()
        var streamEnded = false
        var holdNextOpen = false
        var openWaiter: CheckedContinuation<Void, Never>?
        var openEntered = false
        var sendFails = false
        var sendAttempts = 0
        var holdSendMatching: (@Sendable (String) -> Bool)?
        var sendWaiter: CheckedContinuation<Void, Never>?
        var sendHeld = false
        var closeCount = 0
        var openReturned = 0
    }
    private let state = LockedBox(State())

    package var key: String? { state.withLock { $0.key } }
    package var url: URL? { state.withLock { $0.url } }
    package var sent: [String] { state.withLock { $0.sent } }
    package var closed: Bool { state.withLock { $0.closed } }
    package var closeCount: Int { state.withLock { $0.closeCount } }
    /// Opens that have come back, by success or by throw: the signal that a
    /// reconnect held in `open` has resumed and is about to act.
    package var openReturned: Int { state.withLock { $0.openReturned } }
    /// Every `send` that reached the transport, failed or not: what a
    /// paused runtime must stop producing.
    package var sendAttempts: Int { state.withLock { $0.sendAttempts } }
    package var sendFails: Bool {
        get { state.withLock { $0.sendFails } }
        set { state.withLock { $0.sendFails = newValue } }
    }
    /// The next `open` suspends after counting itself until `releaseOpen()`,
    /// so a test can act while a reconnect is half-way through.
    package var holdNextOpen: Bool {
        get { state.withLock { $0.holdNextOpen } }
        set { state.withLock { $0.holdNextOpen = newValue } }
    }
    package var openEntered: Bool { state.withLock { $0.openEntered } }
    package func releaseOpen() {
        let waiter = state.withLock { s -> CheckedContinuation<Void, Never>? in
            defer { s.openWaiter = nil }
            return s.openWaiter
        }
        waiter?.resume()
    }
    package var openCount: Int { state.withLock { $0.openCount } }
    package var openError: VoiceTransportError? {
        get { state.withLock { $0.openError } }
        set { state.withLock { $0.openError = newValue } }
    }
    package var autoEvents: [RealtimeEvent] {
        get { state.withLock { $0.autoEvents } }
        set { state.withLock { $0.autoEvents = newValue } }
    }

    package func open(key: String, url: URL) async throws {
        defer { state.withLock { $0.openReturned += 1 } }
        // A fresh stream per open once the last one ended, like the real
        // EventPipe: reusing a finished one would drop the new connection's
        // events and hide a pump that never restarted.
        let (events, box, hold): ([RealtimeEvent], StreamBox<RealtimeEvent>, Bool) = try state.withLock { s in
            if let error = s.openError { throw error }
            s.openCount += 1
            (s.key, s.url) = (key, url)
            if s.streamEnded {
                s.box = StreamBox()
                s.streamEnded = false
            }
            defer { s.holdNextOpen = false }
            return (s.autoEvents, s.box, s.holdNextOpen)
        }
        if hold {
            await withCheckedContinuation { waiter in
                state.withLock { s in
                    s.openWaiter = waiter
                    s.openEntered = true
                }
            }
        }
        for event in events { box.yield(event) }
    }

    /// The first frame matching `predicate` suspends before it lands in
    /// `sent` until `releaseSend()`, so a test can let a later frame overtake
    /// it: the crossing the scheduler only produces sometimes.
    package func holdSend(matching predicate: @escaping @Sendable (String) -> Bool) {
        state.withLock { $0.holdSendMatching = predicate }
    }
    package var sendHeld: Bool { state.withLock { $0.sendHeld } }
    package func releaseSend() {
        let waiter = state.withLock { s -> CheckedContinuation<Void, Never>? in
            defer { s.sendWaiter = nil }
            return s.sendWaiter
        }
        waiter?.resume()
    }

    package func send(_ json: String) async throws {
        let hold = try state.withLock { s -> Bool in
            s.sendAttempts += 1
            if s.sendFails { throw VoiceTransportError.unreachable }
            guard let matches = s.holdSendMatching, matches(json) else {
                s.sent.append(json)
                return false
            }
            s.holdSendMatching = nil
            return true
        }
        guard hold else { return }
        await withCheckedContinuation { waiter in
            state.withLock { s in
                s.sendWaiter = waiter
                s.sendHeld = true
            }
        }
        state.withLock { $0.sent.append(json) }
    }
    package func events() -> AsyncStream<RealtimeEvent> { state.withLock { $0.box.stream } }
    package func close() async {
        state.withLock { s in
            s.closed = true
            s.closeCount += 1
        }
    }
    package func yield(_ event: RealtimeEvent) { state.withLock { $0.box }.yield(event) }

    /// Simulate transport pump receiving an error and failing.
    package func simulateReceiveFailure() async {
        await Task.yield()
        endStream()
    }

    /// Simulate stream ending without explicit close (abrupt termination).
    package func simulateStreamEnd() async {
        await Task.yield()
        endStream()
    }

    private func endStream() {
        let box = state.withLock { s in
            s.streamEnded = true
            return s.box
        }
        box.finish()
    }
}

package final class ScriptedMic: MicCapturing, @unchecked Sendable {
    package init() {}

    package var granted = true
    @Guarded package var started = false
    @Guarded package var stopped = false
    @Guarded package var prewarmed = false
    @Guarded package var accessAsked = false
    @Guarded package var hasEchoCancellation = false
    /// How many times `start()` ran, and whether one of those ran while the
    /// previous session was still live (no `stop()` in between) — the shape
    /// of the real MicCapture crash (double `installTap`, live 2026-09-23).
    @Guarded package var startCount = 0
    @Guarded package var startedWithoutStop = false
    @Guarded package var receivedBufferValue = true
    /// Seconds `receivedBuffer` takes to answer: the only way a test can
    /// slip a call into the session's suspension points.
    package var receivedBufferDelay: TimeInterval = 0
    package var receivedBuffer: Bool {
        get async {
            if receivedBufferDelay > 0 {
                try? await Task.sleep(for: .seconds(receivedBufferDelay))
            }
            return receivedBufferValue
        }
    }
    package var startError: VoiceTransportError?
    private let box = StreamBox<MicFrame>()
    package var frames: AsyncStream<MicFrame> { box.stream }

    package func requestAccess() async -> Bool {
        accessAsked = true
        return granted
    }
    package func prewarm() async { prewarmed = true }
    /// Seconds `start()` takes: lets a test land a release or a discard
    /// while the mic is still coming up.
    package var startDelay: TimeInterval = 0
    package func start() async throws {
        if startDelay > 0 { try? await Task.sleep(for: .seconds(startDelay)) }
        if let startError { throw startError }
        if started, !stopped { startedWithoutStop = true }
        started = true
        stopped = false
        startCount += 1
    }
    package func stop() async { stopped = true }
    package func disableVoiceProcessing() async { hasEchoCancellation = false }
    package func yield(_ frame: MicFrame) {
        receivedBufferValue = true
        box.yield(frame)
    }
}

package final class ScriptedPlayer: PCMPlaying, @unchecked Sendable {
    package init() {}

    @Guarded package var shared: Bool?
    @Guarded package var played: [Data] = []
    @Guarded package var flushed = false
    @Guarded package var stopped = false
    @Guarded package var hasPending = false
    @Guarded package var volumes: [Double] = []
    private let drainBox = StreamBox<Void>()
    private let levelBox = StreamBox<Double>()
    package var drained: AsyncStream<Void> { drainBox.stream }
    package var levels: AsyncStream<Double> { levelBox.stream }

    package func start(sharedEngine: Bool) async throws { shared = sharedEngine }
    package func play(_ pcm16le24k: Data) async {
        played.append(pcm16le24k)
        hasPending = true
    }
    package func flush() async {
        flushed = true
        hasPending = false
        drainBox.yield(())
    }
    package func stop() async { stopped = true }
    package func setVolume(_ volume: Double) async { volumes.append(volume) }
    package func yieldDrained() {
        hasPending = false
        drainBox.yield(())
    }
}

package final class ScriptedTranscriber: Transcriber, @unchecked Sendable {
    package init() {}

    @Guarded package var authorized = false
    @Guarded package var locale = ""
    @Guarded package var started = false
    @Guarded package var stoppedText = ""
    @Guarded package var grantsAuthorization = true
    @Guarded package var stops = 0
    @Guarded package var appended: [MicFrame] = []
    package var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    package var partials: AsyncStream<String> { box.stream }
    package var currentText: String { stoppedText }

    /// Seconds the speech prompt takes to answer.
    @Guarded package var authorizationDelay: TimeInterval = 0
    package func requestAuthorization() async -> Bool {
        let delay = authorizationDelay
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        authorized = grantsAuthorization
        return authorized
    }
    /// Seconds the on-device ear takes to come up after the mic.
    @Guarded package var startDelay: TimeInterval = 0
    package func start(localeIdentifier: String) async throws {
        let delay = startDelay
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        locale = localeIdentifier
        started = true
        running = true
    }
    /// Like `AnalyzerTranscriber`, which drops a frame while it has no
    /// live run: audio that reaches the ear before `start()` returned is
    /// lost, so only the early-audio path can deliver it.
    package func append(_ frame: MicFrame) async {
        guard running else { return }
        appended.append(frame)
    }
    @Guarded package var clearOnStop = false
    /// Seconds `stop()` waits for the recognizer's final, like the real
    /// ear's `TranscriptFinalizer` bound; `running` goes false only after
    /// it, the way the real `halt()` kills whatever recognition is live
    /// by then — including one a newer hold started meanwhile.
    @Guarded package var stopDelay: TimeInterval = 0
    /// Per-call delays, consumed in order before `stopDelay` applies: a
    /// slow first stop followed by an instant one.
    private let stopDelayQueue = LockedBox<[TimeInterval]>([])
    package var stopDelays: [TimeInterval] {
        get { stopDelayQueue.value }
        set { stopDelayQueue.value = newValue }
    }
    @Guarded package private(set) var running = false
    package func stop() async -> String {
        stops += 1
        let text = stoppedText
        // The emptiness check and the pop share one lock: overlapping stops
        // must not both take the same entry or pop an empty list.
        let queued = stopDelayQueue.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        let delay = queued ?? stopDelay
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        running = false
        if clearOnStop { stoppedText = "" }
        return text
    }
    /// 12c: a new hypothesis from the ear; `currentText` follows it.
    package func yieldPartial(_ text: String) {
        stoppedText = text
        box.yield(text)
    }
}

/// A segmenting ear (9j-1): the server's VAD decides the turns and hands
/// each finished utterance as final text.
package final class ScriptedSegmentingEar: SegmentingTranscriber, @unchecked Sendable {
    package init() {}

    package var authorized = true, locale = "", started = false, stoppedText = ""
    package var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    private let turns = StreamBox<EarTurnEvent>()
    package var partials: AsyncStream<String> { box.stream }
    package var turnEvents: AsyncStream<EarTurnEvent> { turns.stream }
    package var currentText: String { stoppedText }

    package func requestAuthorization() async -> Bool { authorized }
    package func start(localeIdentifier: String) async throws {
        locale = localeIdentifier
        started = true
    }
    package func append(_ frame: MicFrame) async {}
    package func stop() async -> String { stoppedText }
    package func yieldTurn(_ event: EarTurnEvent) { turns.yield(event) }
}

package final class ScriptedSynth: SpeechSynthesizer, @unchecked Sendable {
    package init() {}

    @Guarded package var began = false
    @Guarded package var finished = false
    @Guarded package var stopped = false
    @Guarded package var spoken: String?
    @Guarded package var speakingNow = ""
    /// Written from the runtime's task, read from the test's: behind a lock
    /// so a read from any task is never a race (review 16h-2 L3).
    private let lock = NSLock()
    private var sentences: [String] = []
    package var queue: [String] { lock.withLock { sentences } }
    private let box = StreamBox<SpeechEvent>()
    package var events: AsyncStream<SpeechEvent> { box.stream }
    package func begin() async { began = true }
    package func enqueue(_ sentence: String) async { lock.withLock { sentences.append(sentence) } }
    package func finish() async { finished = true }
    package func stop() async { stopped = true }
    package func spokenSoFar() async -> String? { spoken }
    package func yield(_ event: SpeechEvent) { box.yield(event) }
}

package final class ScriptedChat: ChatProvider, @unchecked Sendable {
    package init() {}

    package var deltas: [ChatDelta] = []
    /// Wave 10b: una lista por ronda; vacía, se repite `deltas` como antes.
    @Guarded package var rounds: [[ChatDelta]] = []
    @Guarded package private(set) var histories: [[Turn]] = []
    @Guarded package private(set) var toolsSeen: [ToolSpec] = []
    /// HIGH-B: a job's end streams again (the summary), so the hold's own
    /// tools are the first entry, not the last.
    @Guarded package private(set) var toolsPerCall: [[ToolSpec]] = []
    package func stream(_ history: [Turn], tools: [ToolSpec])
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
    package func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}

package final class ScriptedSecrets: SecretStore, @unchecked Sendable {
    // Locked: a mouth drops a key from the synthesis task while the router
    // and the test read the store from theirs (same shape TSan caught in
    // the synthesis doubles).
    private let lock = NSLock()
    private var _values: [SecretKey: String]
    private var _reads = 0
    package var values: [SecretKey: String] {
        get { lock.withLock { _values } }
        set { lock.withLock { _values = newValue } }
    }
    /// 12c: a Keychain read can be a prompt; prewarm must not count one.
    package var reads: Int {
        get { lock.withLock { _reads } }
        set { lock.withLock { _reads = newValue } }
    }
    package init(_ values: [SecretKey: String] = [:]) { self._values = values }
    package func read(_ key: SecretKey) throws -> String? {
        lock.withLock {
            _reads += 1
            return _values[key]
        }
    }
    package func write(_ key: SecretKey, value: String) throws { lock.withLock { _values[key] = value } }
    package func delete(_ key: SecretKey) throws { lock.withLock { _ = _values.removeValue(forKey: key) } }
}

package final class ScriptedThread: ConversationPresenting, @unchecked Sendable {
    package init() {}

    // Locked: a background job writes the thread from its own task while the
    // voice writes it from the session; the bare arrays crashed the suite.
    private let lock = NSLock()
    private var _turns: [Turn] = [], _status: [String] = [], _stream = "", _finished = false
    private var _history: [Turn] = []
    package var turns: [Turn] {
        get { lock.withLock { _turns } }
        set { lock.withLock { _turns = newValue } }
    }
    package var status: [String] {
        get { lock.withLock { _status } }
        set { lock.withLock { _status = newValue } }
    }
    package var stream: String {
        get { lock.withLock { _stream } }
        set { lock.withLock { _stream = newValue } }
    }
    package var finished: Bool {
        get { lock.withLock { _finished } }
        set { lock.withLock { _finished = newValue } }
    }
    /// Like the real presenter: `turns` is what gets painted (raw words),
    /// `history` is what the model sees next turn (compact context line).
    package var history: [Turn] {
        get { lock.withLock { _history } }
        set { lock.withLock { _history = newValue } }
    }
    package func historyTurns() async -> [Turn] { history }
    package func memoryTurns() async -> [Turn] { turns }
    package func appendUser(_ text: String) async {
        lock.withLock {
            _turns.append(Turn(role: .user, content: text))
            _history.append(Turn(role: .user, content: text))
        }
    }
    package func appendUser(_ text: String, context: TurnContext?) async {
        let remembered = context.map { ContextBlock.compact($0, language: .en) + " " + text } ?? text
        lock.withLock {
            _turns.append(Turn(role: .user, content: text))
            _history.append(Turn(role: .user, content: remembered))
        }
    }
    /// Holds only the next `appendAssistant` and is spent by it, so a reply
    /// after the held one never blocks a test that forgets to open the gate.
    package var nextAssistantGate: TestGate? {
        get { lock.withLock { _nextAssistantGate } }
        set { lock.withLock { _nextAssistantGate = newValue } }
    }
    private var _nextAssistantGate: TestGate?
    package func appendAssistant(_ text: String) async {
        let gate = lock.withLock {
            defer { _nextAssistantGate = nil }
            return _nextAssistantGate
        }
        await gate?.wait()
        // A held append honours its caller's cancellation, as a presenter is
        // allowed to: an append made inline in a cancelled caller is lost.
        if gate != nil, Task.isCancelled { return }
        lock.withLock {
            _turns.append(Turn(role: .assistant, content: text))
            _history.append(Turn(role: .assistant, content: text))
        }
    }
    package func appendStatus(_ text: String) async { lock.withLock { _status.append(text) } }
    // Mirrors the REAL contract (ChatViewModel replaces): the old fake
    // accumulated, which is exactly why no test caught the flashing bubble.
    package func showStream(_ text: String) async { stream = text }
    package func finishStream() async { finished = true }
}
