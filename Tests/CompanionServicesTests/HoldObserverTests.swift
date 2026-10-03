import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Incredible's hold observations (referencia local): while the key is held the host
// reports, per hold, every surface the user moved to and everything they copied.

private final class FakeSurface: HoldSurfaceReading, @unchecked Sendable {
    var current: HoldSurface?
    init(_ current: HoldSurface?) { self.current = current }
    func surface() -> HoldSurface? { current }
}

private final class Batches: @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [HoldObservationBatch] = []
    var all: [HoldObservationBatch] { lock.lock(); defer { lock.unlock() }; return _all }
    func add(_ batch: HoldObservationBatch) { lock.lock(); _all.append(batch); lock.unlock() }
}

private func observer(_ surface: FakeSurface, _ board: FakePasteboard, clock: Counter = Counter())
    -> HoldObserver {
    HoldObserver(surface: surface, pasteboard: board, now: { clock.value }, polls: false)
}

@Test func whatWasOnScreenAndOnTheBoardBeforeTheHoldIsNotObserved() async {
    let surface = FakeSurface(HoldSurface(app: "Notes", title: "Lista"))
    let board = FakePasteboard(changeCount: 4, string: "viejo")
    let hold = observer(surface, board)
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    await hold.tick()
    expectEq(batches.all.count, 0, "el punto de partida no se reporta")
}

@Test func movingToAnotherSurfaceIsObserved() async {
    let surface = FakeSurface(HoldSurface(app: "Notes", title: "Lista"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 7) { batches.add($0) }
    surface.current = HoldSurface(app: "Mail", title: "Nuevo")
    await hold.tick()
    await hold.tick()
    expectEq(batches.all.count, 1, "un cambio, un lote; sin cambio, nada")
    expectEq(batches.all.last?.generation, 7, "el lote lleva su generacion")
    expectEq(batches.all.last?.events.map(\.event),
             [.surfaceChanged(app: "Mail", title: "Nuevo", url: nil)], "la superficie nueva")
}

@Test func aCopyDuringTheHoldIsObservedButAConcealedOneNever() async {
    let board = FakePasteboard(changeCount: 1, string: nil)
    let hold = observer(FakeSurface(nil), board)
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    board.changeCount = 2
    board.string = "total 42"
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.copied("total 42")], "lo copiado")
    board.changeCount = 3
    board.string = "clave"
    board.concealed = true
    await hold.tick()
    expectEq(batches.all.count, 1, "un gestor de contrasenas nunca se lee")
    board.changeCount = 4
    board.string = nil
    board.concealed = false
    board.hasImage = true
    await hold.tick()
    expectEq(batches.all.count, 1, "sin texto no hay copia que mostrar")
}

@Test func everyBatchCarriesTheWholeHoldSoIdsStayStable() async {
    let surface = FakeSurface(HoldSurface(app: "A", title: nil))
    let board = FakePasteboard(changeCount: 1, string: nil)
    let clock = Counter()
    let hold = observer(surface, board, clock: clock)
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    clock.bump()
    surface.current = HoldSurface(app: "B", title: nil)
    await hold.tick()
    clock.bump()
    board.changeCount = 2
    board.string = "x"
    await hold.tick()
    expectEq(batches.all.last?.events.count, 2, "el segundo lote trae los dos eventos")
    expectEq(batches.all.last?.events.map(\.atMs), [1, 2], "cada uno con su hora")
    expectEq(HoldCollect.items(from: batches.all[0].events).map(\.id),
             Array(HoldCollect.items(from: batches.all[1].events).map(\.id).prefix(1)),
             "el mismo evento conserva su id de un lote a otro")
}

@Test func stoppingEndsTheHoldAndANewOneStartsClean() async {
    let surface = FakeSurface(HoldSurface(app: "A", title: nil))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "B", title: nil)
    await hold.tick()
    await hold.stop()
    surface.current = HoldSurface(app: "C", title: nil)
    await hold.tick()
    expectEq(batches.all.count, 1, "sin hold no se observa nada")
    await hold.start(generation: 2) { batches.add($0) }
    surface.current = HoldSurface(app: "D", title: nil)
    await hold.tick()
    expectEq(batches.all.last?.generation, 2, "el hold nuevo es otra generacion")
    expectEq(batches.all.last?.events.count, 1, "y empieza sin lo del anterior")
}

// Code and QA review: a hold that starts on Companion itself has no surface yet; the
// first real app the user goes to is a move.
@Test func theFirstSurfaceAfterAnUnreadableStartIsAMove() async {
    let surface = FakeSurface(nil)
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Mail", title: "Nuevo")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.surfaceChanged(app: "Mail", title: "Nuevo", url: nil)],
             "la primera app real cuenta")
}

