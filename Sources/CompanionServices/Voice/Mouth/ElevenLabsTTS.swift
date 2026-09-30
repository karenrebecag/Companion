import CompanionCore
import Foundation

/// Wave 15f-7a: the hold's mouth on ElevenLabs, behind the same port as
/// OpenAI's so `SpeechSynthesis` never learns which one is speaking.
///
/// Wire contract, verified 2026-09-25 against
/// https://elevenlabs.io/docs/api-reference/text-to-speech/stream (the
/// `convert-as-stream` page) and
/// https://elevenlabs.io/docs/api-reference/authentication: `POST
/// /v1/text-to-speech/{voice_id}/stream`, key in `xi-api-key`, JSON body
/// `text`/`model_id`/`language_code`, format in the `output_format` query.
/// `pcm_24000` is S16LE 16-bit mono per
/// https://elevenlabs.io/docs/overview/capabilities/text-to-speech — the
/// exact bytes `DataSpeechPlayback` already plays for OpenAI.
public struct ElevenLabsTTSClient: TTSFetching, Sendable {
    private static let host = "https://api.elevenlabs.io"
    private static let outputFormat = "pcm_24000"

    private let secrets: any SecretStore
    private let transport: any ChatTransport
    private let language: AppLanguage
    /// Read per request, not captured once: the voice is a setting and a
    /// change must reach the next sentence without rebuilding the mouth.
    private let voiceID: @Sendable () -> String

    public init(
        secrets: any SecretStore, transport: any ChatTransport,
        language: AppLanguage, voiceID: @escaping @Sendable () -> String
    ) {
        self.secrets = secrets
        self.transport = transport
        self.language = language
        self.voiceID = voiceID
    }

    /// The OpenAI `VoiceID` is ignored on purpose: ElevenLabs speaks with
    /// its own voice id, and that is what keys the audio apart.
    public func cacheVariant(voice: VoiceID) -> String {
        "elevenlabs/\(ElevenLabsMouth.model)/\(Self.trimmed(voiceID()))"
    }

    public func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        let request = try makeRequest(text)
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200, !data.isEmpty else {
            throw ChatError.httpStatus(response.statusCode)
        }
        return data
    }

    public func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(text)
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

    /// Same reasoning as `OpenAITTSClient.warm`: a connection probe with no
    /// key and no body, so the handshake is paid at press without reading
    /// the Keychain. The unauthenticated answer is expected and ignored.
    public func warm() async {
        guard let url = URL(string: Self.host + "/v1/models"),
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
        Log.app("tts: elevenlabs warm \(ms) ms")
    }

    private func makeRequest(_ text: String) throws -> URLRequest {
        // Checked before the key: a request that will never be sent must
        // not cost a Keychain read.
        let voice = Self.trimmed(voiceID())
        guard Self.isValidVoiceID(voice) else { throw InvalidVoiceID() }
        let key = Self.trimmed(try secrets.read(.elevenLabs) ?? "")
        guard !key.isEmpty else { throw ChatError.invalidKey }
        guard let url = URL(string: Self.host + "/v1/text-to-speech/\(voice)/stream"
                  + "?output_format=\(Self.outputFormat)")
        else { throw ChatError.unreachable }
        guard EndpointPolicy.isAcceptable(url) else { throw ChatError.unreachable }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "text": text,
            "model_id": ElevenLabsMouth.model,
            "language_code": language.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    fileprivate static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ElevenLabsTTSClient {
    /// Security review 2026-09-25 (LOW-1): the voice id is spliced into the
    /// URL path, so it is refused unless it is what ElevenLabs issues —
    /// never escaped into shape.
    public struct InvalidVoiceID: Error, Equatable {}

    /// `^[A-Za-z0-9]{1,64}$` after trimming the ends; the rule itself is
    /// `ElevenLabsMouth.isValidVoiceID`, shared with Settings.
    static func isValidVoiceID(_ raw: String) -> Bool {
        ElevenLabsMouth.isValidVoiceID(raw)
    }
}
