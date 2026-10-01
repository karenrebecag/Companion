import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing
import WebKit

// Wave 16m-5b, third review round. Each test names what it kills.

@MainActor
private final class Counting {
    var draws: [String] = []
    var hungDraws = 0
    var delay: Duration = .milliseconds(60)
    let image = DiagramImage(data: Data([1]), width: 504, height: 40)

    var draw: DiagramScheduler.Draw {
        { [self] block, _ in
            draws.append(block.source)
            if block.source.contains("hang") {
                hungDraws += 1
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            }
            do { try await Task.sleep(for: delay) } catch { return .failed(.unavailable) }
            return .image(image)
        }
    }
}

private func block(_ text: String) -> DiagramBlock { DiagramBlock(source: "flowchart LR\n  \(text)") }
private func isImage(_ outcome: DiagramOutcome) -> Bool { if case .image = outcome { true } else { false } }

// MARK: - 1. A cancelled caller is not a timeout

@MainActor
@Test func diagramCancelledCallersDoNotShutTheRendererDownTests() async {
    await watched(60, "diagramCancelledCallers") {
        // Kills: removing `if Task.isCancelled { return .failed(.unavailable) }`.
        let probe = Counting()
        let scheduler = DiagramScheduler(timeout: .seconds(60), draw: probe.draw)
        for index in 0 ... DiagramScheduler.timeoutsBeforeShutdown {
            let task = Task { await scheduler.render(block("hang\(index)"), width: 504) }
            do { try await Task.sleep(for: .milliseconds(80)) } catch {}
            task.cancel()
            let outcome = await task.value
            expect(outcome != .failed(.timeout), "16m-5b r3: un popup cerrado a mitad de dibujo nunca es .timeout (\(index))")
        }
        let normal = await scheduler.render(block("ok"), width: 504)
        expect(isImage(normal), "16m-5b r3: tras \(DiagramScheduler.timeoutsBeforeShutdown + 1) popups cerrados, el siguiente dibuja: \(normal)")
    }
}

// MARK: - 2. A cancelled flight cannot delete its successor

@MainActor
@Test func diagramCancelledFlightKeepsItsSuccessorTests() async {
    await watched(60, "diagramCancelledFlight") {
        // Kills: `flights[key] = nil` without an identity check in `run`.
        let probe = Counting()
        probe.delay = .milliseconds(400)
        let scheduler = DiagramScheduler(timeout: .seconds(60), draw: probe.draw)
        let key = block("A --> B")
        let first = Task { await scheduler.render(key, width: 504) }
        do { try await Task.sleep(for: .milliseconds(100)) } catch {}
        first.cancel()
        let second = Task { await scheduler.render(key, width: 504) }
        do { try await Task.sleep(for: .milliseconds(60)) } catch {}
        let third = Task { await scheduler.render(key, width: 504) }
        _ = await first.value
        let results = await [second.value, third.value]
        expect(results.allSatisfy(isImage), "16m-5b r3: reabrir tras cancelar dibuja")
        expect(probe.draws.count <= 2, "16m-5b r3: como mucho un dibujo extra tras cancelar y reabrir (hubo \(probe.draws.count))")
    }
}

// MARK: - 5. Queued flights look at the shutdown again

@MainActor
@Test func diagramQueuedFlightsRecheckShutdownTests() async {
    await watched(60, "diagramQueuedRecheck") {
        // Kills: a queued flight that draws after the renderer shut down.
        let probe = Counting()
        let scheduler = DiagramScheduler(timeout: .milliseconds(80), draw: probe.draw)
        let count = DiagramScheduler.timeoutsBeforeShutdown + 2
        let tasks = (0 ..< count).map { index in Task { await scheduler.render(block("hang\(index)"), width: 504) } }
        var outcomes: [DiagramOutcome] = []
        for task in tasks { outcomes.append(await task.value) }
        expectEq(probe.hungDraws, DiagramScheduler.timeoutsBeforeShutdown, "16m-5b r3: los encolados no dibujan tras el apagado")
        expectEq(outcomes.suffix(2).map { $0 }, [.failed(.unavailable), .failed(.unavailable)], "16m-5b r3: y dicen unavailable")
    }
}

