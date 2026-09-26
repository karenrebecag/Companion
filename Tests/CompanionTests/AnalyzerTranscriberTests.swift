import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15e-0 (spec §4 rows 1, 2, 5). El oído del hold es SpeechAnalyzer; el
// framework no trae fake, así que la lógica vive detrás de `TranscriberEngine`
// y estos tests la manejan con uno guionado.

@Test @MainActor func analyzerTranscriberTests() async {
    await testTheFinalCarriesWhatWasSaidFromTheFirstFrame()
    await testFinalSegmentsJoinIntoOneTranscript()
    await testPartialsAndCurrentTextFollowTheVolatileResult()
    await testAFinalThatNeverLandsFallsBackToTheLastPartial()
    await testContextualStringsCarryTheVocabularyCappedAt50()
    await testContextualStringsNeverCarryThePreviousTranscript()
    await testMissingAssetsNeverHangAndLogTheReason()
    await testMissingAssetsInstallOnceWhileInFlight()
    await testTheEarLogsCountsAndLatencyNeverTheWords()
    await testStopWithoutAStartReturnsNothing()
    await testANewStartCancelsTheLiveRun()
}

private func earLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-analyzer-\(UUID().uuidString).log")
}

private func readLog(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        return ""
    }
}


/// Row 1: frames fed from the first one; `stop()` is the analyzer's final.
@MainActor func testTheFinalCarriesWhatWasSaidFromTheFirstFrame() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["abre Safari"]
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    try? await ear.start(localeIdentifier: "es-MX")
    await ear.append(frame(0x7A))
    await ear.append(frame(0x11))
    await ear.append(frame(0x22))
    let text = await ear.stop()
    expectEq(text, "abre Safari", "final: lo que devuelve el analyzer")
    let fed = engine.runs.first?.fed ?? []
    expectEq(fed.count, 3, "final: los tres frames llegaron")
    expectEq(fed.first?.pcm16le24k.first, 0x7A, "final: desde el primer frame")
    expectEq(engine.locales, ["es-MX"], "final: el idioma del hold")
    expect(engine.runs.first?.finished == true, "final: el analyzer se finalizó")
}

/// The analyzer finalizes a long hold in segments; the hold is one utterance.
@MainActor func testFinalSegmentsJoinIntoOneTranscript() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["y busca el clima"]
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre Safari", isFinal: true))
    engine.runs.first?.emit(TranscriberEngineResult(text: "y busca", isFinal: false))
    await pumpUntil("segmentos: el volátil llegó") { ear.currentText == "abre Safari y busca" }
    let text = await ear.stop()
    expectEq(text, "abre Safari y busca el clima", "segmentos: un solo final")
}

@MainActor func testPartialsAndCurrentTextFollowTheVolatileResult() async {
    let engine = FakeTranscriberEngine()
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let seen = StringsBox(ear.partials)
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre", isFinal: false))
    await pumpUntil("parcial: currentText en vivo") { ear.currentText == "abre" }
    await pumpUntil("parcial: llega al stream") { seen.values.contains("abre") }
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre Notas", isFinal: false))
    await pumpUntil("parcial: el volátil se reemplaza") { ear.currentText == "abre Notas" }
}

/// Same contract as the old ear (15c-1): the final or, when it never lands
/// within the budget, the last partial — never a hang.
@MainActor func testAFinalThatNeverLandsFallsBackToTheLastPartial() async {
    let engine = FakeTranscriberEngine()
    engine.resultsNeverEnd = true
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] }, finalizeTimeout: 0.05)
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre Mail", isFinal: false))
    await pumpUntil("sin final: parcial") { ear.currentText == "abre Mail" }
    let started = ContinuousClock.now
    let text = await ear.stop()
    expectEq(text, "abre Mail", "sin final: el último parcial")
    expect(ContinuousClock.now - started < .seconds(1), "sin final: no cuelga")
    expect(engine.runs.first?.cancelled == true, "sin final: el run se cancela")
}

