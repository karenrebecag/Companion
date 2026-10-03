import Foundation

package struct MicFrame: Sendable, Equatable {
    package var pcm16le24k: Data
    package var rms: Double

    package init(pcm16le24k: Data, rms: Double) {
        self.pcm16le24k = pcm16le24k
        self.rms = rms
    }
}

package protocol VoiceTransport: Sendable {
    func open(key: String, url: URL) async throws
    func send(_ json: String) async throws
    func events() -> AsyncStream<RealtimeEvent>
    func close() async
}

package enum VoiceTransportError: Error, Sendable, Equatable {
    case timeout, unauthorized, closed, unreachable
}

package protocol MicCapturing: Sendable {
    func requestAccess() async -> Bool
    func start() async throws
    func stop() async
    func disableVoiceProcessing() async
    /// Build what the first start would build, without opening the mic
    /// or asking for it (Wave 12c). Default: nothing.
    func prewarm() async
    var frames: AsyncStream<MicFrame> { get }
    var hasEchoCancellation: Bool { get async }
    var receivedBuffer: Bool { get async }
}

extension MicCapturing {
    package func prewarm() async {}
}

package protocol PCMPlaying: Sendable {
    func start(sharedEngine: Bool) async throws
    func play(_ pcm16le24k: Data) async
    func flush() async
    func stop() async
    /// Live volume (0...1): the slider must not wait for an app relaunch.
    func setVolume(_ volume: Double) async
    /// What has been heard so far, for captions that follow the voice.
    var position: PlaybackPosition { get async }
    var hasPending: Bool { get async }
    var drained: AsyncStream<Void> { get }
    var levels: AsyncStream<Double> { get }
}

package protocol Transcriber: Sendable {
    func requestAuthorization() async -> Bool
    var isAuthorized: Bool { get async }
    func start(localeIdentifier: String) async throws
    func append(_ frame: MicFrame) async
    func stop() async -> String
    var partials: AsyncStream<String> { get }
    /// The transcript recognized so far this turn, read without halting — the
    /// turn logic reads it live to decide when speech has settled, then again
    /// to commit. A snapshot, so there is no single-pass stream to race on.
    var currentText: String { get }
}

/// What a segmenting ear says about turn boundaries (Wave 9j-1): the server's
/// VAD knows when the user STARTED speaking and hands each finished utterance
/// as final text — the client stops guessing with heuristics.
package enum EarTurnEvent: Sendable, Equatable {
    case speechStarted
    case finished(text: String)
}

/// An ear that detects turn boundaries itself. The session prefers these
/// events over its local endpointer when the ear provides them.
package protocol SegmentingTranscriber: Transcriber {
    var turnEvents: AsyncStream<EarTurnEvent> { get }
}

/// Wave 15f-5: the instants inside the mouth for the FIRST sentence of a
/// turn — the session stamps them on its own clock as they arrive, so a slow
/// voice reads apart as queue, network or player.
package enum SpeechMark: Sendable, Equatable {
    /// The first sentence reached the synthesizer.
    case firstCut
    /// Its TTS request left.
    case ttsRequest
    /// Its first PCM bytes came back.
    case firstByte
}

package enum SpeechEvent: Sendable, Equatable {
    case chunkStarted(text: String, duration: TimeInterval)
    case mark(SpeechMark)
    case level(Double)
    case finished
    case failed
}

package protocol SpeechSynthesizer: Sendable {
    func begin() async
    func enqueue(_ sentence: String) async
    func finish() async
    func stop() async
    func spokenSoFar() async -> String?
    var speakingNow: String { get async }
    var events: AsyncStream<SpeechEvent> { get }
    /// Wave 15b-3/4: whether `phrase` is already on disk, without fetching
    /// it — `AckPolicy` reads this to pick between the specific reply and
    /// the quick ack.
    func isCached(_ phrase: String) async -> Bool
    /// Fetches and stores each phrase in the background, never touching the
    /// speech queue or player: warming must never make a hold's own reply
    /// wait, and must never sound.
    func prewarm(_ phrases: [String]) async
    /// Opens a connection to the TTS endpoint ahead of the first phrase.
    func warmConnection() async
}

