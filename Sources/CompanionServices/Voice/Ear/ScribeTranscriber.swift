import CompanionCore
import Foundation

/// The realtime ear on ElevenLabs Scribe v2 Realtime. Same port as the OpenAI
/// ear: partials go out as the running transcript, and each committed segment
/// is the end of a turn (commit_strategy=turn_prediction commits when the model
/// predicts the speaker finished).
///
/// The key travels in the `xi-api-key` header over wss to api.elevenlabs.io
/// and nowhere else; the URL carries no credential. Only event kinds reach the
/// log, never transcript text.
package final class ScribeTranscriber: SegmentingTranscriber, @unchecked Sendable {
    static let maxInboundBytes = 64 * 1024
    static let sampleRate = 24_000
    /// Bounded reconnect: two retries with a short pause, then the ear goes
    /// quiet until the next session start. An unbounded loop would hammer a
    /// server that is already refusing us.
    static let retryDelays: [Double] = [0.5, 2.0]
    /// ~15 s of 100 ms frames waiting for session_started.
    static let maxQueued = 150
    static let supportedLanguages: Set<String> = ["es", "en", "pt"]

    private static let host = "api.elevenlabs.io"
    private static let errorKinds: Set<String> = [
        "error", "auth_error", "quota_exceeded", "commit_throttled",
        "unaccepted_terms", "rate_limited", "queue_overflow",
        "resource_exhausted", "session_time_limit_exceeded", "input_error",
        "invalid_request", "chunk_size_exceeded",
        "insufficient_audio_activity", "transcriber_error",
    ]

    private let keyProvider: @Sendable () -> String?
    private let lock = NSLock()
    private var transcript = ScribeTranscript()
    private var connectURL: URL?
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?
    private var attempts = 0
    /// Set by a server error: those are not retried, a retry would meet the
    /// same answer. The next session start is the way back.
    private var serverRefused = false
    private var ready = false
    private var queued: [String] = []
    private var heardFirstPartial = false
    private let box = AudioStreamBox<String>()
    private let turnBox = AudioStreamBox<EarTurnEvent>()

    package init(keyProvider: @escaping @Sendable () -> String?) {
        self.keyProvider = keyProvider
    }

    package var partials: AsyncStream<String> { box.stream }

    package var turnEvents: AsyncStream<EarTurnEvent> { turnBox.stream }

    package var currentText: String { lock.withLock { transcript.currentText } }

    package var isAuthorized: Bool { Self.trimmedKey(keyProvider()) != nil }

    package func requestAuthorization() async -> Bool { isAuthorized }

    package func start(localeIdentifier: String) async throws {
        halt()
        guard let url = Self.endpoint(language: Self.languageCode(from: localeIdentifier))
        else { throw VoiceTransportError.unreachable }
        lock.withLock { connectURL = url }
        try connect(url: url)
    }

    package func append(_ frame: MicFrame) async {
        guard let task = lock.withLock({ socket }) else { return }
        let payload = Self.chunkJSON(frame.pcm16le24k)
        let waiting: Bool = lock.withLock {
            guard !ready else { return false }
            if queued.count < Self.maxQueued { queued.append(payload) }
            return true
        }
        if waiting { return }
        do {
            try await task.send(.string(payload))
        } catch {
            // The receive loop reports the same dead socket and decides about
            // a retry; logging here too would repeat it ten times a second.
            Log.app("ear: scribe send failed")
        }
    }

    package func stop() async -> String {
        let heard = currentText
        halt()
        return heard
    }

    // MARK: - Wire (pure, tested)

    static func endpoint(language: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = host
        parts.path = "/v1/speech-to-text/realtime"
        parts.queryItems = [
            URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
            URLQueryItem(name: "audio_format", value: "pcm_\(sampleRate)"),
            URLQueryItem(name: "commit_strategy", value: "turn_prediction"),
            URLQueryItem(name: "language_code", value: language),
            // Documented range 500-10000 ms; the server closes an idle socket
            // after 15 s, and the mic is not always sending.
            URLQueryItem(name: "keepalive_interval_ms", value: "1000"),
        ]
        return parts.url
    }

    /// nil unless the target is wss to the ElevenLabs host: the key must never
    /// be attached to anything else.
    static func request(url: URL, key: String) -> URLRequest? {
        guard url.scheme == "wss", url.host == host, !key.isEmpty else { return nil }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        return request
    }

    static func isAllowedRedirect(to url: URL) -> Bool {
        (url.scheme == "https" || url.scheme == "wss") && url.host == host
    }

    /// "es-MX" → "es". Anything the app does not speak falls back to English,
    /// never to an empty code the server would reject.
    static func languageCode(from localeIdentifier: String) -> String {
        let prefix = localeIdentifier.split(separator: "-").first
            .map { String($0).lowercased() } ?? ""
        return supportedLanguages.contains(prefix) ? prefix : "en"
    }

    static func chunkJSON(_ pcm16le24k: Data) -> String {
        encode([
            "message_type": "input_audio_chunk",
            "audio_base_64": pcm16le24k.base64EncodedString(),
            "commit": false,
            "sample_rate": sampleRate,
        ])
    }

    static func retryDelay(afterAttempt attempt: Int) -> Double? {
        retryDelays.indices.contains(attempt) ? retryDelays[attempt] : nil
    }

    static func event(fromJSON json: String) -> ScribeEvent {
        guard json.utf8.count <= maxInboundBytes else { return .ignored }
        guard let obj = object(from: json) else { return .ignored }
        switch obj["message_type"] as? String {
        case "session_started":
            return .sessionStarted
        case "partial_transcript":
            guard let text = obj["text"] as? String else { return .ignored }
            return .partial(text)
        case "committed_transcript":
            guard let text = obj["text"] as? String else { return .ignored }
            return .committed(text)
        case let kind? where errorKinds.contains(kind):
            return .failed(kind: kind)
        default:
            return .ignored
        }
    }

    private static func trimmedKey(_ raw: String?) -> String? {
        let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? nil : key
    }

    private static func object(from json: String) -> [String: Any]? {
        do {
            return try JSONSerialization.jsonObject(
                with: Data(json.utf8)) as? [String: Any]
        } catch {
            return nil
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

    // MARK: - Socket plumbing

    private func connect(url: URL) throws {
        guard let key = Self.trimmedKey(keyProvider()),
              let request = Self.request(url: url, key: key)
        else { throw VoiceTransportError.unreachable }
        // Own session, because the redirect guard is a session delegate. The
        // configuration is the app's no-store one, like every other session.
        let guardedSession = URLSession(
            configuration: NoStoreSession.configuration(),
            delegate: RedirectGuard(), delegateQueue: nil)
        let task = guardedSession.webSocketTask(with: request)
        let previous: URLSession? = lock.withLock {
            let old = session
            session = guardedSession
            socket = task
            ready = false
            return old
        }
        previous?.invalidateAndCancel()
        task.resume()
        receiveLoop(on: task)
    }

    private func receiveLoop(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, self.lock.withLock({ self.socket === task }) else { return }
            switch result {
            case .failure:
                self.connectionLost(task)
            case .success(let message):
                if case .string(let json) = message {
                    self.handle(Self.event(fromJSON: json), over: task)
                }
                self.receiveLoop(on: task)
            }
        }
    }

    private func handle(_ event: ScribeEvent, over task: URLSessionWebSocketTask) {
        switch event {
        case .sessionStarted:
            Log.app("ear: scribe session started")
            flushQueued(over: task)
        case .partial:
            let (text, first) = lock.withLock { () -> (String, Bool) in
                transcript.apply(event)
                let first = !heardFirstPartial
                heardFirstPartial = true
                return (transcript.currentText, first)
            }
            if first { Log.app("ear: scribe hearing") }
            box.yield(text)
        case .committed:
            let (turn, text) = lock.withLock { () -> (EarTurnEvent?, String) in
                let turn = transcript.apply(event)
                return (turn, transcript.currentText)
            }
            Log.app("ear: scribe segment")
            box.yield(text)
            if let turn { turnBox.yield(turn) }
        case .failed(let kind):
            Log.app("ear: scribe error (\(kind))")
            lock.withLock { serverRefused = true }
        case .ignored:
            break
        }
    }

    private func flushQueued(over task: URLSessionWebSocketTask) {
        let backlog: [String] = lock.withLock {
            ready = true
            attempts = 0
            defer { queued = [] }
            return queued
        }
        for payload in backlog {
            task.send(.string(payload)) { _ in }
        }
    }

    private func connectionLost(_ task: URLSessionWebSocketTask) {
        let delay: Double? = lock.withLock {
            guard socket === task else { return nil }
            socket = nil
            guard !serverRefused, let pause = Self.retryDelay(afterAttempt: attempts)
            else { return nil }
            attempts += 1
            return pause
        }
        guard let delay else {
            Log.app("ear: scribe socket closed, ear off")
            return
        }
        Log.app("ear: scribe socket lost, retrying")
        let retry = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled,
                  let url = self.lock.withLock({ self.connectURL })
            else { return }
            do {
                try self.connect(url: url)
            } catch {
                Log.app("ear: scribe reconnect failed")
            }
        }
        lock.withLock { reconnectTask = retry }
    }

    private func halt() {
        let (live, old, retry): (URLSessionWebSocketTask?, URLSession?, Task<Void, Never>?) =
            lock.withLock {
                let parts = (socket, session, reconnectTask)
                socket = nil
                session = nil
                reconnectTask = nil
                connectURL = nil
                transcript = ScribeTranscript()
                ready = false
                queued = []
                attempts = 0
                serverRefused = false
                heardFirstPartial = false
                return parts
            }
        retry?.cancel()
        live?.cancel(with: .goingAway, reason: nil)
        old?.invalidateAndCancel()
    }
}

