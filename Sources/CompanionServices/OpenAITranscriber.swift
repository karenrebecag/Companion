import CompanionCore
import Foundation

/// The realtime ear: OpenAI's `gpt-live-transcribe` over the realtime
/// transcription websocket. Chosen by measurement (2026-08-25): on the same
/// audio it beat Apple es-MX ("prueba" vs "problema") and, unlike Apple, it
/// transcribes mixed-language speech natively — "Desktop" inside Spanish came
/// back as "Stock" from Apple. OpenAI no longer recommends the 4o-transcribe
/// generation this app used before.
///
/// Deltas accumulate for the whole session into `currentText` — the same
/// continuous-transcript contract the turn logic already consumes; the
/// committed-prefix bookkeeping lives in the caller. Costs $0.017/min of
/// session audio, so it is started only when the realtime pipeline opens.
public final class OpenAITranscriber: SegmentingTranscriber, @unchecked Sendable {
    private let keyProvider: @Sendable () -> String?
    /// The user's turn-detection preference (Settings), read at session open:
    /// since 9j-1 the server's VAD segments the turns, so the knob that went
    /// unconsumed after 9i drives it again.
    private let turnDetection: @Sendable () -> TurnDetection
    private let lock = NSLock()
    private var text = ""
    private var socket: URLSessionWebSocketTask?
    private let box = AudioStreamBox<String>()
    private let turnBox = AudioStreamBox<EarTurnEvent>()
    /// Audio spoken during the websocket handshake must not fall on the
    /// floor: "hola" said two seconds after opening came back as "Ya." with
    /// its first phonemes lost. Frames queue here until the server acks the
    /// session config, then flush in order.
    private var ready = false
    private var queued: [String] = []
    private static let maxQueued = 150  // ~15 s of 100 ms frames

    public init(
        keyProvider: @escaping @Sendable () -> String?,
        turnDetection: @escaping @Sendable () -> TurnDetection = {
            .serverVAD(silenceMs: 700)
        }
    ) {
        self.keyProvider = keyProvider
        self.turnDetection = turnDetection
    }

    public var partials: AsyncStream<String> { box.stream }

    public var turnEvents: AsyncStream<EarTurnEvent> { turnBox.stream }

    public var currentText: String { lock.withLock { text } }

    /// The key gates the whole realtime pipeline before this runs; report
    /// what is actually true at this moment.
    public var isAuthorized: Bool { keyProvider() != nil }

    public func requestAuthorization() async -> Bool { isAuthorized }

    public func start(localeIdentifier: String) async throws {
        halt()
        guard let key = keyProvider() else {
            throw VoiceTransportError.unreachable
        }
        guard let url = URL(
            string: "wss://api.openai.com/v1/realtime?intent=transcription")
        else { throw VoiceTransportError.unreachable }
        var request = URLRequest(url: url)
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        lock.withLock { text = "" }
        socket = task
        task.resume()
        receiveLoop(on: task)
        try await send(Self.sessionUpdateJSON(
            language: Self.languageHint(from: localeIdentifier),
            turnDetection: turnDetection()), over: task)
    }

    public func append(_ frame: MicFrame) async {
        guard let socket else { return }
        let payload = Self.appendJSON(frame.pcm16le24k)
        let waiting: Bool = lock.withLock {
            guard !ready else { return false }
            if queued.count < Self.maxQueued { queued.append(payload) }
            return true
        }
        if waiting { return }
        do {
            try await send(payload, over: socket)
        } catch {
            // One dead socket must not log ten times a second: drop it and go
            // quiet; the receive loop already reported why it died.
            Log.app("ear: transcription send failed (\(error.localizedDescription)); ear off")
            self.socket = nil
        }
    }

    public func stop() async -> String {
        let heard = currentText
        halt()
        return heard
    }

    // MARK: - Wire (pure, tested)

    /// Language hint from a speech locale: "es-MX" → "es". The model handles
    /// mixed languages on its own; the hint only biases the expected one.
    static func languageHint(from localeIdentifier: String) -> String {
        let prefix = localeIdentifier.split(separator: "-").first ?? "en"
        return prefix.isEmpty ? "en" : String(prefix).lowercased()
    }

