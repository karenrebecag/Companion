import AVFoundation
import CompanionCore
import Foundation

public struct OpenAITTSClient: TTSFetching, Sendable {
    private let secrets: any SecretStore
    private let transport: any ChatTransport

    public init(secrets: any SecretStore, transport: any ChatTransport) {
        self.secrets = secrets
        self.transport = transport
    }

    public func fetch(_ text: String, voice: VoiceID) async throws -> Data {
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
        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice.rawValue,
            "response_format": "mp3",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200, !data.isEmpty else {
            throw ChatError.httpStatus(response.statusCode)
        }
        return data
    }
}

public actor DataSpeechPlayback: SpeechPlayback {
    public init() {}

    public func play(_ data: Data) async throws {
        try await PlayerGate.play(data)
    }

    public func stop() async {
        await PlayerGate.stop()
    }
}

public struct AVSpeechFallback: SystemSpeechFallback, Sendable {
    public init() {}

    public func speak(_ text: String) async throws {
        try await SpeechGate.speak(text)
    }
}

@MainActor
private final class PlayerGate: NSObject, AVAudioPlayerDelegate {
    private static var current: PlayerGate?
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Error>?

    static func play(_ data: Data) async throws {
        let gate = PlayerGate()
        current = gate
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            gate.continuation = cont
            do {
                let player = try AVAudioPlayer(data: data)
                gate.player = player
                player.delegate = gate
                player.prepareToPlay()
                player.play()
            } catch {
                cont.resume(throwing: error)
            }
        }
        current = nil
    }

    static func stop() {
        current?.player?.stop()
        current?.finish(nil)
        current = nil
    }

    /// Idempotent: stop() and the delegate can both land on the same playback.
    private func finish(_ error: Error?) {
        guard let cont = continuation else { return }
        continuation = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    // AVFoundation delegate requirements are nonisolated; hop instead of
    // assuming the callback thread.
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer, error: Error?
    ) {
        Task { @MainActor in self.finish(error ?? ChatError.empty) }
    }
}

@MainActor
private final class SpeechGate: NSObject, AVSpeechSynthesizerDelegate {
    private static let synth = AVSpeechSynthesizer()
    private static var current: SpeechGate?
    private var continuation: CheckedContinuation<Void, Error>?

    static func speak(_ text: String) async throws {
        let gate = SpeechGate()
        current = gate
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            gate.continuation = cont
            synth.delegate = gate
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
                ?? AVSpeechSynthesisVoice(language: "es")
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
