import Foundation

public struct MicFrame: Sendable, Equatable {
    public var pcm16le24k: Data
    public var rms: Double

    public init(pcm16le24k: Data, rms: Double) {
        self.pcm16le24k = pcm16le24k
        self.rms = rms
    }
}

public protocol VoiceTransport: Sendable {
    func open(key: String, url: URL) async throws
    func send(_ json: String) async throws
    func events() -> AsyncStream<RealtimeEvent>
    func close() async
}

public enum VoiceTransportError: Error, Sendable, Equatable {
    case timeout, unauthorized, closed, unreachable
}

public protocol MicCapturing: Sendable {
    func requestAccess() async -> Bool
    func start() async throws
    func stop() async
    func disableVoiceProcessing() async
    var frames: AsyncStream<MicFrame> { get }
    var hasEchoCancellation: Bool { get async }
    var receivedBuffer: Bool { get async }
}

public protocol PCMPlaying: Sendable {
    func start(sharedEngine: Bool) async throws
    func play(_ pcm16le24k: Data) async
    func flush() async
    func stop() async
    var hasPending: Bool { get async }
    var drained: AsyncStream<Void> { get }
    var levels: AsyncStream<Double> { get }
}

public protocol Transcriber: Sendable {
    func requestAuthorization() async -> Bool
    var isAuthorized: Bool { get async }
    func start(localeIdentifier: String) async throws
    func append(_ frame: MicFrame) async
    func stop() async -> String
    var partials: AsyncStream<String> { get }
}

public enum SpeechEvent: Sendable, Equatable {
    case chunkStarted(text: String, duration: TimeInterval)
    case level(Double)
    case finished
    case failed
}

public protocol SpeechSynthesizer: Sendable {
    func begin() async
    func enqueue(_ sentence: String) async
    func finish() async
    func stop() async
    func spokenSoFar() async -> String?
    var speakingNow: String { get async }
    var events: AsyncStream<SpeechEvent> { get }
}

public struct VoiceLevels: Sendable, Equatable {
    public var mic: Double
    public var agent: Double

    public init(mic: Double, agent: Double) {
        self.mic = mic
        self.agent = agent
    }
}

public protocol VoiceControlling: Sendable {
    /// Applies mid-session; the server accepts speed changes but not voice.
    func setSpeed(_ speed: Double) async
    func start() async
    func advance() async
    func hangUp() async
    func toggleMute() async
    var snapshots: AsyncStream<TurnSnapshot> { get }
    var levels: AsyncStream<VoiceLevels> { get }
}

/// Whether this Mac has a route to the internet. Lets the session tell "the
/// realtime server did not answer" (classic can still work) apart from "there
/// is no network" (nothing remote will work).
public protocol ReachabilityProbing: Sendable {
    var isOnline: Bool { get async }
}


/// Plays a short sample so settings can preview a voice. Deliberately separate
/// from VoiceTransport: a preview must never touch a live realtime session or
/// the microphone graph (see docs/REFERENCE.md, audio section).
public protocol VoiceSampling: Sendable {
    func play(_ text: String, voice: VoiceID) async throws
}
