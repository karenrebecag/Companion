@preconcurrency import AVFoundation
import CompanionCore
import Foundation


/// Wave 15c-5: schedules PCM16LE 24 kHz mono onto its own `AVAudioEngine` as
/// it arrives, instead of `AVAudioPlayer`, which needs a whole file up
/// front — the old mp3 download-then-play. Its own engine, never the mic's
/// shared one (`RealtimePlayer`): a hold's TTS is not realtime voice and
/// must not fight AEC for the graph. One instance lives for the app's whole
/// session (wired once in `CompanionMain`), so the engine is built once and
/// just re-armed between sentences.
package actor DataSpeechPlayback: SpeechPlayback {
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

    package init() {}

    package func play(_ data: Data) async throws {
        _ = try await play(Self.oneShot(data))
    }

    /// Returns everything actually scheduled — a `stop()` mid-stream leaves
    /// this short of the full sentence, which is exactly the signal
    /// `SpeechSynthesis` needs to skip caching a partial.
    package func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data {
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

    package func stop() async {
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

package struct AVSpeechFallback: SystemSpeechFallback, Sendable {
    /// No default on purpose: this voice only speaks when the network is
    /// gone, so a call site that forgets the language would be discovered by
    /// the one user who can least afford it.
    private let language: AppLanguage

    package init(language: AppLanguage) {
        self.language = language
    }

    package var voiceLocaleIdentifier: String {
        language.speechLocaleIdentifier
    }

    package func speak(_ text: String) async throws {
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
