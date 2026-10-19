import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The voice session's harness and scripted ports, shared by every voice
// test file; split out of VoiceSessionTests.swift to keep it under 800 lines.

package struct VoiceHarness {
    package let session: VoiceSession
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

@MainActor
package func makeVoiceHarness(
    key: String? = "sk-test",
    aec: Bool = false,
    online: Bool = true,
    jobs: (any JobSubmitter)? = nil,
    language: AppLanguage = .en,
    parentTools: (any ParentToolExecuting)? = nil,
    onJobEvent: (@Sendable (JobEvent) -> Void)? = nil,
    sensor: (any ContextSensing)? = nil,
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
    debugTranscripts: Bool = false
) -> VoiceHarness {
    let mic = ScriptedMic()
    mic.hasEchoCancellation = aec
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    var keys: [SecretKey: String] = [:]
    if let key { keys[.cerebras] = key }
    let secrets = ScriptedSecrets(keys)
    let thread = ScriptedThread()
    let clock = TestClock()
    let provider = StaticConfigProvider(
        Config(voice: VoiceSettings(mode: voiceMode), ownerFirstName: "Karen", language: language,
               debugTranscripts: debugTranscripts))
    let session = VoiceSession(
        mic: mic,
        player: player,
        transcriber: transcriber,
        synthesizer: synth,
        chat: chat,
        secrets: secrets,
        thread: thread,
        configProvider: provider,
        jobs: jobs,
        parentTools: parentTools,
        sensor: sensor,
        approvals: approvals,
        fieldProbe: fieldProbe,
        injector: injector,
        screen: screen,
        reachability: ScriptedReachability(online),
        releaseTail: releaseTail,
        now: { clock.now })
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
        session: session, mic: mic, player: player,
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
    private let restartHub = RestartHub()
    package func subscribeRestarts() -> AsyncStream<MicRestart> { restartHub.open() }
    package func emitRestart(_ event: MicRestart) { restartHub.yield(event) }
    /// Emitted from inside `start()`: a restart that lands while the session
    /// is still opening, before it could have been listening for it.
    package var restartsDuringStart: [MicRestart] = []
    /// `start()` emits `restartsDuringStart`, then suspends until
    /// `releaseStart()`: a restart that lands while the mic is still coming up,
    /// with the session's open provably parked on this await.
    private struct StartGate {
        var hold = false
        var waiter: CheckedContinuation<Void, Never>?
        var entered = false
        var released = false
    }
    private let startGate = LockedBox(StartGate())
    package var holdStart: Bool {
        get { startGate.withLock { $0.hold } }
        set { startGate.withLock { $0.hold = newValue } }
    }
    /// True once `start()` is parked on the gate with its waiter stored: only
    /// then can a test rely on `releaseStart()` finding someone to wake.
    package var startEntered: Bool { startGate.withLock { $0.entered } }
    /// Remembered when it lands before `start()` parks, so a release that wins
    /// the race can never leave `start()` suspended forever.
    package func releaseStart() {
        let waiter = startGate.withLock { g -> CheckedContinuation<Void, Never>? in
            g.released = true
            defer { g.waiter = nil }
            return g.waiter
        }
        waiter?.resume()
    }

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
        for event in restartsDuringStart { restartHub.yield(event) }
        if holdStart {
            await withCheckedContinuation { waiter in
                let alreadyReleased = startGate.withLock { g -> Bool in
                    g.entered = true
                    if g.released { return true }
                    g.waiter = waiter
                    return false
                }
                if alreadyReleased { waiter.resume() }
            }
        }
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

/// One live stream per subscription, like the real mic's feed: an event with
/// no subscriber is dropped, and a new subscriber replaces the old one.
private final class RestartHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<MicRestart>.Continuation?

    func open() -> AsyncStream<MicRestart> {
        let (stream, next) = AsyncStream.makeStream(of: MicRestart.self)
        let previous = lock.withLock { () -> AsyncStream<MicRestart>.Continuation? in
            defer { continuation = next }
            return continuation
        }
        previous?.finish()
        return stream
    }

    func yield(_ event: MicRestart) { lock.withLock { continuation }?.yield(event) }
}

package final class ScriptedPlayer: PCMPlaying, @unchecked Sendable {
    package init() {}

    @Guarded package var shared: Bool?
    /// Every `start`, in order: a restarted mic must re-attach the player.
    @Guarded package var sharedStarts: [Bool] = []
    @Guarded package var played: [Data] = []
    @Guarded package var flushed = false
    @Guarded package var stopped = false
    @Guarded package var hasPending = false
    @Guarded package var volumes: [Double] = []
    @Guarded package var position = PlaybackPosition.zero
    private let drainBox = StreamBox<Void>()
    private let levelBox = StreamBox<Double>()
    package var drained: AsyncStream<Void> { drainBox.stream }
    package var levels: AsyncStream<Double> { levelBox.stream }

    /// Thrown by every `start` after the first: the open succeeds, a re-attach
    /// onto a restarted mic's engine is what fails.
    package var startError: VoiceTransportError?
    package func start(sharedEngine: Bool) async throws {
        if let startError, !sharedStarts.isEmpty { throw startError }
        // Like the real player: a restart drops the queued audio and says so.
        if hasPending { yieldDrained() }
        shared = sharedEngine
        sharedStarts.append(sharedEngine)
    }
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