/// What the Scribe socket reports, after the wire is parsed. `committed` is
/// the end of a turn; `partial` is the live hypothesis for the open segment.
enum ScribeEvent: Equatable, Sendable {
    case sessionStarted
    case partial(String)
    case committed(String)
    case failed(kind: String)
    case ignored
}

/// The running transcript of one session: committed segments plus the live
/// hypothesis. Kept apart from the socket so the mapping is testable alone.
struct ScribeTranscript: Equatable, Sendable {
    private(set) var committed: [String] = []
    private(set) var partial = ""

    var currentText: String {
        (committed + [partial])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The end-of-turn event a segment produces, or nil while it is still open
    /// or when the commit carried no words (a silent segment is not a turn).
    @discardableResult
    mutating func apply(_ event: ScribeEvent) -> EarTurnEvent? {
        switch event {
        case .partial(let text):
            partial = text
            return nil
        case .committed(let text):
            partial = ""
            let segment = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { return nil }
            committed.append(segment)
            return .finished(text: segment)
        case .sessionStarted, .failed, .ignored:
            return nil
        }
    }
}

/// Refuses any redirect that would leave the ElevenLabs host, so the header
/// key is never replayed to another origin.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let allowed = request.url.map(ScribeTranscriber.isAllowedRedirect(to:)) ?? false
        completionHandler(allowed ? request : nil)
    }
}