// Code review: a title that blinks out for one look is not a move within the same app.
@Test func aTitleThatCannotBeReadKeepsTheLastOne() async {
    let surface = FakeSurface(HoldSurface(app: "Mail", title: "Nuevo"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Mail", title: nil)
    await hold.tick()
    surface.current = HoldSurface(app: "Mail", title: "Nuevo")
    await hold.tick()
    expectEq(batches.all.count, 0, "un titulo que no se pudo leer no es otra ventana")
    surface.current = HoldSurface(app: "Notes", title: nil)
    await hold.tick()
    expectEq(batches.all.count, 1, "otra app sin titulo si es un cambio")
}

private final class CountingBoard: PasteboardReading, @unchecked Sendable {
    var changeCount = 1
    var text: String?
    var concealed = false
    private(set) var reads = 0
    var string: String? {
        reads += 1
        return text
    }
    var fileURLs: [URL] { [] }
    var hasImage: Bool { false }
}

// QA review: concealed content must not be read at all, not read and dropped.
@Test func aConcealedCopyIsNeverEvenRead() async {
    let board = CountingBoard()
    let hold = HoldObserver(surface: FakeSurface(nil), pasteboard: board, now: { 0 }, polls: false)
    await hold.start(generation: 1) { _ in }
    board.changeCount = 2
    board.text = "clave"
    board.concealed = true
    await hold.tick()
    expectEq(board.reads, 0, "el texto de un gestor de contrasenas no se toca")
}

@Test func aMoveAndACopyInOneLookAreOneBatch() async {
    let surface = FakeSurface(HoldSurface(app: "A", title: nil))
    let board = FakePasteboard(changeCount: 1, string: nil)
    let hold = observer(surface, board)
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "B", title: nil)
    board.changeCount = 2
    board.string = "x"
    await hold.tick()
    expectEq(batches.all.count, 1, "un lote")
    expectEq(batches.all.last?.events.count, 2, "con los dos")
    board.changeCount = 3
    board.string = ""
    await hold.tick()
    expectEq(batches.all.count, 1, "copiar texto vacio no es nada")
}

// Security review: a huge copy is kept only as long as anything could show it.
@Test func aHugeCopyIsCut() async {
    let board = FakePasteboard(changeCount: 1, string: nil)
    let hold = observer(FakeSurface(nil), board)
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    board.changeCount = 2
    board.string = String(repeating: "a", count: 100_000)
    await hold.tick()
    guard case .copied(let text) = batches.all.last?.events.last?.event else {
        expect(false, "debia haber una copia")
        return
    }
    expectEq(text.count, HoldObserver.copyLimit, "la copia se corta a \(HoldObserver.copyLimit)")
}

// QA review: the real loop, not just tick(): it looks on its own and stops when told.
@Test func theLoopLooksOnItsOwnAndStopsWhenTold() async {
    let surface = FakeSurface(HoldSurface(app: "A", title: nil))
    let hold = HoldObserver(surface: surface, pasteboard: FakePasteboard(changeCount: 1, string: nil),
                            now: { 0 }, interval: .milliseconds(5))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "B", title: nil)
    await settle { batches.all.count == 1 }
    expectEq(batches.all.count, 1, "el bucle vio el cambio solo")
    await hold.start(generation: 2) { batches.add($0) }
    surface.current = HoldSurface(app: "C", title: nil)
    await settle { batches.all.count == 2 }
    expectEq(batches.all.map(\.generation), [1, 2], "un segundo start reemplaza al primero")
    await hold.stop()
    surface.current = HoldSurface(app: "D", title: nil)
    do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
    expectEq(batches.all.count, 2, "detenido no mira mas")
}

private func settle(_ done: () -> Bool) async {
    for _ in 0..<400 where !done() {
        do { try await Task.sleep(for: .milliseconds(5)) } catch { return }
    }
}

@Test func aSurfaceThatCannotBeReadIsNotAChange() async {
    let surface = FakeSurface(HoldSurface(app: "A", title: "x"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = nil
    await hold.tick()
    surface.current = HoldSurface(app: "A", title: "x")
    await hold.tick()
    expectEq(batches.all.count, 0, "perder la lectura un instante no inventa cambios")
}

// b2b: Incredible's hold reports a dialog when it opens over what the user is on,
// without counting it as another window.
@Test func aDialogThatOpensIsObservedOnceAndIsNotAMove() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar")
    await hold.tick()
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.dialogOpened(title: "Guardar")], "solo el dialogo")
    surface.current = HoldSurface(app: "Pages", title: "Informe")
    await hold.tick()
    await hold.tick()
    expectEq(batches.all.count, 1, "cerrarlo no es nada")
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event),
             [.dialogOpened(title: "Guardar"), .dialogOpened(title: "Guardar")], "abrirlo otra vez si, y nada mas")
}

@Test func aDialogAlreadyOpenWhenTheHoldBeganIsNotObserved() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    await hold.tick()
    expectEq(batches.all.count, 0, "es el punto de partida")
}

@Test func aDialogThatCannotBeReadForOneLookIsNotOpenedAgain() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Pages", title: nil)
    await hold.tick()
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar")
    await hold.tick()
    expectEq(batches.all.count, 0, "una lectura fallida no cierra ni abre nada")
}

