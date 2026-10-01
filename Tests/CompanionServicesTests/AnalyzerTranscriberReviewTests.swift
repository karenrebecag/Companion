import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Revisión 2026-09-24 de la wave 15e. H1: el gate de assets dejaba el hold
// sordo para siempre cuando `AssetInventory.status` decía "missing" de un
// modelo que sí estaba instalado.

@Test @MainActor func analyzerTranscriberReviewTests() async {
    await testAStatusThatSaysMissingNeverDeafensAnInstalledModel()
    await testAnInstalledLocaleIsEnoughWhenARequestStillExists()
    await testAReadyLocaleIsNotCheckedAgainOnLaterPresses()
    await testTheMissingLineCarriesTheRawStatus()
    await testAStopDuringTheStartGapLeavesNoLiveRun()
    await testOverlappingStartsNeverOrphanARun()
    await testAStopWaitingOnItsFinalKeepsItsOwnText()
    await testAFinalizeThatNeverReturnsFallsBackToTheLastPartial()
}

/// H1: live, the status said missing for a model already on disk and the
/// install request came back nil — nothing to install means ready.
@MainActor func testAStatusThatSaysMissingNeverDeafensAnInstalledModel() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["abre Safari"]
    engine.reportedAssets = TranscriberAssets(
        status: "supported", nothingToInstall: true, localeInstalled: false)
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    try? await ear.start(localeIdentifier: "es-MX")
    await ear.append(frame(0x11))
    let text = await ear.stop()
    expectEq(text, "abre Safari", "H1: sin nada que instalar, el hold oye")
    expectEq(engine.runs.count, 1, "H1: se abrió el analyzer")
}

@MainActor func testAnInstalledLocaleIsEnoughWhenARequestStillExists() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["abre Notas"]
    engine.reportedAssets = TranscriberAssets(
        status: "supported", nothingToInstall: false, localeInstalled: true)
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    try? await ear.start(localeIdentifier: "es-MX")
    let text = await ear.stop()
    expectEq(text, "abre Notas", "H1: installedLocales lo lista, el hold oye")
}

/// H1: once a locale proved ready, the press path does no framework round
/// trips for it again.
@MainActor func testAReadyLocaleIsNotCheckedAgainOnLaterPresses() async {
    let engine = FakeTranscriberEngine()
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    await ear.prepare(localeIdentifier: "es-MX")
    let afterPrepare = engine.assetChecks
    try? await ear.start(localeIdentifier: "es-MX")
    _ = await ear.stop()
    try? await ear.start(localeIdentifier: "es-MX")
    _ = await ear.stop()
    expectEq(engine.assetChecks, afterPrepare, "H1: tras prepare, ningún press vuelve a preguntar")
    expectEq(engine.runs.count, 2, "H1: los dos holds oyen")

    let fresh = FakeTranscriberEngine()
    let other = AnalyzerTranscriber(engine: fresh, vocabulary: { [] })
    try? await other.start(localeIdentifier: "es-MX")
    _ = await other.stop()
    try? await other.start(localeIdentifier: "es-MX")
    _ = await other.stop()
    expectEq(fresh.assetChecks, 1, "H1: sin prepare, solo el primer press pregunta")
}

@MainActor func testTheMissingLineCarriesTheRawStatus() async {
    let engine = FakeTranscriberEngine()
    engine.reportedAssets = TranscriberAssets(
        status: "downloading", nothingToInstall: false, localeInstalled: false)
    engine.installDelay = 5
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-assets-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        try? await ear.start(localeIdentifier: "es-MX")
        _ = await ear.stop()
        let log = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(log.contains("ear=apple assets=missing locale=es-MX status=downloading"),
               "H1: la línea de assets dice el status crudo")
    }
}

