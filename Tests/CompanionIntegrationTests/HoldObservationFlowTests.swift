import CompanionCore
import CompanionServices
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// QA review (b3): from the hold observer through the companion the overlay draws, the
// same path the app wires, with only the screen and the board faked.

private final class Surface: HoldSurfaceReading, @unchecked Sendable {
    var current: HoldSurface?
    init(_ current: HoldSurface?) { self.current = current }
    func surface() -> HoldSurface? { current }
}

private final class Board: PasteboardReading, @unchecked Sendable {
    var changeCount = 1
    var string: String?
    var fileURLs: [URL] = []
    var hasImage = false
    var concealed = false
}

private final class Batches: @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [HoldObservationBatch] = []
    var all: [HoldObservationBatch] { lock.lock(); defer { lock.unlock() }; return _all }
    func add(_ batch: HoldObservationBatch) { lock.lock(); _all.append(batch); lock.unlock() }
}

@Test @MainActor func whatIsTouchedDuringAHoldReachesTheCompanion() async {
    let surface = Surface(HoldSurface(app: "Notes", title: "Lista"))
    let board = Board()
    let hold = HoldObserver(surface: surface, pasteboard: board, now: { 10 }, polls: false)
    let companion = HoldCompanionModel(now: { 0 }, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
    companion.listening(true)
    let batches = Batches()
    await hold.start(generation: 3) { batches.add($0) }
    surface.current = HoldSurface(app: "Mail", title: "Nuevo")
    await hold.tick()
    board.changeCount = 2
    board.string = "total 42"
    await hold.tick()
    // The app hops each batch to the main actor; here they are handed over in order.
    for batch in batches.all { companion.observe(batch, words: 2) }
    expectEq(companion.state.flash?.kind, .copied, "lo ultimo destella en el orb")
    expectEq(companion.state.stack.map(\.item.kind), [.copied], "la copia se apila; la ventana solo destella")
    expectEq(companion.state.woven("manda esto ya"), "manda esto [\u{201C}total 42\u{201D}] ya",
             "y se teje donde iba la voz")
}
