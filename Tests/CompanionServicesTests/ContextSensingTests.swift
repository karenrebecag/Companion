import CompanionCore
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 10a. Los sensores nunca lanzan, nunca piden permiso y nunca retrasan
// el turno: lo que no llegó dentro del presupuesto no viaja.
@Test @MainActor func contextSensingTests() async {
    await testBudgetDropsTheSlowChannel()
    await testFailingChannelComesBackEmpty()
    await testClipboardOnlyWhenChanged()
    await testSinceLastTurnAcrossSenses()
    await testChannelsOffMeansSensorsUntouched()
    await testFrontmostIgnoresSelfAndReportsPrevious()
    await testDocumentsSensorDegradesWithoutTrust()
    await testTrustIsReadOnEverySense()
    await testDocumentsSensorReadsTheOtherApp()
    await testConcealedClipboardIsNeverRead()
}

/// BUILD-LEDGER P6: un canal que duerme 2 s no retrasa el `sense`.
@MainActor func testBudgetDropsTheSlowChannel() async {
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Safari"),
        documents: FakeChannel(documents: ["a.md"], delay: .seconds(2)),
        clipboard: FakeChannel(clipboard: ClipboardSummary(kind: .text, preview: "x")))
    // Medido fuera del main actor: la suite corre @Test en paralelo y los
    // `pumpUntil` de otros tests lo ocupan; el salto de vuelta no es del sensor.
    let (ctx, elapsed) = await Task.detached { () -> (TurnContext, TimeInterval) in
        let start = Date()
        let ctx = await sensor.sense(.all, budget: .milliseconds(100))
        return (ctx, Date().timeIntervalSince(start))
    }.value
    expect(elapsed < 1, "presupuesto: terminó en \(elapsed)s, no esperó los 2 s")
    expectEq(ctx.focusedApp, "Safari", "presupuesto: el canal rápido llegó")
    expectEq(ctx.openDocuments, [], "presupuesto: el lento viaja vacío")
    expectEq(ctx.clipboard?.preview, "x", "presupuesto: el otro rápido también llegó")
}

@MainActor func testFailingChannelComesBackEmpty() async {
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Notes"),
        documents: FakeChannel(documents: [], fails: true),
        clipboard: FakeChannel())
    let ctx = await sensor.sense(.all, budget: .milliseconds(200))
    expectEq(ctx.focusedApp, "Notes", "fallo: los demás siguen")
    expectEq(ctx.openDocuments, [], "fallo: el que falla vuelve vacío")
}

/// No se relee lo que la usuaria ya tenía hace una hora: si `changeCount` no
/// se movió, el portapapeles no viaja.
@MainActor func testClipboardOnlyWhenChanged() async {
    let board = FakePasteboard(changeCount: 7, string: "hola")
    let sensor = ClipboardSensor(pasteboard: board)
    let first = await sensor.clipboard()
    expectEq(first?.preview, "hola", "clipboard: la primera vez sí")
    let second = await sensor.clipboard()
    expect(second == nil, "clipboard: sin cambio, nil")
    board.changeCount = 8
    board.string = "otra"
    let third = await sensor.clipboard()
    expectEq(third?.preview, "otra", "clipboard: cambió, viaja")
    board.changeCount = 9
    board.string = nil
    board.fileURLs = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.pdf")]
    let files = await sensor.clipboard()
    expectEq(files?.kind, .files, "clipboard: archivos por tipo")
    expectEq(files?.preview, "a.png, b.pdf", "clipboard: solo nombres, no rutas")
}

/// H4 (security review 2026-09-25): a password manager marks its copy with
/// `org.nspasteboard.ConcealedType`/`TransientType` — that content must
/// never reach `<context>`, string or file name alike.
@MainActor func testConcealedClipboardIsNeverRead() async {
    let concealedString = FakePasteboard(changeCount: 1, string: "hunter2")
    concealedString.concealed = true
    expect(
        await ClipboardSensor(pasteboard: concealedString).clipboard() == nil,
        "clipboard: texto concealed, nunca viaja")

    let concealedFiles = FakePasteboard(changeCount: 1, string: nil)
    concealedFiles.concealed = true
    concealedFiles.fileURLs = [URL(fileURLWithPath: "/tmp/vault.kdbx")]
    expect(
        await ClipboardSensor(pasteboard: concealedFiles).clipboard() == nil,
        "clipboard: archivos concealed, nunca viajan")

    let plain = FakePasteboard(changeCount: 1, string: "hola")
    expectEq(
        await ClipboardSensor(pasteboard: plain).clipboard()?.preview, "hola",
        "clipboard: sin concealed, sigue viajando")
}

@MainActor func testSinceLastTurnAcrossSenses() async {
    let clock = TickingClock(start: 1_000)
    let sensor = SystemContextSensor(
        focused: FakeChannel(), documents: FakeChannel(), clipboard: FakeChannel(),
        now: { clock.now })
    let first = await sensor.sense(.all, budget: .milliseconds(100))
    expect(first.sinceLastTurn == nil, "since: nil la primera vez")
    clock.advance(41.5)
    let second = await sensor.sense(.all, budget: .milliseconds(100))
    expectEq(second.sinceLastTurn.map { Int($0) }, 41, "since: segundos desde el anterior")
}

