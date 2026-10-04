import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// P2: as in Incredible, a turn in passive does not open the island; the voice line
// chip (P3) carries it. What needs the user (the sheet, a notice, the undo, the hands)
// still shows.

private let aiPhases: [SessionPhase] = [.pending, .thinking, .toolExecuting, .speaking,
                                        .subAgentRunning, .completed]

private func projection(_ phase: SessionPhase, _ presence: Presence) -> SessionProjection {
    var p = SessionProjection()
    p.kind = .processing(phase)
    p.voice = .live
    p.presence = presence
    return p
}

@Test func aTurnInPassiveLeavesTheIslandAtRest() {
    for phase in aiPhases {
        let state = IslandState.from(projection(phase, .passive), pebbleHidden: false)
        expectEq(state.size, .pebble, "\(phase): la isla no se abre")
        expectEq(state.line, .none, "\(phase): sin linea")
        expect(!state.showsStop, "\(phase): sin boton en una isla cerrada")
        expect(state.quietTurn, "\(phase): el turno lo lleva el chip")
    }
}

@Test func anActiveTurnOpensTheIslandAsBefore() {
    for phase in aiPhases {
        let state = IslandState.from(projection(phase, .active), pebbleHidden: false)
        expect(state.size != .pebble, "\(phase): activo, la isla se abre")
        expect(!state.quietTurn, "\(phase): sin chip")
    }
}

// Security review (P1, for P2): what needs the user always shows, passive or not.
@Test func theSheetStillShowsInPassive() {
    var p = projection(.toolExecuting, .passive)
    p.approvalQueue = [ApprovalRequest(requestId: "r", toolName: "enviar", summary: "Enviar", inputJSON: "{}")]
    let state = IslandState.from(p, pebbleHidden: true)
    expectEq(state.size, .card, "la hoja abre la isla")
    expectEq(state.approval?.requestId, "r", "y se ve")
    expectEq(state.light, .amber, "con su luz")
}

@Test func aNoticeTheUndoAndTheHandsStillShowInPassive() {
    var notice = projection(.thinking, .passive)
    notice.kind = .idle
    notice.notice = .replyCut
    expectEq(IslandState.from(notice, pebbleHidden: false).line, .replyCut, "un aviso se ve")

    var receipt = projection(.speaking, .passive)
    receipt.receipt = UndoReceipt(id: UUID(), kind: .created, subject: "Brief.pdf",
                                  undo: .trash(path: "/w/Brief.pdf", size: 1, modified: Date(timeIntervalSince1970: 0)))
    let undo = IslandState.from(receipt, pebbleHidden: false)
    expectEq(undo.size, .nudge, "el deshacer abre lo justo")
    expect(undo.receipt != nil, "y se puede deshacer")

    var hands = projection(.toolExecuting, .passive)
    hands.handsLentTo = "Claude Code"
    let lent = IslandState.from(hands, pebbleHidden: false)
    expectEq(lent.hands, "Claude Code", "el chip de manos sigue")
    expectEq(lent.size, .nudge, "con lugar donde verse")
}

// What the user started is theirs: a dictation is never quieted, and in passive a
// press would already have made it active.
@Test func aDictationIsNeverQuieted() {
    var p = projection(.pending, .passive)
    p.dictation = "Notas"
    let state = IslandState.from(p, pebbleHidden: false)
    expectEq(state.line, .pasting, "el dictado se ve")
    expect(!state.quietTurn, "no es un turno de la IA")
}

// Security review (P2): something running is never invisible, even on an island the
// user hid with the voice off.
@Test func aQuietTurnAlwaysKeepsThePebble() {
    for phase in aiPhases {
        var p = projection(phase, .passive)
        p.voice = .off
        let state = IslandState.from(p, pebbleHidden: true)
        expectEq(state.size, .pebble, "\(phase): oculta y sin voz, igual queda el pebble")
        expect(state.quietTurn, "\(phase): sigue siendo un turno quieto")
    }
    var idle = SessionProjection()
    idle.presence = .passive
    expectEq(IslandState.from(idle, pebbleHidden: true).size, .hidden, "en reposo, la eleccion del usuario manda")
}

// QA review (P2): the light on a quiet turn says only that it finished.
@Test func aQuietTurnLightsGreenOnlyWhenItFinishes() {
    for phase in aiPhases {
        let light = IslandState.from(projection(phase, .passive), pebbleHidden: false).light
        expectEq(light, phase == .completed ? .green : IslandState.Light.none, "\(phase): luz")
    }
}

// QA review (P2): a notice raised during a quiet turn shows, through the quiet branch.
@Test func aNoticeDuringAQuietTurnShows() {
    var p = projection(.thinking, .passive)
    p.notice = .replyCut
    let state = IslandState.from(p, pebbleHidden: false)
    expectEq(state.line, .replyCut, "el aviso se ve")
    expectEq(state.size, .card, "como tarjeta")
    expect(state.quietTurn, "el turno sigue sin abrir nada mas")
}

@Test func aSheetDuringAQuietTurnKeepsTheTurnQuiet() {
    var p = projection(.toolExecuting, .passive)
    p.approvalQueue = [ApprovalRequest(requestId: "r", toolName: "enviar", summary: "Enviar", inputJSON: "{}")]
    let state = IslandState.from(p, pebbleHidden: false)
    expectEq(state.light, .amber, "ambar mientras espera")
    expect(state.quietTurn, "la hoja se ve; el turno sigue quieto para el chip")
}

// QA review (P2): the moment the user is back, the same turn opens as always.
@Test func theSameTurnOpensWhenTheUserIsBack() {
    var p = projection(.thinking, .passive)
    expectEq(IslandState.from(p, pebbleHidden: false).size, .pebble, "pasivo, en reposo")
    p.presence = .active
    let state = IslandState.from(p, pebbleHidden: false)
    expectEq(state.size, .bar, "activo, se abre")
    expectEq(state.line, .thinking, "con su linea")
    expect(state.showsStop, "y su boton")
    expect(!state.quietTurn, "ya no es quieto")
}

@Test func aJobInPassiveDoesNotOpenItsCard() {
    var p = projection(.subAgentRunning, .passive)
    p.job = JobTimeline(goal: "Ordenar facturas")
    let state = IslandState.from(p, pebbleHidden: false)
    expectEq(state.size, .pebble, "sin tarjeta")
    expectEq(state.line, .none, "ni linea del job")
}

// QA review (P2): a quiet turn's reply is not on the island, so the model is not told it
// was seen; P3's chip reports it when it actually shows.
@Test func aQuietReplyIsNotReportedAsSeen() {
    expect(!IslandState.from(projection(.speaking, .passive), pebbleHidden: false).reportsReplyShown,
           "pasivo: no se reporta como vista")
    expect(IslandState.from(projection(.speaking, .active), pebbleHidden: false).reportsReplyShown,
           "activo: si")
}
