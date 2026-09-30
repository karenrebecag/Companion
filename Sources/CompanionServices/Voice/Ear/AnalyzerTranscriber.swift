import CompanionCore
import Foundation

/// One result from the on-device analyzer: a volatile guess at the segment
/// in progress, or that segment's final text.
package struct TranscriberEngineResult: Sendable, Equatable {
    package var text: String
    package var isFinal: Bool

    package init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// One analysis, from the first frame to its final. A value per hold so a
/// late `finish()` of one hold can never touch the next one's analyzer.
package protocol TranscriberEngineRun: Sendable {
    var results: AsyncStream<TranscriberEngineResult> { get }
    func feed(_ frame: MicFrame) async
    /// Ends the input and finalizes; the results stream ends after the
    /// last final.
    func finish() async
    func cancel() async
}

/// What the engine reports about one locale's on-device model.
package struct TranscriberAssets: Sendable, Equatable {
    /// `AssetInventory.status`, verbatim, for the log.
    package var status: String
    /// `assetInstallationRequest(supporting:)` came back nil.
    package var nothingToInstall: Bool
    /// `SpeechTranscriber.installedLocales` lists the locale.
    package var localeInstalled: Bool

    package init(status: String, nothingToInstall: Bool, localeInstalled: Bool) {
        self.status = status
        self.nothingToInstall = nothingToInstall
        self.localeInstalled = localeInstalled
    }

    /// Code review 2026-09-24 (alto): live, `status` said missing for a
    /// model already on disk and every hold ended deaf. Nothing left to
    /// install, or the locale listed as installed, is the ground truth.
    package var isReady: Bool { nothingToInstall || localeInstalled }
}

/// The seam between `AnalyzerTranscriber`'s hold logic and Apple's
/// `SpeechAnalyzer` (`AppleSpeechEngine`): the framework ships no fake, so
/// everything testable lives above this line.
package protocol TranscriberEngine: Sendable {
    func requestAuthorization() async -> Bool
    var isAuthorized: Bool { get async }
    func assets(localeIdentifier: String) async -> TranscriberAssets
    func installAssets(localeIdentifier: String) async throws
    func begin(localeIdentifier: String, contextualStrings: [String]) async throws
        -> any TranscriberEngineRun
}

/// Wave 15e-0: the hold's only ear — Apple's on-device analyzer, streaming
/// from the key-down (spike: 54 ms p50 per clip, no network). Replaces
/// both `SFSpeechRecognizer` and the cloud Whisper final.
package actor AnalyzerTranscriber: Transcriber {
    /// Enough for the owner and the likeliest app names; more only dilutes
    /// the bias.
    static let maxContextualStrings = 50

    private let engine: any TranscriberEngine
    private let vocabulary: @Sendable () -> [String]
    /// The bound on the analyzer's own final; past it the last partial is
    /// the answer, the same contract the old ear kept (15c-1).
    private let finalizeTimeout: TimeInterval
    private let box = AudioStreamBox<String>()
    /// The live hold's transcript. Each start gets its own, so a stop still
    /// waiting on its final reads its own words, never the next hold's.
    private let current = CurrentTranscript()
    private var run: (any TranscriberEngineRun)?
    private var consumer: Task<Void, Never>?
    private var active = false
    private var assetsMissing = false
    private var installing: Set<String> = []
    /// Locales proven ready: later presses skip the asset round trips.
    private var ready: Set<String> = []
    private var appended = 0
    /// Bumped by every start and every stop: a start that suspended across
    /// either one is stale and must not install its run.
    private var generation = 0

    package nonisolated var partials: AsyncStream<String> { box.stream }

    /// Live snapshot of the recognized text; reading it never halts the
    /// analysis and never consumes the partials stream.
    package nonisolated var currentText: String { current.value.snapshot() }

    package var isAuthorized: Bool {
        get async { await engine.isAuthorized }
    }

    package init(
        engine: any TranscriberEngine,
        vocabulary: @escaping @Sendable () -> [String],
        finalizeTimeout: TimeInterval = 0.5
    ) {
        self.engine = engine
        self.vocabulary = vocabulary
        self.finalizeTimeout = finalizeTimeout
    }

    package func requestAuthorization() async -> Bool {
        await engine.requestAuthorization()
    }

    package func start(localeIdentifier: String) async throws {
        generation += 1
        let owner = generation
        await halt()
        guard owner == generation else { return }
        let locale = Self.locale(localeIdentifier)
        active = true
        if !ready.contains(locale) {
            let assets = await engine.assets(localeIdentifier: locale)
            guard owner == generation else { return }
            guard assets.isReady else {
                // A hold before the model is on disk would wait ~52 s; it
                // ends as "no te oí" instead and the install starts meanwhile.
                assetsMissing = true
                Log.app("ear=apple assets=missing locale=\(locale) status=\(assets.status)")
                Task { await self.prepare(localeIdentifier: locale) }
                return
            }
            ready.insert(locale)
        }
        let strings = Self.contextualStrings(vocabulary())
        let live = try await engine.begin(localeIdentifier: locale, contextualStrings: strings)
        guard owner == generation else {
            // Code review 2026-09-24 (medio): a stop or a newer start came in
            // while the engine opened this run; nobody would ever halt it.
            await live.cancel()
            return
        }
        let transcript = SegmentedTranscript()
        current.replace(with: transcript)
        run = live
        consumer = Task { [current, box] in
            var sawWords = false
            for await result in live.results {
                transcript.apply(result)
                // A stopping hold still collects its final, but its words
                // are no longer the live partial.
                guard current.holds(transcript) else { continue }
                let text = transcript.snapshot()
                if !sawWords, !text.isEmpty {
                    sawWords = true
                    // 12e: the hold's words never reach the log, only a count.
                    Log.app("speech: first words \(text.count) chars")
                }
                box.yield(text)
            }
        }
    }

    package func append(_ frame: MicFrame) async {
        guard let run else { return }
        appended += 1
        if appended == 1 || appended % 100 == 0 {
            Log.app("speech: appended \(appended) buffers")
        }
        await run.feed(frame)
    }

    /// Takes the live run out of the actor before waiting on its final, so
    /// a start arriving meanwhile neither halts it nor shares its words.
    package func stop() async -> String {
        guard active || run != nil else { return "" }
        generation += 1
        active = false
        appended = 0
        let missing = assetsMissing
        assetsMissing = false
        let transcript = current.value
        guard let live = run, let consumer else {
            if missing { Log.app("ear=apple reason=assets") }
            current.reset(ifStill: transcript)
            return ""
        }
        run = nil
        self.consumer = nil
        let started = ContinuousClock.now
        let finalizer = TranscriptFinalizer()
        Task {
            await live.finish()
            await consumer.value
            await finalizer.signalFinal(transcript.snapshot())
        }
        let final = await finalizer.awaitFinal(timeout: finalizeTimeout)
        let text = final ?? transcript.snapshot()
        Log.app("ear=apple final=\(Self.milliseconds(ContinuousClock.now - started))ms")
        consumer.cancel()
        await live.cancel()
        current.reset(ifStill: transcript)
        return text
    }

    /// Downloads the on-device model for `localeIdentifier` when missing —
    /// once per locale in flight. Called at launch and by a hold that found
    /// the model absent.
    package func prepare(localeIdentifier: String) async {
        let locale = Self.locale(localeIdentifier)
        guard !ready.contains(locale), installing.insert(locale).inserted else { return }
        defer { installing.remove(locale) }
        guard await !engine.assets(localeIdentifier: locale).isReady else {
            ready.insert(locale)
            return
        }
        Log.app("ear=apple assets=installing locale=\(locale)")
        let started = ContinuousClock.now
        do {
            try await engine.installAssets(localeIdentifier: locale)
            ready.insert(locale)
            let ms = Self.milliseconds(ContinuousClock.now - started)
            Log.app("ear=apple assets=installed locale=\(locale) \(ms)ms")
        } catch {
            Log.app("ear=apple assets=failed locale=\(locale) (\(error.localizedDescription))")
        }
    }

    private func halt() async {
        consumer?.cancel()
        consumer = nil
        let old = run
        run = nil
        active = false
        assetsMissing = false
        appended = 0
        current.replace(with: SegmentedTranscript())
        await old?.cancel()
    }

    /// Spelling bias only: names, trimmed, deduplicated, in the caller's
    /// order (owner first), never a previous transcript.
    static func contextualStrings(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in names {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains(where: \.isNewline),
                  seen.insert(name).inserted else { continue }
            out.append(name)
            if out.count == maxContextualStrings { break }
        }
        return out
    }

    private static func locale(_ identifier: String) -> String {
        identifier.isEmpty ? AppLanguage.en.speechLocaleIdentifier : identifier
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1_000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }
}

/// Finalized segments plus the volatile one in progress: the analyzer
/// finalizes a long hold piecewise, and the hold is one utterance.
private final class SegmentedTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var finalized = ""
    private var volatile = ""

    func apply(_ result: TranscriberEngineResult) {
        lock.lock()
        defer { lock.unlock() }
        if result.isFinal {
            finalized = Self.join(finalized, result.text)
            volatile = ""
        } else {
            volatile = result.text
        }
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return Self.join(finalized, volatile)
    }

    private static func join(_ head: String, _ tail: String) -> String {
        guard !head.isEmpty else { return tail }
        guard !tail.isEmpty else { return head }
        let spaced = head.last?.isWhitespace == true || tail.first?.isWhitespace == true
        return spaced ? head + tail : head + " " + tail
    }
}

/// Which `SegmentedTranscript` is the live hold's; read off the actor by
/// `currentText`, so it sits behind its own lock.
private final class CurrentTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var transcript = SegmentedTranscript()

    var value: SegmentedTranscript {
        lock.lock()
        defer { lock.unlock() }
        return transcript
    }

    func replace(with next: SegmentedTranscript) {
        lock.lock()
        defer { lock.unlock() }
        transcript = next
    }

    func holds(_ candidate: SegmentedTranscript) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return transcript === candidate
    }

    /// Clears only when no newer hold took over meanwhile.
    func reset(ifStill stale: SegmentedTranscript) {
        lock.lock()
        defer { lock.unlock() }
        if transcript === stale { transcript = SegmentedTranscript() }
    }
}