@MainActor func testChannelsOffMeansSensorsUntouched() async {
    let focused = FakeChannel(app: "Safari")
    let docs = FakeChannel(documents: ["x"])
    let clip = FakeChannel(clipboard: ClipboardSummary(kind: .text, preview: "y"))
    let sensor = SystemContextSensor(focused: focused, documents: docs, clipboard: clip)
    let ctx = await sensor.sense([], budget: .milliseconds(100))
    expect(ctx.focusedApp == nil && ctx.openDocuments.isEmpty && ctx.clipboard == nil,
           "apagados: nada viaja")
    expect(focused.calls == 0 && docs.calls == 0 && clip.calls == 0,
           "apagados: ningún sensor fue llamado")
    let only = await sensor.sense(.focusedApp, budget: .milliseconds(100))
    expectEq(only.focusedApp, "Safari", "apagados: solo el encendido")
    expect(docs.calls == 0 && clip.calls == 0, "apagados: los otros siguen sin llamarse")
}

/// BUILD-LEDGER P2: traer Companion al frente hace que la app al frente sea
/// Companion. El sensor reporta la ANTERIOR distinta de nosotros.
@MainActor func testFrontmostIgnoresSelfAndReportsPrevious() async {
    let sensor = FrontmostAppSensor(selfBundleID: "com.karen.companion")
    sensor.noteActivation(name: "Safari", bundleID: "com.apple.Safari")
    sensor.noteActivation(name: "Companion", bundleID: "com.karen.companion")
    let app = await sensor.focusedApp()
    expectEq(app, "Safari", "frontmost: la anterior a Companion")
    sensor.noteActivation(name: "Notes", bundleID: "com.apple.Notes")
    expectEq(await sensor.focusedApp(), "Notes", "frontmost: otra app al frente se reporta tal cual")
    let fresh = FrontmostAppSensor(selfBundleID: "com.karen.companion")
    expect(await fresh.focusedApp() == nil, "frontmost: sin activaciones vistas, nil — no inventa")
}

/// Sin Accesibilidad el canal vuelve vacío y NUNCA toca el árbol AX ni pide
/// el permiso: eso se pide en Ajustes, una vez, con explicación.
@MainActor func testDocumentsSensorDegradesWithoutTrust() async {
    let reads = Counter()
    let sensor = OpenDocumentsSensor(
        trusted: { false }, pid: { 1 }, windows: { _ in reads.bump(); return ["doc.md"] })
    let docs = await sensor.openDocuments()
    expectEq(docs, [], "docs: sin permiso, vacío")
    expectEq(reads.value, 0, "docs: sin permiso no se lee el árbol")
}

@MainActor func testTrustIsReadOnEverySense() async {
    let trust = Flag(false)
    let sensor = OpenDocumentsSensor(trusted: { trust.value }, pid: { 1 }, windows: { _ in ["a.md", "b.md"] })
    expectEq(await sensor.openDocuments(), [], "trust: primero no")
    trust.value = true
    expectEq(await sensor.openDocuments(), ["a.md", "b.md"], "trust: se relee, ahora sí")
}

// MARK: - fakes

final class FakePasteboard: PasteboardReading, @unchecked Sendable {
    var changeCount: Int
    var string: String?
    var fileURLs: [URL] = []
    var hasImage = false
    var concealed = false
    init(changeCount: Int, string: String?) {
        self.changeCount = changeCount
        self.string = string
    }
}

final class TickingClock: @unchecked Sendable {
    private(set) var now: Date
    init(start: TimeInterval) { now = Date(timeIntervalSince1970: start) }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func bump() { lock.lock(); _value += 1; lock.unlock() }
}

final class Flag: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

/// Review 2026-09-05: hablarle a Companion la trae al frente, así que "la app
/// al frente" somos nosotros. Los documentos se leen de la ÚLTIMA app que
/// no es Companion — el pid que `FrontmostAppSensor` ya conoce.
@MainActor func testDocumentsSensorReadsTheOtherApp() async {
    let seen = PIDBox()
    let sensor = OpenDocumentsSensor(
        trusted: { true }, pid: { 42 }, windows: { pid in seen.set(pid); return ["x.md"] })
    expectEq(await sensor.openDocuments(), ["x.md"], "otra app: lee")
    expectEq(seen.value, 42, "otra app: con el pid de la anterior, no el nuestro")
    let reads = Counter()
    let none = OpenDocumentsSensor(
        trusted: { true }, pid: { nil }, windows: { _ in reads.bump(); return ["x.md"] })
    expectEq(await none.openDocuments(), [], "otra app: sin app anterior conocida, vacío")
    expectEq(reads.value, 0, "otra app: y no se lee ningún árbol")
    let front = FrontmostAppSensor(selfBundleID: "com.karen.companion")
    front.noteActivation(name: "Safari", bundleID: "com.apple.Safari", pid: 77)
    front.noteActivation(name: "Companion", bundleID: "com.karen.companion", pid: 5)
    expectEq(front.lastOtherPID, 77, "otra app: el sensor de frente guarda el pid de la anterior")
}

final class PIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: pid_t?
    var value: pid_t? { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ v: pid_t) { lock.lock(); _value = v; lock.unlock() }
}