// MARK: - 3. The matte does not block the main actor

private func flatImage(_ value: UInt8, _ width: Int, _ height: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(srgbRed: CGFloat(value) / 255, green: CGFloat(value) / 255, blue: CGFloat(value) / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private final class MatteProbe: @unchecked Sendable { var onMain: Bool? }

@MainActor
@Test func diagramMatteRunsOffMainTests() async {
    await watched(60, "diagramMatteOffMain") {
        // Kills: a matte awaited on the main actor. Small, so it is cheap
        // beside the suite's timing tests; the 3000-point run is the gallery's.
        guard let white = flatImage(255, 1008, 200), let black = flatImage(0, 1008, 200) else {
            return expect(false, "16m-5b r3: no se pudieron crear las tomas")
        }
        let ran = MatteProbe()
        let matted = await DiagramPNG.matteAsync(onWhite: white, onBlack: black) { ran.onMain = $0 }
        expect(matted != nil, "16m-5b r3: el matting termina")
        expectEq(ran.onMain, false, "16m-5b r3: el bucle del matting corre fuera del hilo principal")
    }
}

@MainActor
@Test(.enabled(if: galleryEnabled)) func diagramMatteBigTests() async {
    await watched(60, "diagramMatteBig") {
        // 3000 points tall at 2x: 1008 x 6000, six million pixels.
        guard let white = flatImage(255, 1008, 6000), let black = flatImage(0, 1008, 6000) else {
            return expect(false, "16m-5b r3: no se pudieron crear las tomas")
        }
        final class Ticker { var worst: Duration = .zero; var running = true }
        let ticker = Ticker()
        let watchTask = Task { @MainActor in
            while ticker.running {
                let before = ContinuousClock.now
                do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
                ticker.worst = max(ticker.worst, ContinuousClock.now - before)
            }
        }
        // The ticker must be inside a sleep before the work starts.
        do { try await Task.sleep(for: .milliseconds(30)) } catch {}
        let started = ContinuousClock.now
        let matted = await DiagramPNG.matteAsync(onWhite: white, onBlack: black)
        let took = ContinuousClock.now - started
        // Let the ticker report the gap it lived through before it is stopped.
        do { try await Task.sleep(for: .milliseconds(40)) } catch {}
        ticker.running = false
        watchTask.cancel()
        print("MATTE 1008x6000 took \(took), worst main-actor gap \(ticker.worst)")
        expect(matted != nil, "16m-5b r3: el matting de 3000 de alto termina")
        expect(ticker.worst < .milliseconds(250), "16m-5b r3: el MainActor nunca se bloquea más de 250 ms (peor: \(ticker.worst))")
    }
}

// MARK: - 4. A failed save is told, and its log has no path

@MainActor
@Test func diagramSaveFailureTests() async throws {
    let model = IslandDiagramModel()
    expect(!model.saveFailed, "16m-5b r3: nace sin aviso")
    model.record(.cancelled)
    expect(!model.saveFailed, "16m-5b r3: cancelar el panel no es un fallo")
    model.record(.failed)
    expect(model.saveFailed, "16m-5b r3: un guardado fallido deja el aviso")
    model.record(.saved)
    expect(!model.saveFailed, "16m-5b r3: y guardar bien lo quita")
    for language in [AppLanguage.en, .es] {
        let text = Localized.string("island.diagram.save.failed", language: language)
        expect(text != "island.diagram.save.failed" && !text.isEmpty, "16m-5b r3: el aviso está en \(language)")
    }

    let log = FileManager.default.temporaryDirectory.appendingPathComponent("gapm-r3-\(UUID().uuidString).log")
    defer { do { try FileManager.default.removeItem(at: log) } catch {} }
    let secret = URL(fileURLWithPath: "/nonexistent-secret-dir-\(UUID().uuidString)/private-name.png")
    let result = await Log.capturing(to: log) { DiagramFileWriter.write(Data([1, 2]), to: secret) }
    expectEq(result, .failed, "16m-5b r3: escribir donde no se puede es .failed")
    let logged = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    expect(logged.contains("diagram"), "16m-5b r3: el fallo se registra")
    expect(!logged.contains("secret-dir") && !logged.contains("private-name"), "16m-5b r3: el log no lleva la ruta")
    expect(logged.contains("NSCocoaErrorDomain") || logged.contains("Error"), "16m-5b r3: lleva la clase del error")
    let good = FileManager.default.temporaryDirectory.appendingPathComponent("gapm-r3-\(UUID().uuidString).png")
    defer { do { try FileManager.default.removeItem(at: good) } catch {} }
    expectEq(DiagramFileWriter.write(Data([1, 2]), to: good), .saved, "16m-5b r3: escribir bien es .saved")
    expectEq(try Data(contentsOf: good), Data([1, 2]), "16m-5b r3: y escribe los bytes")
}

// MARK: - 6. tearDown

@MainActor
@Test func diagramTearDownTests() async {
    await watched(60, "diagramTearDown") {
        // Kills: removing the tearDown of a finished draw, and the one a
        // cancelled or timed-out draw runs from its cancellation handler.
        let renderer = testRenderer(script: fakeMermaid())
        var page: DiagramWebPage?
        renderer.pageObserver = { page = $0.navigationDelegate as? DiagramWebPage }
        let done = await renderer.render(DiagramBlock(source: "flowchart LR\n  A --> B"), width: 504)
        expect({ if case .image = done { true } else { false } }(), "16m-5b r3: dibuja: \(done)")
        expect(page != nil && page?.webView == nil, "16m-5b r3: tras dibujar, la página soltó su web view")

        renderer.timeout = .milliseconds(500)
        let hung = await renderer.render(DiagramBlock(source: "flowchart LR\n  hang --> B"), width: 504)
        expectEq(hung, .failed(.timeout), "16m-5b r3: colgado es .timeout")
        do { try await Task.sleep(for: .milliseconds(400)) } catch {}
        expect(page != nil && page?.webView == nil, "16m-5b r3: tras el timeout, la página soltó su web view")
    }
}

// MARK: - 8. A node named click

@Test func diagramNodeNamedClickTests() {
    let node = "graph TD\n  click --> B\n  click -- \"texto\" --> C\n  click[Etiqueta] --> D"
    expectEq(CompanionBlocks.diagram(node)?.source, node, "16m-5b r3: un nodo llamado click no se borra en silencio")
    expectEq(CompanionBlocks.diagram("graph TD\n  A --> B\n  click A callback \"tip\"\n  C --> D")?.source, "graph TD\n  A --> B\n  C --> D",
             "16m-5b r3: el click de verdad sigue saliendo")
    expectEq(CompanionBlocks.diagram("graph TD\n  A --> B\n  click A href \"https://evil.example\"")?.source, "graph TD\n  A --> B",
             "16m-5b r3: también con href")
    expectEq(CompanionBlocks.diagram("graph TD\n  A --> B\n  click A \"https://evil.example\"")?.source, "graph TD\n  A --> B",
             "16m-5b r3: y con una URL entre comillas")
}

// MARK: - 9. The watchdog's timer is cancelled with the body

@MainActor
@Test func diagramWatchdogCleansUpTests() async {
    // Kills: a watchdog timer left running for its whole deadline.
    await watched(60, "gapm-r3-watchdog-probe") {}
    do { try await Task.sleep(for: .milliseconds(200)) } catch {}
    expectEq(WatchdogStats.live["gapm-r3-watchdog-probe"] ?? 0, 0, "16m-5b r3: el temporizador del watchdog termina con el cuerpo")
}
