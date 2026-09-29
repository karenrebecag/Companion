import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-4, review round: the card's timer, the words' lifetime and what
// may print them, the update offer's manners, and the release URL's host.

private let warm = TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)

private func card(_ text: DictatedText = "palabra secreta") -> SessionMachine {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.dictating(app: "Slack"))
    _ = machine.handle(.released)
    _ = machine.handle(.dictated(app: "Slack", text: text))
    return machine
}

// MARK: - HIGH: rest() must not shorten the card's clock

@Test func aWarmMutedSnapshotDoesNotShortenTheCardsClock() {
    var machine = card()
    let effects = machine.handle(.voice(warm))
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.completedDelay)),
           "16m-4 HIGH: rest() no reprograma el latido de 1,5 s sobre la tarjeta")
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay)),
           "16m-4 HIGH: reprograma con el plazo de la tarjeta")
    expectEq(machine.projection.kind, .processing(.completed), "16m-4 HIGH: la tarjeta sigue")
    expectEq(machine.projection.dictatedText, "palabra secreta", "16m-4 HIGH: y sus palabras")
}

// MARK: - MEDIUM 1: a card under the pointer, or just copied, does not expire

@Test func aCardUnderThePointerDoesNotExpire() {
    var machine = card()
    expectEq(machine.handle(.dictationCardHover(true)),
             [.scheduleCompletedExpiry(SessionMachine.dictationHoverCap)],
             "16m-4: el puntero encima alarga el reloj al tope, no lo quita")
    let rested = machine.handle(.voice(warm))
    expectEq(rested.filter { if case .scheduleCompletedExpiry = $0 { true } else { false } },
             [.scheduleCompletedExpiry(SessionMachine.dictationHoverCap)],
             "16m-4: rest() con el puntero encima rearma el tope, no los 12 s")
    expectEq(machine.handle(.dictationCardHover(false)),
             [.scheduleCompletedExpiry(SessionMachine.dictationCardDelay)],
             "16m-4: al salir el puntero el reloj vuelve a los 12 s")
}

@Test func copyingRearmsTheCardsClock() {
    var machine = card()
    expectEq(machine.handle(.dictationCardCopied),
             [.scheduleCompletedExpiry(SessionMachine.dictationCardDelay)],
             "16m-4: copiar rearma los 12 s")
    _ = machine.handle(.dictationCardHover(true))
    expectEq(machine.handle(.dictationCardCopied),
             [.scheduleCompletedExpiry(SessionMachine.dictationHoverCap)],
             "16m-4: copiar con el puntero encima conserva el tope")
}

@Test func cardEventsOutsideTheCardDoNothing() {
    var idle = SessionMachine()
    expectEq(idle.handle(.dictationCardHover(true)), [], "16m-4: sin tarjeta, el hover no hace nada")
    expectEq(idle.handle(.dictationCardCopied), [], "16m-4: sin tarjeta, copiar no arma nada")
    var short = SessionMachine()
    _ = short.handle(.pressed)
    _ = short.handle(.released)
    _ = short.handle(.dictated(app: "Slack", text: nil))
    expectEq(short.handle(.dictationCardHover(true)), [],
             "16m-4: el latido corto sin texto no es una tarjeta")
}

/// A recording clock: what was asked, and whether each wait was cancelled.
final class RecordingSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var _delays: [TimeInterval] = []
    private var _cancelled = 0
    var delays: [TimeInterval] { lock.withLock { _delays } }
    var cancelled: Int { lock.withLock { _cancelled } }

    func sleep(_ seconds: TimeInterval) async throws {
        lock.withLock { _delays.append(seconds) }
        do {
            try await Task.sleep(for: .seconds(3_600))
        } catch {
            lock.withLock { _cancelled += 1 }
            throw error
        }
    }
}

@Test @MainActor func hidingOrHoveringTheCardCancelsItsTimer() async {
    let sleeper = RecordingSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.pressed)
    session.send(.released)
    session.send(.dictated(app: "Slack", text: "hola"))
    // The release armed the pending clock; the card's arrival cancels it and
    // arms its own 12 s.
    await pumpUntil("tarjeta: reloj armado") {
        sleeper.delays.count == 2 && sleeper.cancelled == 1
            && sleeper.delays.last == SessionMachine.dictationCardDelay
    }
    session.send(.dictationCardHover(true))
    await pumpUntil("tarjeta: el hover cambia el reloj por el tope") {
        sleeper.cancelled == 2 && sleeper.delays.last == SessionMachine.dictationHoverCap
    }
    session.send(.dictationCardHover(false))
    await pumpUntil("tarjeta: al salir se rearma") { sleeper.delays.count == 4 }
    session.send(.dictationHidden)
    await pumpUntil("tarjeta: ocultar cancela el reloj") { sleeper.cancelled == 4 }
    expectEq(session.projection.kind, .idle, "tarjeta: y la isla descansa")
}

// MARK: - MEDIUM 3: the words leave by every door