    static func sessionUpdateJSON(
        language: String, turnDetection: TurnDetection
    ) -> String {
        encode([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "transcription": [
                            "model": "gpt-live-transcribe",
                            "languages": [language],
                            "delay": "low",
                        ],
                        // 9j-1: the server's VAD segments the turns — it
                        // knows when an idea ended; the client's heuristics
                        // never did. The user's Settings knob decides which.
                        "turn_detection": turnDetectionJSON(turnDetection),
                    ],
                ],
            ],
        ])
    }

    /// The user's preference mapped to the wire. `create_response` /
    /// `interrupt_response` apply only to speech-to-speech sessions, so a
    /// transcription session sends neither.
    static func turnDetectionJSON(_ detection: TurnDetection) -> [String: Any] {
        switch detection {
        case .serverVAD(let ms):
            return ["type": "server_vad", "silence_duration_ms": ms]
        case .semanticVAD(let eagerness):
            return ["type": "semantic_vad", "eagerness": eagerness.rawValue]
        }
    }

    static func appendJSON(_ pcm16le24k: Data) -> String {
        encode([
            "type": "input_audio_buffer.append",
            "audio": pcm16le24k.base64EncodedString(),
        ])
    }

    /// The transcript delta carried by a server event, or nil for any other
    /// event. Errors are surfaced separately by the receive loop.
    static func delta(fromEvent json: String) -> String? {
        guard let obj = object(from: json),
              obj["type"] as? String
                  == "conversation.item.input_audio_transcription.delta"
        else { return nil }
        return obj["delta"] as? String
    }

    static func errorMessage(fromEvent json: String) -> String? {
        guard let obj = object(from: json),
              obj["type"] as? String == "error"
        else { return nil }
        let err = obj["error"] as? [String: Any]
        return err?["message"] as? String ?? "server error"
    }

    /// The server acked the session config: audio sent from here on is safe.
    static func isSessionReady(event json: String) -> Bool {
        object(from: json)?["type"] as? String == "session.updated"
    }

    /// The server's VAD heard the user start speaking.
    static func isSpeechStarted(event json: String) -> Bool {
        object(from: json)?["type"] as? String
            == "input_audio_buffer.speech_started"
    }

    /// A finished segment's final transcript, or nil for any other event.
    static func completedTranscript(fromEvent json: String) -> String? {
        guard let obj = object(from: json),
              obj["type"] as? String
                  == "conversation.item.input_audio_transcription.completed"
        else { return nil }
        return obj["transcript"] as? String
    }

    private static func object(from json: String) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(
                with: Data(json.utf8)) as? [String: Any]
        } catch {
            return nil
        }
    }

    // MARK: - Socket plumbing

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.socket === task else { return }
            switch result {
            case .failure(let error):
                Log.app("ear: transcription socket died (\(error.localizedDescription))")
            case .success(let message):
                if case .string(let json) = message {
                    if let delta = Self.delta(fromEvent: json) {
                        let next = self.lock.withLock { () -> String in
                            self.text += delta
                            return self.text
                        }
                        self.box.yield(next)
                    } else if let final = Self.completedTranscript(fromEvent: json) {
                        self.turnBox.yield(.finished(text: final))
                    } else if Self.isSpeechStarted(event: json) {
                        self.turnBox.yield(.speechStarted)
                    } else if Self.isSessionReady(event: json) {
                        self.flushQueued(over: task)
                    } else if let error = Self.errorMessage(fromEvent: json) {
                        Log.app("ear: transcription error (\(error))")
                    }
                }
                self.receiveLoop(on: task)
            }
        }
    }

    private func send(_ json: String, over task: URLSessionWebSocketTask) async throws {
        try await task.send(.string(json))
    }

    private func flushQueued(over task: URLSessionWebSocketTask) {
        let backlog: [String] = lock.withLock {
            ready = true
            defer { queued = [] }
            return queued
        }
        guard !backlog.isEmpty else { return }
        Log.app("ear: flushing \(backlog.count) queued frames after session ack")
        for payload in backlog {
            task.send(.string(payload)) { _ in }
        }
    }

    private func halt() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        lock.withLock {
            text = ""
            ready = false
            queued = []
        }
    }

    private static func encode(_ obj: [String: Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: obj)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}
