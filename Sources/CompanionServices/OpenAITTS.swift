@preconcurrency import AVFoundation
import CompanionCore
import Foundation

public struct OpenAITTSClient: TTSFetching, Sendable {
    private static let model = "gpt-4o-mini-tts"
    /// Wave 15f-5 (spec §2): brisker than the API's 1.0, what Incredible's
    /// mouth runs at. Injectable: the voice bench confirms the final value.
    public static let defaultSpeed = 1.1

    private let secrets: any SecretStore
    private let transport: any ChatTransport
    private let speed: Double
    private let instructions: String

    /// No default language on purpose, as `AVSpeechFallback`: a call site
    /// that forgot it would speak Spanish style notes to an English reply.
    public init(
        secrets: any SecretStore, transport: any ChatTransport,
        language: AppLanguage, speed: Double = OpenAITTSClient.defaultSpeed,
        instructions: String? = nil
    ) {
        self.secrets = secrets
        self.transport = transport
        self.speed = speed
        self.instructions = instructions ?? Self.defaultInstructions(language)
    }

    public static func defaultInstructions(_ language: AppLanguage) -> String {
        switch language {
        case .es:
            "Habla en español de México, conversacional, ágil y natural, sin pausas teatrales."
        case .en:
            "Speak in American English, conversational, brisk and natural, with no theatrical pauses."
        }
    }

    /// Audio cached under one style must never be replayed under another,
    /// so the key carries everything that changes the sound. Instructions
    /// go in hashed: the key names a file on disk.
    public func cacheVariant(voice: VoiceID) -> String {
        "\(Self.model)|\(voice.rawValue)|\(speed)|\(PhraseCache.fnv1a(instructions))"
    }