/// Row 2: owner + apps, trimmed, deduplicated, at most 50.
@MainActor func testContextualStringsCarryTheVocabularyCappedAt50() async {
    let engine = FakeTranscriberEngine()
    let apps = (1...80).map { "App\($0)" }
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: {
        ["Karen", "  ", "Safari", "Safari", "Linea\nrota"] + apps
    })
    try? await ear.start(localeIdentifier: "es-MX")
    let strings = engine.contextual.first ?? []
    expectEq(strings.count, 50, "vocabulario: tope de 50")
    expectEq(strings.first, "Karen", "vocabulario: el nombre primero")
    expectEq(strings.filter { $0 == "Safari" }.count, 1, "vocabulario: sin duplicados")
    expect(!strings.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
           "vocabulario: sin vacíos")
    expect(!strings.contains { $0.contains("\n") }, "vocabulario: sin saltos de línea")
}

/// Row 2: the bias is re-read at each start and never carries what was said.
@MainActor func testContextualStringsNeverCarryThePreviousTranscript() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["transfiere a carmesí"]
    let names = NamesBox(["Karen"])
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { names.value })
    try? await ear.start(localeIdentifier: "es-MX")
    _ = await ear.stop()
    names.value = ["Karen", "Notas"]
    try? await ear.start(localeIdentifier: "es-MX")
    let second = engine.contextual.last ?? []
    expectEq(second, ["Karen", "Notas"], "vocabulario: releído en cada start")
    expect(!second.contains { $0.contains("carmesí") }, "vocabulario: nunca el transcript")
}

/// Row 5: a hold before the model is installed returns "" at once, says why,
/// and starts the install instead of opening an analyzer that would hang.
@MainActor func testMissingAssetsNeverHangAndLogTheReason() async {
    let url = earLogURL()
    await Log.capturing(to: url) {
        let engine = FakeTranscriberEngine()
        engine.installed = false
        engine.installDelay = 5
        let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
        var threw = false
        do {
            try await ear.start(localeIdentifier: "es-MX")
        } catch {
            threw = true
        }
        await ear.append(frame(0x11))
        let started = ContinuousClock.now
        let text = await ear.stop()
        expect(!threw, "assets: start no falla (el hold queda en «no te oí»)")
        expectEq(text, "", "assets: stop devuelve vacío")
        expect(ContinuousClock.now - started < .seconds(1), "assets: no cuelga")
        expect(engine.runs.isEmpty, "assets: nunca abre un analyzer")
        expect(readLog(url).contains("ear=apple reason=assets"), "assets: el log dice por qué")
        await pumpUntil("assets: la instalación arrancó") { engine.installs == 1 }
    }
}

@MainActor func testMissingAssetsInstallOnceWhileInFlight() async {
    let engine = FakeTranscriberEngine()
    engine.installed = false
    engine.installDelay = 0.2
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    async let first: Void = ear.prepare(localeIdentifier: "es-MX")
    async let second: Void = ear.prepare(localeIdentifier: "es-MX")
    _ = await (first, second)
    expectEq(engine.installs, 1, "assets: una sola descarga en vuelo")
    await ear.prepare(localeIdentifier: "es-MX")
    expectEq(engine.installs, 1, "assets: instalado, no se repite")
}

/// 12e privacy: counts and milliseconds only, never the utterance.
@MainActor func testTheEarLogsCountsAndLatencyNeverTheWords() async {
    let engine = FakeTranscriberEngine()
    let secret = "contraseña índigo-\(UUID().uuidString.prefix(6))"
    engine.finalOnFinish = [secret]
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let url = earLogURL()
    await Log.capturing(to: url) {
        try? await ear.start(localeIdentifier: "es-MX")
        engine.runs.first?.emit(TranscriberEngineResult(text: "contraseña", isFinal: false))
        await pumpUntil("privacidad: parcial") { ear.currentText == "contraseña" }
        _ = await ear.stop()
        let text = readLog(url)
        expect(text.contains("speech: first words 10 chars"), "privacidad: cuenta caracteres")
        expect(text.range(of: #"ear=apple final=\d+ms"#, options: .regularExpression) != nil,
               "privacidad: la latencia del final en ms")
        expect(!text.contains("contraseña"), "privacidad: nunca lo dicho")
        expect(!text.contains("índigo"), "privacidad: nunca el final")
    }
}

@MainActor func testStopWithoutAStartReturnsNothing() async {
    let engine = FakeTranscriberEngine()
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let text = await ear.stop()
    expectEq(text, "", "sin start: vacío")
    expect(engine.runs.isEmpty, "sin start: nada abierto")
}

/// `halt()` semantics: a start never leaves the previous analysis running.
@MainActor func testANewStartCancelsTheLiveRun() async {
    let engine = FakeTranscriberEngine()
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "viejo", isFinal: false))
    await pumpUntil("reinicio: parcial viejo") { ear.currentText == "viejo" }
    try? await ear.start(localeIdentifier: "es-MX")
    expect(engine.runs.first?.cancelled == true, "reinicio: el run anterior se cancela")
    expectEq(ear.currentText, "", "reinicio: el texto empieza en cero")
    expectEq(engine.runs.count, 2, "reinicio: un run nuevo")
}

