import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Spec self-qa-inspeccion, PR-2: the runner that serves `companion_*`. It
// reads the port and the main log and answers in metadata; nothing here
// writes, asks for a sheet or puts content in `target`.

private let sentinel = "SENTINEL-7f3a-ZXQ"

private func runner(
    _ source: FakeSelfInspecting = FakeSelfInspecting(),
    logTail: @escaping @Sendable (Int) -> [String] = { _ in [] },
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) },
    limit: EqualityLimitBox = EqualityLimitBox()
) -> SelfInspectionRunner {
    SelfInspectionRunner(
        source: source, recognizer: FakeRecognizer(), language: { .en },
        logTail: logTail, now: now, equalityLimit: limit)
}

private func validArguments(_ tool: CompanionTool) -> String {
    tool == .lastMessageMatches ? #"{"expected":"hola"}"# : "{}"
}

private func scratchDir(_ tag: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(tag)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@Test func runnerOffersEveryCompanionTool() {
    let served = runner()
    expectEq(served.specs(.en).map(\.name), CompanionTool.allCases.map(\.rawValue), "runner: las seis, en orden")
    for tool in CompanionTool.allCases {
        expect(served.handles(tool.rawValue), "runner: maneja \(tool.rawValue)")
        expectEq(served.unavailability(for: tool.rawValue), nil, "runner: no depende de las manos")
    }
    expect(!served.handles("click"), "runner: no maneja las manos")
}

@Test func runnerNeverAsksApproval() {
    let served = runner()
    for tool in CompanionTool.allCases {
        let call = ToolCallRef(id: "1", name: tool.rawValue, arguments: validArguments(tool))
        expectEq(served.approval(for: call, said: ""), nil, "runner: \(tool.rawValue) sin hoja propia")
    }
}

@Test func runnerOutcomeTargetIsAlwaysEmpty() async {
    let source = FakeSelfInspecting()
    source.painted = PaintedIsland(state: IslandState(size: .nudge), catalogText: nil)
    source.shownScreen = InspectedScreen(settingsOpen: false, settingsTab: nil, page: "chat")
    source.thread = [FakeSelfInspecting.message("hola")]
    let served = runner(source, logTail: { _ in ["una linea"] })
    for tool in CompanionTool.allCases {
        let outcome = await served.execute(name: tool.rawValue, argumentsJSON: validArguments(tool))
        expect(outcome.ok, "runner: \(tool.rawValue) responde (\(outcome.output))")
        expectEq(outcome.target, "", "runner: \(tool.rawValue) nunca pone contenido en target")
        expectEq(outcome.tool, tool.rawValue, "runner: \(tool.rawValue) se nombra")
    }
}

@Test func runnerOutcomeTargetIsEmptyOnEveryError() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola")]
    let served = runner(source)
    let matches = CompanionTool.lastMessageMatches.rawValue
    var failures = [
        await served.execute(name: "companion_nope", argumentsJSON: "{}"),
        await served.execute(name: CompanionTool.state.rawValue, argumentsJSON: "no es json"),
        await served.execute(name: CompanionTool.island.rawValue, argumentsJSON: "{}"),
        await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: #"{"lines":0}"#),
        await served.execute(name: matches, argumentsJSON: #"{"expected":5}"#),
    ]
    for _ in 1..<EqualityCheckLimit.perMinute {
        _ = await served.execute(name: matches, argumentsJSON: #"{"expected":"x"}"#)
    }
    failures.append(await served.execute(name: matches, argumentsJSON: #"{"expected":"x"}"#))
    for outcome in failures {
        expect(!outcome.ok, "runner: falla (\(outcome.output))")
        expectEq(outcome.target, "", "runner: un error tampoco pone contenido en target (\(outcome.output))")
    }
}

@Test func unknownToolNameIsCappedInTheError() async {
    let long = "companion_" + String(repeating: "z", count: 500)
    let outcome = await runner().execute(name: long, argumentsJSON: "{}")
    expect(!outcome.ok && outcome.output.hasPrefix("not_found:"), "runner: desconocida (\(outcome.output))")
    expect(!outcome.output.contains(long), "runner: el nombre que mando el agente no vuelve entero")
}

@Test func threadToolDetectsLanguageInProcessAndDropsText() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hello we need the \(sentinel)")]
    let outcome = await runner(source).execute(name: CompanionTool.thread.rawValue, argumentsJSON: "{}")
    expect(outcome.ok, "hilo: responde")
    expect(outcome.output.contains(#""language":"en""#), "hilo: el idioma se calcula dentro (\(outcome.output))")
    expect(!outcome.output.contains(sentinel), "hilo: el texto no sale")
}

@Test func matchesToolReturnsBoolOnly() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("  hola mundo ")]
    let served = runner(source)
    let yes = await served.execute(name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":"hola mundo"}"#)
    expectEq(yes.output, #"{"matches":true}"#, "igualdad: solo el bool")
    let no = await served.execute(name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":"Hola mundo"}"#)
    expectEq(no.output, #"{"matches":false}"#, "igualdad: distingue mayusculas")
}

/// The runner side only; the bridge log line for a `companion_*` call is
/// pinned in PR-3 (`companionCallLogLineHasEmptyTarget`).
@Test func matchesToolNeverLogsExpected() async throws {
    let dir = try scratchDir("matches-log")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("capture.log")
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message(sentinel)]
    let served = runner(source)
    let probe = "probe-\(UUID().uuidString)"
    await Log.capturing(to: url) {
        Log.app(probe)
        _ = await served.execute(
            name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":"\#(sentinel)"}"#)
        _ = await served.execute(
            name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":5}"#)
    }
    let logged = try String(contentsOf: url, encoding: .utf8)
    // Without the probe an absent capture file would pass this vacuously.
    expect(logged.contains(probe), "igualdad: la captura funciona")
    expect(!logged.contains(sentinel), "igualdad: el texto esperado nunca va al log")
}

@Test func matchesToolRejectsNonStringOrOversizeExpected() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola")]
    let served = runner(source)
    let name = CompanionTool.lastMessageMatches.rawValue
    let notText = await served.execute(name: name, argumentsJSON: #"{"expected":5}"#)
    expect(!notText.ok && notText.output.hasPrefix("invalid_args:"), "igualdad: un numero no es texto (\(notText.output))")
    let missing = await served.execute(name: name, argumentsJSON: "{}")
    expect(!missing.ok && missing.output.hasPrefix("invalid_args:"), "igualdad: sin expected no compara")
    let long = String(repeating: "a", count: LastMessageMatch.maxExpectedScalars + 1)
    let oversize = await served.execute(name: name, argumentsJSON: #"{"expected":"\#(long)"}"#)
    expect(!oversize.ok && oversize.output.hasPrefix("invalid_args:"), "igualdad: demasiado largo")
    expect(!oversize.output.contains(long), "igualdad: el rechazo no devuelve lo enviado")
}

@Test func matchesToolPastLimitIsRateLimited() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola")]
    let clock = Clock()
    let served = runner(source, now: { clock.now })
    let name = CompanionTool.lastMessageMatches.rawValue
    for attempt in 1...EqualityCheckLimit.perMinute {
        let outcome = await served.execute(name: name, argumentsJSON: #"{"expected":"x"}"#)
        expect(outcome.ok, "igualdad: la \(attempt) entra")
    }
    let refused = await served.execute(name: name, argumentsJSON: #"{"expected":"hola"}"#)
    expect(!refused.ok && refused.output.hasPrefix("rate_limited:"), "igualdad: la 11 en el minuto se rechaza (\(refused.output))")
    clock.advance(EqualityCheckLimit.window + 1)
    let later = await served.execute(name: name, argumentsJSON: #"{"expected":"hola"}"#)
    expectEq(later.output, #"{"matches":true}"#, "igualdad: pasado el minuto vuelve a entrar")
}

/// A probe the runner rejects as invalid still spends budget: otherwise empty
/// or oversize probes would be a free side channel (PR-1 review).
@Test func matchesToolSpendsBudgetBeforeValidating() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola")]
    let served = runner(source)
    let name = CompanionTool.lastMessageMatches.rawValue
    for _ in 1...EqualityCheckLimit.perMinute {
        _ = await served.execute(name: name, argumentsJSON: #"{"expected":5}"#)
    }
    let valid = await served.execute(name: name, argumentsJSON: #"{"expected":"hola"}"#)
    expect(!valid.ok && valid.output.hasPrefix("rate_limited:"), "igualdad: los invalidos tambien gastan (\(valid.output))")
}

/// The per-message cap is what stops an agent from enumerating the user's
/// text one guess at a time across several minutes.
@Test func matchesToolPerMessageCapHoldsUntilANewUserMessage() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola")]
    let clock = Clock()
    let served = runner(source, now: { clock.now })
    let name = CompanionTool.lastMessageMatches.rawValue
    for attempt in 1...EqualityCheckLimit.perMessage {
        if attempt > 1, (attempt - 1) % EqualityCheckLimit.perMinute == 0 {
            clock.advance(EqualityCheckLimit.window + 1)
        }
        let outcome = await served.execute(name: name, argumentsJSON: #"{"expected":"x"}"#)
        expect(outcome.ok, "igualdad: la \(attempt) entra (\(outcome.output))")
    }
    clock.advance(EqualityCheckLimit.window + 1)
    let refused = await served.execute(name: name, argumentsJSON: #"{"expected":"hola"}"#)
    expect(!refused.ok && refused.output.hasPrefix("rate_limited:"), "igualdad: la 31 se rechaza (\(refused.output))")
    expect(refused.output.contains("no more checks"), "igualdad: dice que el mensaje se agoto (\(refused.output))")
    source.thread = [FakeSelfInspecting.message("hola"), FakeSelfInspecting.message("otra cosa")]
    let fresh = await served.execute(name: name, argumentsJSON: #"{"expected":"otra cosa"}"#)
    expectEq(fresh.output, #"{"matches":true}"#, "igualdad: un mensaje nuevo trae cupo nuevo")
}

@Test func matchesToolWithNoUserMessageIsFalse() async {
    let source = FakeSelfInspecting()
    source.thread = [FakeSelfInspecting.message("hola", role: .assistant)]
    let served = runner(source)
    let outcome = await served.execute(
        name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":"hola"}"#)
    expectEq(outcome.output, #"{"matches":false}"#, "igualdad: sin mensaje del usuario no hay igualdad")
    source.thread = []
    let empty = await served.execute(
        name: CompanionTool.lastMessageMatches.rawValue, argumentsJSON: #"{"expected":"hola"}"#)
    expectEq(empty.output, #"{"matches":false}"#, "igualdad: hilo vacio")
}

@Test func matchesToolLimitIsOnePerProcess() {
    let a = SelfInspectionRunner(source: FakeSelfInspecting(), language: { .en })
    let b = SelfInspectionRunner(source: FakeSelfInspecting(), language: { .en })
    expect(a.equalityLimit === SelfInspectionRunner.sharedEqualityLimit, "igualdad: el runner usa la caja del proceso")
    expect(a.equalityLimit === b.equalityLimit, "igualdad: dos runners no reinician el limite")
}

@Test func islandToolBeforeFirstPaintIsNotAvailable() async {
    let outcome = await runner().execute(name: CompanionTool.island.rawValue, argumentsJSON: "{}")
    expect(!outcome.ok && outcome.output.hasPrefix("not_available:"), "isla: sin pintar no hay respuesta (\(outcome.output))")
}

/// The client name and an MCP tool name both come from outside the app: a
/// long one must not come back as a payload aimed at the next agent.
@Test func stateAndIslandCapTheNamesFromOutside() async {
    let source = FakeSelfInspecting()
    let agent = String(repeating: "n", count: 500)
    let tool = String(repeating: "t", count: 500)
    let approval = ApprovalRequest(requestId: "r", toolName: tool, summary: "", inputJSON: "{}", isMCP: true)
    var projection = SessionProjection()
    projection.handsLentTo = agent
    projection.approvalQueue = [approval]
    source.projection = projection
    var island = IslandState(size: .nudge)
    island.hands = agent
    island.approval = approval
    source.painted = PaintedIsland(state: island, catalogText: nil)
    let served = runner(source)
    for name in [CompanionTool.state, .island] {
        let outcome = await served.execute(name: name.rawValue, argumentsJSON: "{}")
        for (long, letter) in [(agent, "n"), (tool, "t")] {
            let capped = String(long.prefix(InspectionName.maxScalars))
            expect(outcome.output.contains(#""\#(capped)""#), "\(name.rawValue): \(letter) sale topado (\(outcome.output))")
            expect(!outcome.output.contains(capped + letter), "\(name.rawValue): \(letter) nunca entero")
        }
    }
}

@Test func everyToolKeepsTheSentinelInside() async {
    let source = FakeSelfInspecting()
    var projection = SessionProjection()
    projection.targets = [sentinel]
    projection.partial = sentinel
    source.projection = projection
    source.painted = PaintedIsland(state: IslandState(size: .card, line: .followUp(sentinel)), catalogText: sentinel)
    source.shownScreen = InspectedScreen(settingsOpen: false, settingsTab: nil, page: "chat")
    source.shownSettings = FakeSelfInspecting.settings(text: sentinel)
    source.thread = [FakeSelfInspecting.message(sentinel)]
    let served = runner(source)
    for tool in CompanionTool.allCases {
        let outcome = await served.execute(name: tool.rawValue, argumentsJSON: validArguments(tool))
        expect(!outcome.output.contains(sentinel), "\(tool.rawValue): el centinela no sale")
    }
}

@Test func logToolReturnsLastLinesWithDataSuffix() async {
    let asked = LockedBox<Int?>(nil)
    let served = runner(logTail: { n in
        asked.withLock { $0 = n }
        return ["uno", "dos"]
    })
    let outcome = await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: "{}")
    expectEq(asked.value, SelfInspectionRunner.defaultLogLines, "log: 50 por defecto")
    expectEq(outcome.output, "uno\ndos\n" + BridgeCopy.toolDataSuffix(.en), "log: las lineas y el marco de datos")
    _ = await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: #"{"lines":7}"#)
    expectEq(asked.value, 7, "log: N pedido")
}

@Test func logToolCapsLinesAndBytes() async {
    let line = String(repeating: "x", count: 999)
    let served = runner(logTail: { n in (0..<n).map { "\($0) \(line)" } })
    for bad in ["0", "201", #""muchas""#] {
        let outcome = await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: #"{"lines":\#(bad)}"#)
        expect(!outcome.ok && outcome.output.hasPrefix("invalid_args:"), "log: \(bad) fuera de rango")
    }
    let outcome = await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: #"{"lines":200}"#)
    let body = outcome.output.replacingOccurrences(of: "\n" + BridgeCopy.toolDataSuffix(.en), with: "")
    expect(body.utf8.count <= SelfInspectionRunner.maxLogBytes, "log: tope de bytes (\(body.utf8.count))")
    expect(body.hasSuffix("199 \(line)"), "log: se quedan las ultimas, no las primeras")
}

/// JSONSerialization hands back NSNumber, and `as? Int` on Darwin turns
/// `true` into 1: a flag is not a line count.
@Test func logToolRejectsLinesThatAreNotAWholeNumber() async {
    let served = runner(logTail: { n in (0..<n).map(String.init) })
    for bad in ["true", "false", "7.5", "null", #"[3]"#] {
        let outcome = await served.execute(name: CompanionTool.log.rawValue, argumentsJSON: #"{"lines":\#(bad)}"#)
        expect(!outcome.ok && outcome.output.hasPrefix("invalid_args:"), "log: \(bad) no es un numero de lineas (\(outcome.output))")
    }
}

@Test func logToolWithNothingLoggedIsOnlyTheDataSuffix() async {
    let outcome = await runner().execute(name: CompanionTool.log.rawValue, argumentsJSON: "{}")
    expect(outcome.ok, "log: un log vacio no es un error")
    expectEq(outcome.output, BridgeCopy.toolDataSuffix(.en), "log: solo el marco de datos")
}

/// A line over the budget is dropped, not cut, and the older lines stop
/// there too: the answer never has a gap in the middle.
@Test func logToolDropsALineOverTheByteBudget() async {
    let huge = String(repeating: "h", count: SelfInspectionRunner.maxLogBytes + 1)
    let older = runner(logTail: { _ in [huge, "corta"] })
    let kept = await older.execute(name: CompanionTool.log.rawValue, argumentsJSON: "{}")
    expectEq(kept.output, "corta\n" + BridgeCopy.toolDataSuffix(.en), "log: la enorme vieja se queda fuera")
    let newest = runner(logTail: { _ in ["corta", huge] })
    let dropped = await newest.execute(name: CompanionTool.log.rawValue, argumentsJSON: "{}")
    expectEq(dropped.output, BridgeCopy.toolDataSuffix(.en), "log: la enorme reciente corta ahi, sin huecos")
}

@Test func logTailReadsOnlyTheGivenFile() throws {
    let dir = try scratchDir("log-tail")
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("companion.log")
    try "vieja-1\nvieja-2\n".write(to: URL(fileURLWithPath: url.path + ".1"), atomically: true, encoding: .utf8)
    try "a\nb\nc\n".write(to: url, atomically: true, encoding: .utf8)
    expectEq(Log.tail(lines: 2, from: url), ["b", "c"], "tail: las ultimas del archivo actual")
    expectEq(Log.tail(lines: 50, from: url), ["a", "b", "c"], "tail: nunca la generacion .1")
    expectEq(Log.tail(lines: 5, from: dir.appendingPathComponent("no-existe.log")), [], "tail: sin archivo, nada")
    expectEq(Log.tail(lines: 0, from: url), [], "tail: cero lineas, nada")
    let empty = dir.appendingPathComponent("vacio.log")
    try Data().write(to: empty)
    expectEq(Log.tail(lines: 5, from: empty), [], "tail: archivo vacio, nada")
    let unterminated = dir.appendingPathComponent("sin-fin.log")
    try "a\nb".write(to: unterminated, atomically: true, encoding: .utf8)
    expectEq(Log.tail(lines: 1, from: unterminated), ["b"], "tail: la ultima aunque no termine en salto")
}

@Test func selfInspectionSourcesNeverMentionTranscriptDebugLogOrUserDefaults() throws {
    let root = try #require(Conformance.repoRoot(), "fuentes: sin la raiz del repo no se comprueba nada")
    let sources = Conformance.swiftFiles(in: root.appendingPathComponent("Sources"))
        .filter { $0.lastPathComponent.hasPrefix("SelfInspection") }
    let names = Set(sources.map(\.lastPathComponent))
    for required in ["SelfInspectionRunner.swift", "SelfInspection.swift", "SelfInspection+Projection.swift"] {
        expect(names.contains(required), "fuentes: \(required) entra en el barrido (\(names.sorted()))")
    }
    // The tail reads whatever file the log was pointed at, so Log.swift
    // itself must never learn where the transcripts debug log lives.
    let log = root.appendingPathComponent("Sources/CompanionServices/Platform/Log.swift")
    for file in sources + [log] {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        expect(!text.isEmpty, "fuentes: \(file.lastPathComponent) se lee")
        for banned in ["TranscriptDebugLog", "UserDefaults"] {
            expect(!text.contains(banned), "fuentes: \(file.lastPathComponent) no menciona \(banned)")
        }
    }
}