// Code and security review (b2b-1): a path can carry a token too (/reset/<token>), and the
// overlay never shows it; only the site is kept.
@Test func aPageAddressKeepsOnlyTheSite() {
    expectEq(SystemHoldSurface.pageURL("https://mail.google.com/mail/u/0/?token=abc#inbox"),
             "https://mail.google.com", "sin ruta, query ni fragmento")
    expectEq(SystemHoldSurface.pageURL("http://example.com"), "http://example.com", "http tambien")
    expectEq(SystemHoldSurface.pageURL("file:///Users/k/secreto.pdf"), nil, "un archivo no es una pagina")
    expectEq(SystemHoldSurface.pageURL("javascript:alert(1)"), nil, "ni un script")
    expectEq(SystemHoldSurface.pageURL("https://user:pw@example.com/a"), "https://example.com",
             "las credenciales en la direccion nunca se guardan")
}

// QA review (b2b-1): a dialog is new by where it is, not only by its title.
@Test func theSameDialogInAnotherAppIsAnotherDialog() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Keynote", title: "Charla", dialog: "Guardar")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event),
             [.surfaceChanged(app: "Keynote", title: "Charla", url: nil), .dialogOpened(title: "Guardar")],
             "el movimiento y luego su dialogo, en ese orden")
}

@Test func oneDialogReplacedByAnotherIsObserved() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Imprimir")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.dialogOpened(title: "Imprimir")], "el nuevo")
}

@Test func aNewDialogWhileTheTitleCannotBeReadIsStillObserved() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Pages", title: nil, dialog: "Otro")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.dialogOpened(title: "Otro")], "solo el dialogo")
}

// QA review (b2b-1): the page search has a budget; missing it once is not leaving the page.
@Test func anAddressThatCannotBeReadForOneLookIsNotAMove() async {
    let surface = FakeSurface(HoldSurface(app: "Safari", title: "Doc", url: "https://a.com/doc"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Safari", title: "Doc", url: nil)
    await hold.tick()
    surface.current = HoldSurface(app: "Safari", title: "Doc", url: "https://a.com/doc")
    await hold.tick()
    expectEq(batches.all.count, 0, "la misma pagina")
    surface.current = HoldSurface(app: "Safari", title: "Doc", url: "https://b.com")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event),
             [.surfaceChanged(app: "Safari", title: "Doc", url: "https://b.com")],
             "otro sitio con el mismo titulo si es un movimiento")
}

@Test func aPageAddressIsNormalisedAndOddOnesAreRefused() {
    expectEq(SystemHoldSurface.pageURL("HTTPS://Example.com/a?x=1"), "https://Example.com", "esquema en minusculas")
    expectEq(SystemHoldSurface.pageURL("http://[::1]:8080/a#f"), "http://[::1]:8080", "puerto e IPv6 sobreviven")
    expectEq(SystemHoldSurface.pageURL("https://example.com?x=1"), "https://example.com", "sin query")
    expectEq(SystemHoldSurface.pageURL("https://a.com/reset/abc123"), "https://a.com", "la ruta no se guarda")
    for odd in ["", "not a url", "http://", "https:///path", "https://user@/x", "ftp://a.com/f", "data:text/plain,hola"] {
        expectEq(SystemHoldSurface.pageURL(odd), nil, "\(odd) no es una pagina")
    }
}

// Code review (b2b-1): a dialog missed for one look is not closed and opened again.
@Test func aDialogMissedForOneLookIsNotOpenedAgain() async {
    let surface = FakeSurface(HoldSurface(app: "Pages", title: "Informe"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar")
    await hold.tick()
    surface.current = HoldSurface(app: "Pages", title: "Informe")
    await hold.tick()
    surface.current = HoldSurface(app: "Pages", title: "Informe", dialog: "Guardar")
    await hold.tick()
    expectEq(batches.all.last?.events.map(\.event), [.dialogOpened(title: "Guardar")], "una sola vez")
}

// Security review (b2b-1): a hostile page title is kept only as long as anything can show it.
@Test func aHugeTitleIsCut() async {
    let surface = FakeSurface(HoldSurface(app: "Safari", title: "a"))
    let hold = observer(surface, FakePasteboard(changeCount: 1, string: nil))
    let batches = Batches()
    await hold.start(generation: 1) { batches.add($0) }
    let huge = String(repeating: "x", count: 10_000)
    surface.current = HoldSurface(app: "Safari", title: huge, dialog: huge)
    await hold.tick()
    let events = batches.all.last?.events.map(\.event) ?? []
    expectEq(events, [.surfaceChanged(app: "Safari", title: String(huge.prefix(HoldSurface.textLimit)), url: nil),
                      .dialogOpened(title: String(huge.prefix(HoldSurface.textLimit)))],
             "titulo y dialogo cortados a \(HoldSurface.textLimit)")
}