    /// Non-streaming: only `prewarm` calls this, in the background, never on
    /// the turn the user is waiting on — no reason to pay the extra plumbing
    /// a live hold needs (see `stream` below).
    public func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        let request = try makeRequest(text, voice: voice)
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200, !data.isEmpty else {
            throw ChatError.httpStatus(response.statusCode)
        }
        return data
    }

    /// Wave 15c-5: the same audio as `fetch`, delivered as PCM chunks as
    /// they arrive — `SpeechSynthesis` schedules each one instead of
    /// waiting for the whole sentence to download.
    public func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(text, voice: voice)
                    let (status, bytes) = try await transport.bytes(for: request)
                    guard status == 200 else { throw ChatError.httpStatus(status) }
                    for try await chunk in bytes {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(_ text: String, voice: VoiceID) throws -> URLRequest {
        let key = (try secrets.read(.openAI))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw ChatError.invalidKey }
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech")
        else { throw ChatError.unreachable }
        guard EndpointPolicy.isAcceptable(url) else { throw ChatError.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 24 kHz 16-bit little-endian mono, headerless — the same shape the
        // rest of the app already speaks (`RealtimePlayer`, `MicCapture`).
        let body: [String: Any] = [
            "model": Self.model,
            "input": text,
            "voice": voice.rawValue,
            "response_format": "pcm",
            "speed": speed,
            "instructions": instructions,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Wave 15b-4: a TLS handshake paid for at press instead of on the turn
    /// the user is waiting on. No key and no body on purpose — a connection
    /// probe, not a request: reading the Keychain here would defeat the
    /// constraint that the key is only ever read at press (`hold()` already
    /// does that), and the models endpoint needs no credential to answer.
    public func warm() async {
        guard let url = URL(string: "https://api.openai.com/v1/models"),
              EndpointPolicy.isAcceptable(url)
        else { return }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        let start = DispatchTime.now()
        do {
            _ = try await transport.data(for: request)
        } catch {
            // Best-effort probe: a failed warm-up is not a failed hold.
        }
        let ms = (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        Log.app("tts: warm \(ms) ms")
    }
}

/// Wave 15c-5: schedules PCM16LE 24 kHz mono onto its own `AVAudioEngine` as
/// it arrives, instead of `AVAudioPlayer`, which needs a whole file up
/// front — the old mp3 download-then-play. Its own engine, never the mic's
/// shared one (`RealtimePlayer`): a hold's TTS is not realtime voice and
/// must not fight AEC for the graph. One instance lives for the app's whole
/// session (wired once in `CompanionMain`), so the engine is built once and
/// just re-armed between sentences.
public actor DataSpeechPlayback: SpeechPlayback {
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false)!

    private let graph = StreamGraph()
    private var stopped = false
    private var epoch = 0
    private var pendingBuffers = 0
    private var drainWaiter: CheckedContinuation<Void, Never>?
    /// The task actually running `for try await chunk in chunks` — `stop()`
    /// cancels this one directly (the pattern `ChatSSEAttempt` already uses)
    /// rather than hoping cancellation travels on its own through a stream
    /// assembled elsewhere.
    private var consumer: Task<Data, Error>?

    public init() {}

    public func play(_ data: Data) async throws {
        _ = try await play(Self.oneShot(data))
    }

    /// Returns everything actually scheduled — a `stop()` mid-stream leaves
    /// this short of the full sentence, which is exactly the signal
    /// `SpeechSynthesis` needs to skip caching a partial.
    public func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data {
        stopped = false
        epoch += 1
        let myEpoch = epoch
        try start()
        let task = Task { () throws -> Data in
            var assembled = Data()
            var carry = Data()
            for try await chunk in chunks {
                assembled.append(chunk)
                carry.append(chunk)
                // A chunk boundary can land inside a 16-bit sample; hold the
                // odd trailing byte for the next chunk instead of feeding a
                // half-sample to the engine.
                let usable = carry.count - (carry.count % 2)
                guard usable > 0 else { continue }
                let frame = Data(carry.prefix(usable))
                carry = Data(carry.suffix(from: usable))
                self.schedule(frame, epoch: myEpoch)
            }
            return assembled
        }
        consumer = task
        defer { consumer = nil }
        let assembled = try await task.value
        await drain(epoch: myEpoch)
        return assembled
    }

    public func stop() async {
        stopped = true
        epoch += 1
        pendingBuffers = 0
        consumer?.cancel()
        graph.node?.stop()
        drainWaiter?.resume()
        drainWaiter = nil
    }

    private func start() throws {
        if graph.engine == nil {
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: Self.format)
            do {
                try engine.start()
            } catch {
                throw ChatError.unreachable
            }
            graph.engine = engine
            graph.node = node
        }
        graph.node?.play()
    }

    private func schedule(_ pcm16le: Data, epoch: Int) {
        guard !stopped, epoch == self.epoch, let node = graph.node else { return }
        let frames = pcm16le.count / 2
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(frames))
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        pcm16le.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            guard let dst = buffer.floatChannelData?[0] else { return }
            for i in 0..<frames { dst[i] = Float(src[i]) / 32768 }
        }
        pendingBuffers += 1
        node.scheduleBuffer(buffer) {
            Task { await self.bufferDidFinish(epoch: epoch) }
        }
    }

    private func bufferDidFinish(epoch: Int) {
        guard epoch == self.epoch else { return }
        pendingBuffers -= 1
        if pendingBuffers <= 0 {
            pendingBuffers = 0
            drainWaiter?.resume()
            drainWaiter = nil
        }
    }

    private func drain(epoch: Int) async {
        guard epoch == self.epoch, pendingBuffers > 0 else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            drainWaiter = c
        }
    }

    private static func oneShot(_ data: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(data)
            continuation.finish()
        }
    }
}

/// HAL objects are not Sendable; the actor's own isolation is the lock.
private final class StreamGraph: @unchecked Sendable {
    var engine: AVAudioEngine?
    var node: AVAudioPlayerNode?

    deinit {
        node?.stop()
        engine?.stop()
    }
}

public struct AVSpeechFallback: SystemSpeechFallback, Sendable {
    /// No default on purpose: this voice only speaks when the network is
    /// gone, so a call site that forgets the language would be discovered by
    /// the one user who can least afford it.
    private let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var voiceLocaleIdentifier: String {
        language.speechLocaleIdentifier
    }

    public func speak(_ text: String) async throws {
        try await SpeechGate.speak(
            text, localeIdentifier: voiceLocaleIdentifier)
    }
}

@MainActor
private final class SpeechGate: NSObject, AVSpeechSynthesizerDelegate {
    private static let synth = AVSpeechSynthesizer()
    private static var current: SpeechGate?
    private var continuation: CheckedContinuation<Void, Error>?

    static func speak(_ text: String, localeIdentifier: String) async throws {
        let gate = SpeechGate()
        current = gate
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            gate.continuation = cont
            synth.delegate = gate
            let utterance = AVSpeechUtterance(string: text)
            // The regional voice first; the bare code is the fallback for a
            // Mac that never downloaded it.
            utterance.voice = AVSpeechSynthesisVoice(language: localeIdentifier)
                ?? AVSpeechSynthesisVoice(
                    language: String(localeIdentifier.prefix(2)))
            synth.speak(utterance)
        }
        current = nil
    }

    /// Idempotent: finish and cancel can both land on the same utterance.
    private func finish() {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finish() }
    }
}
