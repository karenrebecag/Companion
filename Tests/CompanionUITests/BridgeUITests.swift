import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

// Wave 17-2 (App + UI): the reducer's two new events, what the island decides
// from them, the "Lend your hands" preference, and the catalog strings the
// island action and the status menu read.

@Test @MainActor func bridgeUITests() async {
    await pinLanguage {
        testHandsLentRoundTrips()
        testHandsActedBumpsThePulseAndWraps()
        testHandsLentDoesNotTouchOtherFields()
        testIslandKeepsRestingSizeWhileHandsAreLent()
        testIslandLeavesACardSheetAloneButStillSetsHands()
        testIslandWithoutASessionHasNoHandsChip()
        testHandsLendingPreferenceDefaultsToOffAndNotifiesOnRealChangeOnly()
        await testStopHandsCatalogStrings()
    }
}

/// `.handsLent` sets and clears `handsLentTo`; independent of `kind`.
@MainActor func testHandsLentRoundTrips() {
    var m = SessionMachine()
    _ = m.handle(.handsLent(client: "Claude Code"))
    expectEq(m.projection.handsLentTo, "Claude Code", "handsLent: guarda el cliente")
    expectEq(m.projection.kind, .idle, "handsLent: no mueve el kind")
    _ = m.handle(.handsLent(client: nil))
    expectEq(m.projection.handsLentTo, nil, "handsLent: nil cierra la sesión")
}

/// `.handsActed` bumps the pulse and wraps at 1000 so the island can key a
/// one-shot animation off a value that keeps moving.
@MainActor func testHandsActedBumpsThePulseAndWraps() {
    var m = SessionMachine()
    _ = m.handle(.handsActed)
    expectEq(m.projection.handsPulse, 1, "handsActed: incrementa")
    _ = m.handle(.handsActed)
    expectEq(m.projection.handsPulse, 2, "handsActed: sigue incrementando")
    for _ in 0 ..< 998 { _ = m.handle(.handsActed) }
    expectEq(m.projection.handsPulse, 0, "handsActed: envuelve en 1000")
}

/// A bridge session sits alongside an ordinary turn without disturbing it —
/// `begin()` (called on most transitions) must not clear the hands fields.
@MainActor func testHandsLentDoesNotTouchOtherFields() {
    var m = SessionMachine()
    _ = m.handle(.handsLent(client: "Claude Code"))
    _ = m.handle(.pressed)
    expectEq(m.projection.handsLentTo, "Claude Code", "handsLent: un turno propio no lo apaga")
    _ = m.handle(.released)
    _ = m.handle(.handsActed)
    expectEq(m.projection.handsLentTo, "Claude Code", "handsLent: sigue prestado tras un turno")
}

/// Nothing paints `state.hands`, and `.nudge` paints the full panel: growing the
/// island for the chip left the chat open for the whole bridge session. At rest
/// the hands indicator is the screen aura, so the size must stay the resting one.
@MainActor func testIslandKeepsRestingSizeWhileHandsAreLent() {
    var idle = SessionProjection()
    idle.handsLentTo = "Claude Code"
    let atRest = IslandState.from(idle, pebbleHidden: true)
    expectEq(atRest.hands, "Claude Code", "isla: el estado lleva el cliente")
    expectEq(atRest.size, IslandState.from(SessionProjection(), pebbleHidden: true).size,
             "isla: prestar las manos no cambia el tamano en reposo (hidden)")
    let pebble = IslandState.from(idle, pebbleHidden: false)
    expectEq(pebble.size, IslandState.from(SessionProjection(), pebbleHidden: false).size,
             "isla: prestar las manos no cambia el tamano en reposo (pebble)")

    var listening = SessionProjection()
    listening.kind = .listening
    listening.handsLentTo = "Claude Code"
    let bar = IslandState.from(listening, pebbleHidden: false)
    expectEq(bar.size, .bar, "isla: un tamaño ya mayor no se toca")
    expectEq(bar.hands, "Claude Code", "isla: el chip sigue presente")
}

/// The approval sheet outranks the chip's own growth rule, but the chip
/// itself keeps showing — "cuando `approval != nil` deja la hoja como está,
/// `hands` sigue puesto" (spec §1).
@MainActor func testIslandLeavesACardSheetAloneButStillSetsHands() {
    var p = SessionProjection()
    p.handsLentTo = "Claude Code"
    p.approvalQueue = [ApprovalRequest(requestId: "1", toolName: "x", summary: "s", inputJSON: "{}")]
    let state = IslandState.from(p, pebbleHidden: true)
    expectEq(state.size, .card, "isla: la hoja de aprobación manda el tamaño")
    expect(state.approval != nil, "isla: la hoja sigue ahí")
    expectEq(state.hands, "Claude Code", "isla: el chip no desaparece bajo la hoja")
}

@MainActor func testIslandWithoutASessionHasNoHandsChip() {
    let state = IslandState.from(SessionProjection(), pebbleHidden: false)
    expect(state.hands == nil, "isla: sin sesión del puente, sin chip")
}

@MainActor func testHandsLendingPreferenceDefaultsToOffAndNotifiesOnRealChangeOnly() {
    let original = HandsLendingPreference.enabled
    defer { HandsLendingPreference.enabled = original }
    UserDefaults.standard.removeObject(forKey: "companion.lendHands")
    expect(!HandsLendingPreference.enabled, "ajuste: apagado por defecto (P1, spec §3)")

    let counter = NotifyCounter17()
    let observer = NotificationCenter.default.addObserver(
        forName: .companionHandsLendingDidChange, object: nil, queue: nil
    ) { _ in counter.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }

    HandsLendingPreference.enabled = false
    expectEq(counter.count, 0, "ajuste: repetir el mismo valor no avisa")
    HandsLendingPreference.enabled = true
    expectEq(counter.count, 1, "ajuste: encenderlo sí avisa")
    HandsLendingPreference.enabled = true
    expectEq(counter.count, 1, "ajuste: encenderlo otra vez no avisa de nuevo")
    HandsLendingPreference.enabled = false
    expectEq(counter.count, 2, "ajuste: apagarlo también avisa")
}

/// The island action and the status menu both read "Stop hands" from the
/// catalog, under different keys (spec §2 vs §4) — both must be non-empty
/// and vary by language, or the app goes monolingual again silently. The
/// hands chip itself was retired in 16p-2.
@MainActor func testStopHandsCatalogStrings() async {
    await Localized.scoped(to: .en) {
        expectEq(IslandCopy.action(.stopHands), "Stop hands", "isla: acción Detener manos, en")
    }
    await Localized.scoped(to: .es) {
        expectEq(IslandCopy.action(.stopHands), "Detener manos", "isla: acción Detener manos, es")
        expectEq(Localized.string("menu.stopHands"), "Detener manos", "menú: Detener manos, es")
    }
}

private final class NotifyCounter17: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func increment() { lock.withLock { _count += 1 } }
}