// MARK: - Fakes

final class FakeTranscriberEngine: TranscriberEngine, @unchecked Sendable {
    var installed = true
    var installDelay: TimeInterval = 0
    var finalOnFinish: [String] = []
    /// `finish()` returns but the results stream never ends: the final
    /// never lands.
    var resultsNeverEnd = false
    /// `finish()` itself never returns until the run is cancelled — the
    /// analyzer's finalize hanging.
    var finishNeverReturns = false
    /// Held by the next `begin` before it opens a run, then cleared.
    var nextBeginGate: TestGate?
    /// Held by the next run's `finish()` before its finals land.
    var nextFinishGate: TestGate?
    private(set) var installs = 0
    private(set) var runs: [FakeTranscriberRun] = []
    private(set) var contextual: [[String]] = []
    private(set) var locales: [String] = []

    func requestAuthorization() async -> Bool { true }
    var isAuthorized: Bool { true }

    /// Every call to `assets(localeIdentifier:)`: the press path should
    /// stop asking once a locale proved ready.
    private(set) var assetChecks = 0
    /// Overrides what `installed` reports, to model the live mismatch
    /// between `AssetInventory.status` and what is actually on disk.
    var reportedAssets: TranscriberAssets?

    func assets(localeIdentifier: String) async -> TranscriberAssets {
        assetChecks += 1
        if let reportedAssets { return reportedAssets }
        return TranscriberAssets(
            status: installed ? "installed" : "supported",
            nothingToInstall: installed, localeInstalled: installed)
    }

    func installAssets(localeIdentifier: String) async throws {
        installs += 1
        if installDelay > 0 { try await Task.sleep(for: .seconds(installDelay)) }
        installed = true
    }

    func begin(
        localeIdentifier: String, contextualStrings: [String]
    ) async throws -> any TranscriberEngineRun {
        if let gate = nextBeginGate {
            nextBeginGate = nil
            await gate.wait()
        }
        locales.append(localeIdentifier)
        contextual.append(contextualStrings)
        let finishGate = finishNeverReturns ? TestGate() : nextFinishGate
        nextFinishGate = nil
        let run = FakeTranscriberRun(
            finals: finalOnFinish, resultsNeverEnd: resultsNeverEnd, finishGate: finishGate)
        runs.append(run)
        return run
    }
}

final class FakeTranscriberRun: TranscriberEngineRun, @unchecked Sendable {
    private let box = AudioStreamBox<TranscriberEngineResult>()
    private let finals: [String]
    private let resultsNeverEnd: Bool
    private let finishGate: TestGate?
    private(set) var fed: [MicFrame] = []
    private(set) var finished = false
    private(set) var cancelled = false

    init(finals: [String], resultsNeverEnd: Bool, finishGate: TestGate?) {
        self.finals = finals
        self.resultsNeverEnd = resultsNeverEnd
        self.finishGate = finishGate
    }

    var results: AsyncStream<TranscriberEngineResult> { box.stream }

    func emit(_ result: TranscriberEngineResult) { box.yield(result) }

    func feed(_ frame: MicFrame) async { fed.append(frame) }

    func finish() async {
        finished = true
        await finishGate?.wait()
        guard !resultsNeverEnd, !cancelled else { return }
        for text in finals { box.yield(TranscriberEngineResult(text: text, isFinal: true)) }
        box.finish()
    }

    func cancel() async {
        cancelled = true
        finishGate?.open()
        box.finish()
    }
}

/// Suspends callers of `wait()` until `open()`; `entered` tells a test the
/// code under test reached the gate.
final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var didEnter = false

    var entered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didEnter
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            didEnter = true
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

final class NamesBox: @unchecked Sendable {
    var value: [String]
    init(_ value: [String]) { self.value = value }
}

@MainActor final class StringsBox {
    private(set) var values: [String] = []
    init(_ stream: AsyncStream<String>) {
        Task { @MainActor in
            for await value in stream { values.append(value) }
        }
    }
}