/// M2: a release that lands while `start()` still awaits the engine. The
/// stop sees no run and returns "", so the run `start()` opens afterwards
/// belongs to no hold and must not stay live.
@MainActor func testAStopDuringTheStartGapLeavesNoLiveRun() async {
    let engine = FakeTranscriberEngine()
    let gate = TestGate()
    engine.nextBeginGate = gate
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let start = Task { try? await ear.start(localeIdentifier: "es-MX") }
    await pumpUntil("M2: start espera al engine") { gate.entered }
    let text = await ear.stop()
    gate.open()
    await start.value
    expectEq(text, "", "M2: el stop no tenía nada que oír")
    expectEq(engine.runs.count, 1, "M2: el engine abrió el run tarde")
    expect(engine.runs.first?.cancelled == true, "M2: ese run huérfano se cancela")
    await ear.append(frame(0x11))
    expect(engine.runs.first?.fed.isEmpty == true, "M2: nadie le da audio")
}

/// M2: the first start is still inside `begin` when a second one enters;
/// the newest press owns the ear and the first run is never left live.
@MainActor func testOverlappingStartsNeverOrphanARun() async {
    let engine = FakeTranscriberEngine()
    let gate = TestGate()
    engine.nextBeginGate = gate
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] })
    let first = Task { try? await ear.start(localeIdentifier: "es-MX") }
    await pumpUntil("M2: el primer start espera") { gate.entered }
    try? await ear.start(localeIdentifier: "es-MX")
    gate.open()
    await first.value
    expectEq(engine.runs.count, 2, "M2: dos runs abiertos")
    let newest = engine.runs.first
    let stale = engine.runs.last
    expect(stale?.cancelled == true, "M2: el run del start viejo se cancela")
    expect(newest?.cancelled == false, "M2: el run del press nuevo sigue vivo")
    await ear.append(frame(0x22))
    expectEq(newest?.fed.count, 1, "M2: el audio va al run del press nuevo")
}

/// M1: a stop suspended in the engine's finish while the next hold starts
/// returns its own words, and the new hold's partial never leaks into it.
@MainActor func testAStopWaitingOnItsFinalKeepsItsOwnText() async {
    let engine = FakeTranscriberEngine()
    engine.finalOnFinish = ["abre Safari"]
    let finishGate = TestGate()
    engine.nextFinishGate = finishGate
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] }, finalizeTimeout: 2)
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre", isFinal: false))
    await pumpUntil("M1: parcial viejo") { ear.currentText == "abre" }
    let stop = Task { await ear.stop() }
    await pumpUntil("M1: el stop espera el final") { finishGate.entered }
    engine.finalOnFinish = []
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.last?.emit(TranscriberEngineResult(text: "cierra Mail", isFinal: false))
    await pumpUntil("M1: parcial nuevo") { ear.currentText == "cierra Mail" }
    finishGate.open()
    let text = await stop.value
    expectEq(text, "abre Safari", "M1: el stop viejo devuelve su propio final")
    expectEq(ear.currentText, "cierra Mail", "M1: el hold nuevo conserva su parcial")
    expect(engine.runs.last?.cancelled == false, "M1: el stop viejo no corta el hold nuevo")
}

/// M4: the analyzer's finalize itself hangs (not only its results): the
/// bound still returns the last partial and cancels the run.
@MainActor func testAFinalizeThatNeverReturnsFallsBackToTheLastPartial() async {
    let engine = FakeTranscriberEngine()
    engine.finishNeverReturns = true
    let ear = AnalyzerTranscriber(engine: engine, vocabulary: { [] }, finalizeTimeout: 0.05)
    try? await ear.start(localeIdentifier: "es-MX")
    engine.runs.first?.emit(TranscriberEngineResult(text: "abre Mail", isFinal: false))
    await pumpUntil("M4: parcial") { ear.currentText == "abre Mail" }
    let started = ContinuousClock.now
    let text = await ear.stop()
    expectEq(text, "abre Mail", "M4: el último parcial")
    expect(ContinuousClock.now - started < .seconds(1), "M4: no cuelga")
    expect(engine.runs.first?.cancelled == true, "M4: el run se cancela")
}

func frame(_ byte: UInt8) -> MicFrame {
    MicFrame(pcm16le24k: Data(repeating: byte, count: 640), rms: 0.3)
}