@Test func theWordsLeaveByEveryDoor() {
    let doors: [(String, SessionEvent)] = [
        ("press", .pressed), ("provisional press", .pressedProvisionally),
        ("voice error", .voice(TurnSnapshot(state: .error, failure: .networkUnavailable))),
        ("voice thinking", .voice(TurnSnapshot(state: .thinking, pipeline: .realtime))),
        ("typed turn", .typedSubmitted), ("job", .job(.started(goal: "x"))),
        ("stop (Esc)", .stop),
    ]
    for (name, event) in doors {
        var machine = card()
        _ = machine.handle(event)
        expectEq(machine.projection.dictatedText, nil, "16m-4: \(name) suelta las palabras")
        expectEq(machine.projection.dictation, nil, "16m-4: \(name) suelta la app")
    }
}

@Test func aDictatedWithoutAPendingHoldIsIgnored() {
    for prelude in [[], [SessionEvent.pressed]] {
        var machine = SessionMachine()
        for event in prelude { _ = machine.handle(event) }
        let before = machine.projection
        let effects = machine.handle(.dictated(app: "Slack", text: "palabra secreta"))
        expectEq(effects, [], "16m-4: un resultado sin release no produce efectos")
        expectEq(machine.projection, before, "16m-4: ni se guarda")
    }
}

// MARK: - MEDIUM 2: the update offer's manners

@Test func theUpdateOfferRespectsTheHiddenIslandAndTheWindow() {
    let idle = SessionProjection()
    expect(IslandState.from(idle, pebbleHidden: true, update: "v1").line != .updateAvailable(tag: "v1"),
           "16m-4: la isla oculta por la usuaria no ofrece nada")
    var live = SessionProjection()
    live.voice = .live
    expectEq(IslandState.from(live, pebbleHidden: true, update: "v1").line, .updateAvailable(tag: "v1"),
             "16m-4: con la voz viva la isla ya está a la vista, y ofrece")
    expect(IslandState.from(idle, pebbleHidden: false, mainInFront: true, update: "v1").line
        != .updateAvailable(tag: "v1"), "16m-4: con la ventana principal delante no se duplica")
    expectEq(IslandState.from(idle, pebbleHidden: false, mainInFront: false, update: "v1").line,
             .updateAvailable(tag: "v1"), "16m-4: y sin ella sí")
}

// MARK: - MEDIUM 4: layout

@MainActor @Test func theConsentGridClampsItsIdealWidth() {
    let permission = IslandNotice.Grid.permission
    expectEq(IslandNoticeMetrics.width(permission, available: 1_000, ideal: 100), 340,
             "16m-4: el permiso no baja de 340")
    expectEq(IslandNoticeMetrics.width(permission, available: 1_000, ideal: 400), 400,
             "16m-4: entre 340 y 440 se queda en lo que pide")
    expectEq(IslandNoticeMetrics.width(permission, available: 1_000, ideal: 900), 440,
             "16m-4: ni pasa de 440")
    expectEq(IslandNoticeMetrics.width(permission, available: 300, ideal: 100), 300,
             "16m-4: y nunca sale del espacio que hay")
    for grid in [IslandNotice.Grid.limit, .update, .permission, .diagnostic] {
        expectEq(IslandNoticeMetrics.width(grid, available: 0), 0, "16m-4: sin espacio, sin ancho (\(grid))")
    }
}

// MARK: - Security 5: what may print the words

@MainActor @Test func theWordsNeverPrintThroughAnyDescription() {
    let secret = "palabra secreta"
    let machine = card(DictatedText(secret))
    let state = IslandState.from(machine.projection, pebbleHidden: false)
    let printed = [
        "\(machine.projection)", "\(state)", "\(state.line)", String(reflecting: machine.projection),
        "\(SessionEvent.dictated(app: "Slack", text: DictatedText(secret)))",
        IslandCopy.line(state.line), IslandCopy.swapKey(state.line),
    ]
    for text in printed {
        expect(!text.contains(secret), "16m-4: una descripción imprimió lo dictado: \(text.prefix(80))")
    }
    expectEq(machine.projection.dictatedText?.value, secret, "16m-4: la tarjeta sí puede leerlas")
}

@Test @MainActor func theWordsNeverReachTheLogThroughTheWholeCard() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-card-\(UUID().uuidString).log")
    let lines = LineSink()
    let secret = "palabra secreta"
    await Log.capturing(to: url) {
        let sleeper = ManualSleeper()
        let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep,
                                   log: { lines.add($0); Log.app($0) })
        for ending in ["hide", "expire"] {
            session.send(.pressed)
            session.send(.released)
            session.send(.dictated(app: "Slack", text: DictatedText(secret)))
            session.send(.dictationCardHover(true))
            session.send(.dictationCardCopied)
            session.send(.dictationCardHover(false))
            if ending == "hide" {
                session.send(.dictationHidden)
            } else {
                await pumpUntil("log: reloj armado") { sleeper.pending >= 1 }
                sleeper.fire()
                await pumpUntil("log: caducó") { session.projection.kind == .idle }
            }
        }
    }
    let file = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    expect(!file.contains(secret), "16m-4: el log de disco nunca ve lo dictado (ocultar y caducar)")
    expect(!lines.all.contains { $0.contains(secret) }, "16m-4: ni la sesión lo registra")
    expect(!file.isEmpty || !lines.all.isEmpty, "16m-4: el ciclo sí dejó su rastro de transiciones")
}

