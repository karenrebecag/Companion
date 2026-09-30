@preconcurrency import AVFoundation
import CompanionCore
import Foundation
@preconcurrency import Speech

/// Wave 15e-0: `TranscriberEngine` over Apple's `SpeechAnalyzer` +
/// `SpeechTranscriber` (macOS 26). Only framework plumbing lives here; the
/// hold's rules are in `AnalyzerTranscriber`, where a fake can drive them.
public struct AppleSpeechEngine: TranscriberEngine {
    private let locales = SupportedLocaleCache()

    public init() {}

    /// The Speech framework's own gate still covers the analyzer.
    public func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public var isAuthorized: Bool {
        get async { SFSpeechRecognizer.authorizationStatus() == .authorized }
    }

    public func assets(localeIdentifier: String) async -> TranscriberAssets {
        guard let locale = await supported(localeIdentifier) else {
            return TranscriberAssets(
                status: "unsupportedLocale", nothingToInstall: false, localeInstalled: false)
        }
        let module = Self.transcriber(locale)
        let status = await AssetInventory.status(forModules: [module])
        let wanted = locale.identifier(.bcp47)
        let installed = await SpeechTranscriber.installedLocales
            .contains { $0.identifier(.bcp47) == wanted }
        let nothingToInstall: Bool
        do {
            nothingToInstall = try await AssetInventory.assetInstallationRequest(
                supporting: [module]) == nil
        } catch {
            Log.app("ear=apple assets=request-failed (\(error.localizedDescription))")
            nothingToInstall = false
        }
        return TranscriberAssets(
            status: String(describing: status), nothingToInstall: nothingToInstall,
            localeInstalled: installed)
    }

    public func installAssets(localeIdentifier: String) async throws {
        guard let locale = await supported(localeIdentifier) else {
            throw VoiceTransportError.unreachable
        }
        let request = try await AssetInventory.assetInstallationRequest(
            supporting: [Self.transcriber(locale)])
        try await request?.downloadAndInstall()
    }

    public func begin(
        localeIdentifier: String, contextualStrings: [String]
    ) async throws -> any TranscriberEngineRun {
        guard let locale = await supported(localeIdentifier) else {
            throw VoiceTransportError.unreachable
        }
        let transcriber = Self.transcriber(locale)
        guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]),
            let source = AppleSpeechRun.micFormat,
            let resampler = StreamingResampler(from: source, to: target)
        else { throw VoiceTransportError.unreachable }
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextualStrings
        let (input, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(
            inputSequence: input, modules: [transcriber], options: nil,
            analysisContext: context)
        return AppleSpeechRun(
            analyzer: analyzer, transcriber: transcriber, input: continuation,
            resampler: resampler)
    }

    /// Cached per identifier so a press does not pay a framework round trip
    /// for an answer that cannot change while the app runs.
    private func supported(_ identifier: String) async -> Locale? {
        if let known = locales.value(for: identifier) { return known }
        let found = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: identifier))
        if let found { locales.store(found, for: identifier) }
        return found
    }

    /// Volatile results are the live partials; fast results trade a little
    /// accuracy on them for latency, never on the final.
    private static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
    }
}

actor AppleSpeechRun: TranscriberEngineRun {
    static let micFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true)

    nonisolated let results: AsyncStream<TranscriberEngineResult>
    private let box: AudioStreamBox<TranscriberEngineResult>
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    /// One per hold: a resampler keeps filter state between frames, so
    /// frame edges do not click into the model's input.
    private let resampler: StreamingResampler
    private let reader: Task<Void, Never>
    private var done = false

    init(
        analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber,
        input: AsyncStream<AnalyzerInput>.Continuation,
        resampler: StreamingResampler
    ) {
        let box = AudioStreamBox<TranscriberEngineResult>()
        self.box = box
        self.results = box.stream
        self.analyzer = analyzer
        self.input = input
        self.resampler = resampler
        reader = Task {
            do {
                for try await result in transcriber.results {
                    box.yield(TranscriberEngineResult(
                        text: String(result.text.characters), isFinal: result.isFinal))
                }
            } catch {
                Log.app("speech: analyzer results failed (\(error.localizedDescription))")
            }
            box.finish()
        }
    }

    func feed(_ frame: MicFrame) async {
        guard !done, let pcm = Self.buffer(from: frame) else { return }
        guard let converted = resampler.convert(pcm) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async {
        guard !done else { return }
        done = true
        // The last syllable's tail is still inside the resampler's filter.
        if let tail = resampler.drain() { input.yield(AnalyzerInput(buffer: tail)) }
        input.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            Log.app("speech: analyzer finalize failed (\(error.localizedDescription))")
            box.finish()
        }
    }

    func cancel() async {
        done = true
        input.finish()
        await analyzer.cancelAndFinishNow()
        reader.cancel()
        box.finish()
    }

    private static func buffer(from frame: MicFrame) -> AVAudioPCMBuffer? {
        let bytes = frame.pcm16le24k
        let count = bytes.count / MemoryLayout<Int16>.size
        guard count > 0, let format = micFormat,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
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

/// Mic PCM (24 kHz Int16) to the analyzer's format, one frame at a time.
/// Not Sendable-checked: each instance belongs to one `AppleSpeechRun` actor.
final class StreamingResampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private var loggedConvertFailure = false

    init?(from source: AVAudioFormat, to target: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        self.converter = converter
        self.target = target
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        // Headroom for the resampler's carried-over frames.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        let pending = PendingInput(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            guard let next = pending.take() else {
                // Not end of stream: the next frame continues this one.
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return next
        }
        if status == .error {
            if !loggedConvertFailure {
                loggedConvertFailure = true
                Log.app("speech: frame conversion failed (\(error?.localizedDescription ?? "unknown"))")
            }
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }

    /// The samples the resampler's filter still holds after the last frame.
    func drain() -> AVAudioPCMBuffer? {
        // A resampler's filter latency is a few hundred frames at most.
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4_096) else {
            return nil
        }
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            outStatus.pointee = .endOfStream
            return nil
        }
        if status == .error {
            Log.app("speech: converter drain failed (\(error?.localizedDescription ?? "unknown"))")
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }
}

/// The converter's input block is `@Sendable` and pulls until told there is
/// no more; this hands it the one frame, once.
private final class PendingInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

private final class SupportedLocaleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var byIdentifier: [String: Locale] = [:]

    func value(for identifier: String) -> Locale? {
        lock.lock()
        defer { lock.unlock() }
        return byIdentifier[identifier]
    }

    func store(_ locale: Locale, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        byIdentifier[identifier] = locale
    }
}
