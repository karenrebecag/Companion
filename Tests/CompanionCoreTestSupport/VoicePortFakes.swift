import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@MainActor package func expectThrow(
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

package final class FakeTransport: VoiceTransport, @unchecked Sendable {
    package init() {}
    package var key: String?, url: URL?, sent: [String] = [], closed = false
    package var openError: VoiceTransportError?, sendError: VoiceTransportError?
    private let box = StreamBox<RealtimeEvent>()
    package func open(key: String, url: URL) async throws {
        if let openError { throw openError }
        (self.key, self.url) = (key, url)
    }
    package func send(_ json: String) async throws { if let sendError { throw sendError }; sent.append(json) }
    package func events() -> AsyncStream<RealtimeEvent> { box.stream }
    package func close() async { closed = true; box.finish() }
    package func yield(_ event: RealtimeEvent) { box.yield(event) }
}

package final class FakeMic: MicCapturing, @unchecked Sendable {
    package init() {}
    package var granted = true, started = false, stopped = false, vpDisabled = false
    package var startError: VoiceTransportError?
    package var hasEchoCancellation = false, receivedBuffer = false
    private let box = StreamBox<MicFrame>()
    package var frames: AsyncStream<MicFrame> { box.stream }
    package func requestAccess() async -> Bool { granted }
    package func start() async throws { if let startError { throw startError }; started = true }
    package func stop() async { stopped = true; box.finish() }
    package func disableVoiceProcessing() async { vpDisabled = true }
    package func yield(_ frame: MicFrame) { receivedBuffer = true; box.yield(frame) }
}

package final class FakePlayer: PCMPlaying, @unchecked Sendable {
    package init() {}
    package var shared: Bool?, played: [Data] = []
    package var flushed = false, stopped = false, hasPending = false
    private let drainBox = StreamBox<Void>()
    private let levelBox = StreamBox<Double>()
    package var drained: AsyncStream<Void> { drainBox.stream }
    package var levels: AsyncStream<Double> { levelBox.stream }
    package func start(sharedEngine: Bool) async throws { shared = sharedEngine }
    package func play(_ pcm16le24k: Data) async { played.append(pcm16le24k); hasPending = true }
    package func flush() async { flushed = true; hasPending = false; drainBox.yield(()) }
    package func stop() async { stopped = true; drainBox.finish(); levelBox.finish() }
    package func setVolume(_ volume: Double) async {}
    package func yieldLevel(_ value: Double) { levelBox.yield(value) }
}

package final class FakeTranscriber: Transcriber, @unchecked Sendable {
    package init() {}
    // The runtime calls this from detached tasks and the stop queue while the
    // test rewrites stoppedText between turns.
    private let lock = NSLock()
    private var _authorized = false, _locale = "", _stoppedText = ""
    private var _appended: [MicFrame] = []
    package var authorized: Bool {
        get { lock.withLock { _authorized } }
        set { lock.withLock { _authorized = newValue } }
    }
    package var locale: String {
        get { lock.withLock { _locale } }
        set { lock.withLock { _locale = newValue } }
    }
    package var stoppedText: String {
        get { lock.withLock { _stoppedText } }
        set { lock.withLock { _stoppedText = newValue } }
    }
    package var appended: [MicFrame] {
        get { lock.withLock { _appended } }
        set { lock.withLock { _appended = newValue } }
    }
    package var isAuthorized: Bool { authorized }
    private let box = StreamBox<String>()
    package var partials: AsyncStream<String> { box.stream }
    package var currentText: String { stoppedText }
    package func requestAuthorization() async -> Bool { lock.withLock { _authorized = true; return _authorized } }
    package func start(localeIdentifier: String) async throws { locale = localeIdentifier }
    package func append(_ frame: MicFrame) async { lock.withLock { _appended.append(frame) } }
    package func stop() async -> String { box.finish(); return stoppedText }
    package func yieldPartial(_ text: String) { box.yield(text) }
}

package final class FakeSpeech: SpeechSynthesizer, @unchecked Sendable {
    package init() {}
    package var began = false, finished = false, stopped = false
    package var queue: [String] = [], spoken: String?, speakingNow = ""
    private let box = StreamBox<SpeechEvent>()
    package var events: AsyncStream<SpeechEvent> { box.stream }
    package func begin() async { began = true }
    package func enqueue(_ sentence: String) async { queue.append(sentence) }
    package func finish() async { finished = true }
    package func stop() async { stopped = true; box.finish() }
    package func spokenSoFar() async -> String? { spoken }
    package func yield(_ event: SpeechEvent) { box.yield(event) }
}

package final class FakeVoice: VoiceControlling, @unchecked Sendable {
    package init() {}
    package private(set) var speeds: [Double] = []
    package func setSpeed(_ speed: Double) async { speeds.append(speed) }
    package func setVolume(_ volume: Double) async {}

    package var started = false, advanced = false, hungUp = false, muted = false
    private let snapBox = StreamBox<TurnSnapshot>()
    private let levelBox = StreamBox<VoiceLevels>()
    package var snapshots: AsyncStream<TurnSnapshot> { snapBox.stream }
    package var levels: AsyncStream<VoiceLevels> { levelBox.stream }
    package func start() async { started = true }
    package func advance() async { advanced = true }
    package func hangUp() async { hungUp = true; snapBox.finish(); levelBox.finish() }
    package func toggleMute() async { muted.toggle() }
    package func push(attachment: AttachmentRef) async { pushed.append(attachment) }
    package func approvalClosed(requestId: String) async {}
    package func approvalFront(requestId: String?) async {}
    package var pushed: [AttachmentRef] = []
    package func yieldSnapshot(_ snapshot: TurnSnapshot) { snapBox.yield(snapshot) }
    package func yieldLevels(_ value: VoiceLevels) { levelBox.yield(value) }
}

package final class FakePresenter: ConversationPresenting, @unchecked Sendable {
    package init() {}
    // appendStatus runs on the global executor while the view-model tests poll
    // `status` from the main actor.
    private let lock = NSLock()
    private var _turns: [Turn] = [], _status: [String] = [], _stream = "", _finished = false
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
    package func historyTurns() async -> [Turn] { turns }
    package func appendUser(_ text: String) async { lock.withLock { _turns.append(Turn(role: .user, content: text)) } }
    package func appendAssistant(_ text: String) async {
        lock.withLock { _turns.append(Turn(role: .assistant, content: text)) }
    }
    package func appendStatus(_ text: String) async { lock.withLock { _status.append(text) } }
    package func showStream(_ text: String) async { stream = text }
    package func finishStream() async { finished = true }
}
