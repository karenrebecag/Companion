import CompanionCore
import Foundation
import Testing

// Wave 20d B/C. An action that ran without the sheet leaves a receipt on the
// island for a few seconds, with the one way back. Only the user's press
// undoes; nothing the model says reaches this path.

@Test func undoReceiptTests() {
    testAReceiptShowsAndExpires()
    testUndoIsThePressOfTheMatchingReceiptOnly()
    testANewerReceiptReplacesTheOlderAndAnExpiredOneCannotBeUndone()
    testAJobStepCanLeaveAReceipt()
    testTheIslandShowsTheReceiptWhateverItDoes()
}

private let receipt = UndoReceipt(
    id: UUID(), kind: .created, subject: "Brief.pdf", undo: .trash(path: "/work/Brief.pdf", size: 1, modified: Date(timeIntervalSince1970: 0)))

func testAReceiptShowsAndExpires() {
    var m = SessionMachine()
    let fx = m.handle(.actionDone(receipt))
    expectEq(m.projection.receipt, receipt, "recibo: queda en la proyección")
    expect(fx.contains(.scheduleReceiptExpiry(id: receipt.id, UndoReceipt.undoWindow)), "recibo: se agenda su fin")
    _ = m.handle(.receiptExpired(id: UUID()))
    expectEq(m.projection.receipt, receipt, "recibo: el fin de otro no lo quita")
    _ = m.handle(.receiptExpired(id: receipt.id))
    expectEq(m.projection.receipt, nil, "recibo: vence a su hora")
}

func testUndoIsThePressOfTheMatchingReceiptOnly() {
    var m = SessionMachine()
    _ = m.handle(.actionDone(receipt))
    expect(m.handle(.undoPressed(id: UUID())).isEmpty, "deshacer: otro id no hace nada")
    expectEq(m.projection.receipt, receipt, "deshacer: el recibo sigue")
    let fx = m.handle(.undoPressed(id: receipt.id))
    expect(fx.contains(.undo(receipt)), "deshacer: su pulsación pide el efecto")
    expectEq(m.projection.receipt, nil, "deshacer: el recibo se va")
    expect(m.handle(.undoPressed(id: receipt.id)).isEmpty, "deshacer: una vez")
}

func testANewerReceiptReplacesTheOlderAndAnExpiredOneCannotBeUndone() {
    var m = SessionMachine()
    let second = UndoReceipt(id: UUID(), kind: .wrote, subject: "A1", undo: nil)
    _ = m.handle(.actionDone(receipt))
    _ = m.handle(.actionDone(second))
    expectEq(m.projection.receipt, second, "recibos: el nuevo reemplaza al anterior")
    expect(m.handle(.undoPressed(id: receipt.id)).isEmpty, "recibos: el anterior ya no se puede deshacer")
    _ = m.handle(.receiptExpired(id: second.id))
    expect(m.handle(.undoPressed(id: second.id)).isEmpty, "recibos: vencido, deshacer no hace nada")
}

func testAJobStepCanLeaveAReceipt() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.acted(receipt)))
    expectEq(m.projection.receipt, receipt, "encargo: su recibo llega a la isla")
}

func testTheIslandShowsTheReceiptWhateverItDoes() {
    var m = SessionMachine()
    _ = m.handle(.actionDone(receipt))
    let idle = IslandState.from(m.projection, pebbleHidden: false)
    expectEq(idle.receipt, receipt, "isla: en reposo")
    expectEq(idle.light, .green, "isla: luz verde, hecho")
    expect(idle.size != .hidden && idle.size != .pebble, "isla: el recibo tiene dónde vivir")
    _ = m.handle(.job(.started(goal: "otro")))
    expectEq(IslandState.from(m.projection, pebbleHidden: false).receipt, receipt, "isla: con un encargo en curso")
    _ = m.handle(.receiptExpired(id: receipt.id))
    expectEq(IslandState.from(m.projection, pebbleHidden: true).receipt, nil, "isla: sin recibo, nada")
}
