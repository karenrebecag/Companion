@preconcurrency import AVFoundation
import CompanionCore
import Foundation
@preconcurrency import Speech

public final class SystemTranscriber: Transcriber, @unchecked Sendable {
    private static let pcmFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true)

    private let box = AudioStreamBox<String>()
    private let transcript = TranscriptBox()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Callbacks land here, not on the app's main queue: the UI must never be
    /// able to starve recognition results.
    private let callbackQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()
    private var appended = 0
    private var sawWords = false

    public var partials: AsyncStream<String> { box.stream }

    /// Live snapshot of the recognized text — the recognition callback keeps it
    /// current, so reading it never halts recognition and never consumes the
    /// partials stream.
    public var currentText: String { transcript.snapshot() }

    public var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public init() {}

    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public func start(localeIdentifier: String) async throws {
        halt()
        let locale = Locale(identifier: localeIdentifier.isEmpty
            ? AppLanguage.en.speechLocaleIdentifier : localeIdentifier)
        let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let rec, rec.isAvailable else {
            throw VoiceTransportError.unreachable
        }
        rec.queue = callbackQueue
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if rec.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        recognizer = rec
        request = req
        transcript.set("")
        appended = 0
        sawWords = false
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            // A silent failure here is a session that "no me escucha" with no
            // trace. Log it; halt() cancels are expected and produce one line.
            if let error, result == nil {
                Log.app("speech: recognition failed "
                    + "(\(error.localizedDescription))")
                return
            }
            guard let result else { return }
            let next = result.bestTranscription.formattedString
            if !self.sawWords, !next.isEmpty {
                self.sawWords = true
                Log.app("speech: first words «\(String(next.prefix(40)))»")
            }
            self.transcript.set(next)
            self.box.yield(next)
        }
    }

    public func append(_ frame: MicFrame) async {
        guard let request else {
            // A silent guard here once swallowed a whole session's audio; if
            // frames arrive with no live request, that has to be visible.
            Log.app("speech: frame dropped — no live recognition request")
            return
        }
        guard let buffer = Self.buffer(from: frame) else { return }
        appended += 1
        if appended == 1 || appended % 100 == 0 {
            Log.app("speech: appended \(appended) buffers")
        }
        request.append(buffer)
    }

    public func stop() async -> String {
        let heard = transcript.snapshot()
        halt()
        return heard
    }

    private func halt() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        transcript.set("")
    }

    private static func buffer(from frame: MicFrame) -> AVAudioPCMBuffer? {
        let bytes = frame.pcm16le24k
        let count = bytes.count / MemoryLayout<Int16>.size
        guard count > 0, let format = pcmFormat else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        bytes.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress,
                  let dst = buffer.int16ChannelData?[0] else { return }
            dst.update(from: src, count: count)
        }
        return buffer
    }
}

private final class TranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func set(_ value: String) {
        lock.lock()
        text = value
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
