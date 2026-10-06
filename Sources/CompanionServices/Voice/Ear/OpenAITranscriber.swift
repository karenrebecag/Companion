import CompanionCore
import Foundation

/// The slice of a websocket the ear uses, so a test can play the server.
package protocol EarSocket: AnyObject, Sendable {
    func resume()
    func send(_ text: String) async throws
    /// Fire and forget: the config retry and the queued-frame flush have no
    /// one to throw to.
    func sendDetached(_ text: String)
    /// A text frame arrives as its string; any other frame as nil.
    func receive(_ handler: @escaping @Sendable (Result<String?, Error>) -> Void)
    func cancel()
}

private final class URLSessionEarSocket: EarSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(_ request: URLRequest) {
        task = NoStoreSession.shared.webSocketTask(with: request)
    }

    func resume() { task.resume() }
    func send(_ text: String) async throws { try await task.send(.string(text)) }
    func sendDetached(_ text: String) { task.send(.string(text)) { _ in } }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }

    func receive(_ handler: @escaping @Sendable (Result<String?, Error>) -> Void) {
        task.receive { result in
            handler(result.map { message in
                if case .string(let json) = message { return json }
                return nil
            })
        }
    }
}

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
package final class OpenAITranscriber: SegmentingTranscriber, @unchecked Sendable {
    private let keyProvider: @Sendable () -> String?
    /// The user's turn-detection preference (Settings), read at session open:
    /// since 9j-1 the server's VAD segments the turns, so the knob that went
    /// unconsumed after 9i drives it again.
    private let turnDetection: @Sendable () -> TurnDetection
    private let lock = NSLock()
    private var text = ""
    private var socket: (any EarSocket)?
    /// Read once per start: the dictation list can change between sessions,
    /// never inside one.
    private let languages: @Sendable () -> [String]
    private let connect: @Sendable (URLRequest) -> any EarSocket
    private let box = AudioStreamBox<String>()
    private let turnBox = AudioStreamBox<EarTurnEvent>()
    /// Audio spoken during the websocket handshake must not fall on the
    /// floor: "hola" said two seconds after opening came back as "Ya." with
    /// its first phonemes lost. Frames queue here until the server acks the
    /// session config, then flush in order.
    private var ready = false
    private var queued: [String] = []
    private static let maxQueued = 150  // ~15 s of 100 ms frames
    /// One retry without server VAD when the config is rejected: a deaf ear
    /// (frames queued forever waiting for an ack that never comes) is the
    /// worst failure mode this class can have — measured, not hypothetical.
    private var fellBack = false
    /// Kept so a rejected config retries the same list, including an
    /// omitted languages key. A retry that invented a language would bias
    /// an ear the user left on automatic.
    private var sessionLanguages: [String] = []
    /// Health trace: every link in the hearing chain must be visible in the
    /// log — a session that heard nothing used to look identical to one where
    /// the user never spoke.
    private var sentFrames = 0
    private var heardAnything = false

    package init(
        keyProvider: @escaping @Sendable () -> String?,
        turnDetection: @escaping @Sendable () -> TurnDetection = {
            .serverVAD(silenceMs: 700)
        },
        languages: @escaping @Sendable () -> [String] = {
            SpokenLanguagePreference.transcriptionLanguages()
        },
        connect: @escaping @Sendable (URLRequest) -> any EarSocket = {
            URLSessionEarSocket($0)
        }
    ) {
        self.keyProvider = keyProvider
        self.turnDetection = turnDetection
        self.languages = languages
        self.connect = connect
    }

    package var partials: AsyncStream<String> { box.stream }

    package var turnEvents: AsyncStream<EarTurnEvent> { turnBox.stream }

    package var currentText: String { lock.withLock { text } }

    /// The key gates the whole realtime pipeline before this runs; report
    /// what is actually true at this moment.
    package var isAuthorized: Bool { keyProvider() != nil }

    package func requestAuthorization() async -> Bool { isAuthorized }

    /// `localeIdentifier` is the UI language. Dictation is a separate list,
    /// empty until the user picks, so this session is not biased toward the
    /// interface (local reference; Incredible language pickers).
    package func start(localeIdentifier _: String) async throws {
        halt()
        guard let key = keyProvider() else {
            throw VoiceTransportError.unreachable
        }
        guard let url = URL(
            string: "wss://api.openai.com/v1/realtime?intent=transcription")
        else { throw VoiceTransportError.unreachable }
        var request = URLRequest(url: url)
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let task = connect(request)
        // One read feeds both the first config and a rejected-config retry,
        // so the two can never disagree about the list.
        let chosen = languages()
        lock.withLock {
            text = ""
            sessionLanguages = chosen
            fellBack = false
            sentFrames = 0
            heardAnything = false
        }
        socket = task
        task.resume()
        receiveLoop(on: task)
        try await send(
            Self.sessionUpdateJSON(languages: chosen, turnDetection: turnDetection()),
            over: task)
    }

    package func append(_ frame: MicFrame) async {
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
            let count = lock.withLock { () -> Int in
                sentFrames += 1
                return sentFrames
            }
            // A session that sends 5 s of audio and hears nothing back is
            // broken somewhere upstream — say so instead of staying silent.
            if count == 50, !lock.withLock({ heardAnything }) {
                Log.app("ear: 50 frames sent, no transcript back yet")
            }
        } catch {
            // One dead socket must not log ten times a second: drop it and go
            // quiet; the receive loop already reported why it died.
            Log.app("ear: transcription send failed (\(error.localizedDescription)); ear off")
            self.socket = nil
        }
    }

    package func stop() async -> String {
        let heard = currentText
        halt()
        return heard
    }

    // MARK: - Wire (pure, tested)

    /// `turnDetection: nil` disables server segmentation (the resilience
    /// fallback: a deaf ear is worse than a heuristic one). An empty list
    /// omits `languages`. Sending [] or [""] would bias the
    /// ear, or hand it a code that leaves it deaf
    /// (local reference; Incredible language pickers).
    static func sessionUpdateJSON(
        languages: [String], turnDetection: TurnDetection?
    ) -> String {
        // gpt-transcribe, NOT gpt-live-transcribe: the live model REJECTS
        // turn_detection (measured: "Turn detection is not supported for
        // this transcription model" left the ear deaf), and the probe
        // showed gpt-transcribe + server VAD segmenting alone with better
        // accuracy — it got "Créame" where both others heard "Creo".
        var transcription: [String: Any] = ["model": "gpt-transcribe"]
        let listed = languages.filter { !$0.isEmpty }
        if !listed.isEmpty {
            transcription["languages"] = listed
        }
        return encode([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "transcription": transcription,
                        "turn_detection": turnDetection.map {
                            turnDetectionJSON($0) as Any
                        } ?? (NSNull() as Any),
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
    /// What the user says is theirs: the log keeps the rhythm of the ear
    /// (first hypothesis, each closed segment) and never the words. A
    /// dictated sentence would otherwise land in the app log (12e).
    static func earLine(hearing text: String) -> String {
        "ear: hearing (\(text.count) chars)"
    }

    static func earLine(segment text: String) -> String {
        "ear: segment (\(text.count) chars)"
    }

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

    private func receiveLoop(on task: any EarSocket) {
        task.receive { [weak self] result in
            guard let self, self.socket === task else { return }
            switch result {
            case .failure(let error):
                Log.app("ear: transcription socket died (\(error.localizedDescription))")
            case .success(let message):
                if let json = message {
                    if let delta = Self.delta(fromEvent: json) {
                        let (next, first): (String, Bool) = self.lock.withLock {
                            self.text += delta
                            let first = !self.heardAnything
                            self.heardAnything = true
                            return (self.text, first)
                        }
                        if first {
                            Log.app(Self.earLine(hearing: next))
                        }
                        self.box.yield(next)
                    } else if let final = Self.completedTranscript(fromEvent: json) {
                        Log.app(Self.earLine(segment: final))
                        self.turnBox.yield(.finished(text: final))
                    } else if Self.isSpeechStarted(event: json) {
                        Log.app("ear: vad speech started")
                        self.turnBox.yield(.speechStarted)
                    } else if Self.isSessionReady(event: json) {
                        self.flushQueued(over: task)
                    } else if let error = Self.errorMessage(fromEvent: json) {
                        Log.app("ear: transcription error (\(error))")
                        self.fallBackIfConfigRejected(over: task)
                    }
                }
                self.receiveLoop(on: task)
            }
        }
    }

    private func send(_ json: String, over task: any EarSocket) async throws {
        try await task.send(json)
    }

    /// An error before the session ack means the config was rejected and the
    /// ack will never come — retry once without server VAD so the ear still
    /// hears (the session falls back to its heuristic turn-taking).
    private func fallBackIfConfigRejected(over task: any EarSocket) {
        let (retry, chosen): (Bool, [String]) = lock.withLock {
            guard !ready, !fellBack else { return (false, sessionLanguages) }
            fellBack = true
            return (true, sessionLanguages)
        }
        guard retry else { return }
        Log.app("ear: config rejected — retrying without server VAD")
        task.sendDetached(Self.sessionUpdateJSON(languages: chosen, turnDetection: nil))
    }

    private func flushQueued(over task: any EarSocket) {
        let backlog: [String] = lock.withLock {
            ready = true
            defer { queued = [] }
            return queued
        }
        guard !backlog.isEmpty else { return }
        Log.app("ear: flushing \(backlog.count) queued frames after session ack")
        for payload in backlog {
            task.sendDetached(payload)
        }
    }

    private func halt() {
        socket?.cancel()
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