final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [String] = []
    var all: [String] { lock.withLock { _all } }
    func add(_ line: String) { lock.withLock { _all.append(line) } }
}

// MARK: - Security 6: the release page is GitHub's, and ours

@Test func theReleasePageMustBeOursOnGitHub() {
    func parse(_ url: String) -> URL? {
        let data = (try? JSONSerialization.data(withJSONObject: ["tag_name": "v9.9.9", "html_url": url])) ?? Data()
        return UpdateChecker.parse(data, current: "0.1.0")?.pageURL
    }
    let good = "https://github.com/karenrebecag/Companion/releases/tag/v9.9.9"
    expectEq(parse(good), URL(string: good), "16m-4: la página de nuestra release pasa")
    expectEq(parse("https://evil.example/x"), nil, "16m-4: otro host, fuera")
    expectEq(parse("https://github.com.evil.example/karenrebecag/Companion/releases/1"), nil,
             "16m-4: un host que solo empieza como github.com, fuera")
    expectEq(parse("https://github.com/attacker/Companion/releases/tag/v9.9.9"), nil,
             "16m-4: otro repositorio de github.com, fuera")
    expectEq(parse("https://github.com/karenrebecag/Companion/issues/1"), nil,
             "16m-4: otra ruta de nuestro repositorio, fuera")
    expectEq(parse("https://user@github.com/karenrebecag/Companion/releases/1"), nil,
             "16m-4: con credenciales en la URL, fuera")
    expectEq(parse("https://github.com:8443/karenrebecag/Companion/releases/1"), nil,
             "16m-4: con puerto, fuera")
}

// MARK: - Security 7: the pasteboard

@MainActor @Test func copiedDictationIsMarkedTransientForClipboardManagers() {
    let board = NSPasteboard(name: NSPasteboard.Name("companion.test.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    IslandDictation.copy("palabra secreta", to: board)
    let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    expect(board.types?.contains(transient) == true, "16m-4: marcado como transitorio")
    expect(board.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) != true,
           "16m-4: pero no como oculto: el usuario quiere pegarlo")
    expectEq(board.string(forType: .string), "palabra secreta", "16m-4: y el texto sigue ahí")
}

// MARK: - Safeguard: a lost hover-out must not keep private words up for ever

@Test @MainActor func aLostHoverOutStillExpiresAtTheCap() async {
    expect(SessionMachine.dictationHoverCap > SessionMachine.dictationCardDelay,
           "16m-4: el tope es más largo que el plazo normal")
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.pressed)
    session.send(.released)
    session.send(.dictated(app: "Slack", text: "palabra secreta"))
    session.send(.dictationCardHover(true))
    await settle(0.05)
    sleeper.fire()
    await pumpUntil("tope: la tarjeta caduca sin hover(false)") { session.projection.kind == .idle }
    expectEq(session.projection.dictatedText, nil, "16m-4: y suelta las palabras")
}

// MARK: - The release prefix is derived, not repeated

@Test func theReleasePrefixComesFromTheAPIURL() {
    expectEq(UpdateChecker.releasePathPrefix, "/karenrebecag/Companion/releases",
             "16m-4: el prefijo sale de releaseAPI")
    func page(_ path: String) -> URL { URL(string: "https://github.com" + path)! }
    expect(UpdateChecker.isOurReleasePage(page("/KarenRebecaG/companion/releases/tag/v1")),
           "16m-4: owner y repo sin distinguir mayúsculas")
    expect(!UpdateChecker.isOurReleasePage(page("/karenrebecag/Companion/releases/../../otro")),
           "16m-4: `..` fuera")
    expect(!UpdateChecker.isOurReleasePage(page("/karenrebecag/Companion/releases/%2e%2e/otro")),
           "16m-4: `%2e%2e` fuera")
    expect(!UpdateChecker.isOurReleasePage(page("/karenrebecag/Companion/releases/%2E%2E/otro")),
           "16m-4: `%2E%2E` fuera")
    expect(!UpdateChecker.isOurReleasePage(page("/karenrebecag/Companion/releasesx")),
           "16m-4: el prefijo es de segmento, no de texto")
}

// MARK: - Mirror must not open DictatedText either

@Test func dumpAndMirrorDoNotExposeTheWords() {
    var dumped = ""
    dump(DictatedText("palabra secreta"), to: &dumped)
    dump(card().projection, to: &dumped)
    expect(!dumped.contains("palabra secreta"), "16m-4: dump no imprime lo dictado")
    expectEq(Mirror(reflecting: DictatedText("x")).children.count, 0, "16m-4: Mirror sin hijos")
}