/// A synthesizer that does not implement warming (a test fake, or a future
/// port with nothing to warm) costs nothing extra: pressing a hold simply
/// finds these calls no-ops.
extension SpeechSynthesizer {
    package func isCached(_ phrase: String) async -> Bool { false }
    package func prewarm(_ phrases: [String]) async {}
    package func warmConnection() async {}
}

package struct VoiceLevels: Sendable, Equatable {
    package var mic: Double
    package var agent: Double

    package init(mic: Double, agent: Double) {
        self.mic = mic
        self.agent = agent
    }
}

package protocol VoiceControlling: Sendable {
    /// Applies mid-session; the server accepts speed changes but not voice.
    func setSpeed(_ speed: Double) async
    /// Playback volume, applied live to the local player.
    func setVolume(_ volume: Double) async
    func start() async
    func advance() async
    func hangUp() async
    func toggleMute() async
    func push(attachment: AttachmentRef) async
    /// Wave 12b: the hold. Press opens; release sends what was heard;
    /// discard closes without sending; interrupt cuts the agent.
    func hold() async
    /// FN on the way down: a press that may still turn out to be a tap.
    /// Only local work starts until `confirmHold` or the release.
    func holdProvisionally() async
    func confirmHold() async
    func release() async
    func discard() async
    func interrupt() async
    /// 16q-1 review: a request left the sheet; the session forgets it. Not
    /// defaulted: a default silently won the overload against the actor's own
    /// method and the call did nothing.
    func approvalClosed(requestId: String) async
    /// The request the sheet shows now, nil when empty. Not defaulted, for
    /// the same reason as `approvalClosed`.
    func approvalFront(requestId: String?) async
    var snapshots: AsyncStream<TurnSnapshot> { get }
    var levels: AsyncStream<VoiceLevels> { get }
    /// The spoken reply, word by word as it is heard (gap 2).
    var captions: AsyncStream<CaptionSnapshot> { get }
}

extension VoiceControlling {
    /// A voice without captions (the classic one, a test fake) shows the
    /// plain reply: an empty stream is the honest answer, not a missing one.
    package var captions: AsyncStream<CaptionSnapshot> { AsyncStream { $0.finish() } }
    package func hold() async {}
    package func holdProvisionally() async { await hold() }
    package func confirmHold() async {}
    package func release() async {}
    package func discard() async {}
    package func interrupt() async {}
}

/// Whether this Mac has a route to the internet. Lets the session tell "the
/// realtime server did not answer" (classic can still work) apart from "there
/// is no network" (nothing remote will work).
package protocol ReachabilityProbing: Sendable {
    var isOnline: Bool { get async }
}


/// Plays a short sample so settings can preview a voice. Deliberately separate
/// from VoiceTransport: a preview must never touch a live realtime session or
/// the microphone graph (see docs/REFERENCE.md, audio section).
package protocol VoiceSampling: Sendable {
    func play(_ text: String, voice: VoiceID) async throws
}

/// How the user can interrupt the agent, decided by the audio path. The UI
/// adapts to it: an explicit button when talking over is impossible, a clean
/// flow when the mic can hear the user during playback.
package enum InterruptCapability: Sendable, Equatable {
    /// Echo-free output (headphones) or working AEC: talk over the agent.
    case voiceAndTap
    /// Speakers without echo cancellation: only the tap interrupts.
    case tapOnly

    package static func decide(echoFreeOutput: Bool, aecActive: Bool) -> Self {
        (echoFreeOutput || aecActive) ? .voiceAndTap : .tapOnly
    }
}

/// Observes the audio output route so the UI can adapt live when the user
/// plugs or unplugs headphones.
package protocol OutputRouteObserving: Sendable {
    /// Emits the current echo-free state on subscription and on every change.
    var echoFreeUpdates: AsyncStream<Bool> { get }
}
