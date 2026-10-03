import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Wave 16i-1 (spec 16i §2, §5, §9, §11): the island never shows an open
// panel with nothing in it, peeks under the pointer like NotchNook before it
// opens, draws its own popovers, and says "stopped" and "couldn't hear" as
// Incredible does.

@Test @MainActor func islandUsefulTests() async {
    testNoPanelIsOpenAndEmpty()
    testThePeekGrowsTheNotchAndCastsAShadow()
    testThePeekIsLivelyAndWaitsBeforeOpening()
    testOpeningFromThePeekNeverShrinks()
    testPopoversAndTooltipsHaveTheirBudget()
    testStopIsTheOrbWhileItSpeaks()
    testCancelledIsAShortPill()
    await testCouldntHearIsACardWithAWayOut()
    testTheNoticeCountsDown()
    testTheVoiceVolumeNeverReadsAsUnset()
    await testTheNewWordsAreInBothLanguages()
}

private let notch = NotchGeometry.notch(on: ScreenShape(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
    safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))

/// Karen's 18:01 recording: an empty black panel showed while opening and
/// while closing. Content now rides the growing panel and leaves with it.
@MainActor func testNoPanelIsOpenAndEmpty() {
    for from in IslandState.Size.allCases {
        for to in IslandState.Size.allCases where from != to {
            let empty = IslandMotion.emptyPanel(from: from, to: to)
            expect(empty <= 0.04 + 1e-9, "motion: \(from)→\(to) deja el panel vacío \(empty) s")
        }
    }
    expect(IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false) < IslandMotion.secondPhase,
           "abrir: el contenido ya entra mientras la forma crece, recortado por ella")
    let closing = IslandMotion.steps(from: .card, to: .pebble, reduceMotion: false)
    expectEq(closing.first?.delay, 0, "cerrar: la forma se recoge a la vez que el contenido se va")
    expect(IslandMotion.closeFade <= MotionCurve.settledAt(MotionCurve.standard, duration: IslandMotion.shapeClose.duration),
           "cerrar: el contenido se ha ido antes de que la forma llegue")
}

/// NotchNook, measured (spec 16i §11): +20 × +9 pt and a soft shadow.
@MainActor func testThePeekGrowsTheNotchAndCastsAShadow() {
    let rest = CGSize(width: notch.width, height: notch.height)
    let peek = IslandChrome.peekSize(notch: notch)
    expectEq(peek, CGSize(width: notch.width + 20, height: notch.height + 9), "asomo: la muesca crece un poco")
    expectEq(IslandChrome.hitSize(base: rest, peeking: true, resting: true, notch: notch), peek,
             "asomo: el área de clic es la forma asomada")
    expectEq(IslandChrome.hitSize(base: rest, peeking: false, resting: true, notch: notch), rest,
             "sin asomo: la muesca")
    let open = CGSize(width: 492, height: 300)
    expectEq(IslandChrome.hitSize(base: open, peeking: true, resting: false, notch: notch), open,
             "abierta: el asomo no la achica")
    // Security review 16i-1 (LOW): the peek is only drawn at rest, so only
    // at rest may it widen what takes clicks.
    let low = CGSize(width: 320, height: notch.height)
    expectEq(IslandChrome.hitSize(base: low, peeking: true, resting: false, notch: notch), low,
             "abierta y baja: el asomo no agranda el área más allá de la forma")
    expectEq(IslandChrome.shadowOpacity(resting: true, peeking: false), 0, "reposo: es hardware, sin sombra")
    expectEq(IslandChrome.shadowOpacity(resting: true, peeking: true), 1, "asomo: la sombra aparece")
    expectEq(IslandChrome.shadowOpacity(resting: false, peeking: false), 1, "abierta: con sombra")
}

@MainActor func testThePeekIsLivelyAndWaitsBeforeOpening() {
    expectEq(IslandMotion.peekDwell, 0.15, "asomo: abre si el puntero se queda 150 ms")
    let peek = MotionSpring.islandPeek
    expect(peek.overshoot > 0.03 && peek.overshoot <= 0.08,
           "asomo: rebote visible y acotado como NotchNook, \(peek.overshoot)")
    expect(peek.settle <= 0.5, "asomo: asentado en medio segundo, \(peek.settle) s")
    expect(!MotionSpring.all.contains { $0.0 == "islandPeek" }, "M4: el asomo es la excepción nombrada")
    expect(MotionSpring.lively.contains { $0.0 == "islandPeek" }, "M4: y vive en la lista de excepciones")
    for (name, spring) in MotionSpring.lively {
        expect(spring.overshoot <= 0.08, "M4: \(name) rebota \(spring.overshoot)")
    }
}

@MainActor func testOpeningFromThePeekNeverShrinks() {
    let peek = IslandChrome.peekSize(notch: notch)
    let target = CGSize(width: 492, height: 200)
    let pill = IslandChrome.size(of: .pill, target: target, notch: notch, from: peek)
    expect(pill.width >= peek.width && pill.height >= peek.height, "abrir desde el asomo: nada salta hacia atrás")
    expectEq(IslandChrome.size(of: .pill, target: target, notch: notch, from: .zero),
             CGSize(width: IslandChrome.pillWidth, height: notch.height), "abrir en frío: la píldora de siempre")
}

/// transitions.dev menu dropdown and tooltip, in the island (spec 16i §2).
@MainActor func testPopoversAndTooltipsHaveTheirBudget() {
    let popover = IslandMotionBudget.popover
    expectEq(popover.openDuration, 0.25, "popover: entra en 250 ms")
    expectEq(popover.closeDuration, 0.15, "popover: sale en 150 ms")
    expectEq(popover.fromScale, 0.97, "popover: crece desde 0,97")
    let tip = IslandMotionBudget.tooltip
    expectEq(tip.delay, 0.08, "tooltip: espera 80 ms")
    expectEq(tip.inDuration, 0.15, "tooltip: entra en 150 ms")
    expectEq(tip.outDuration, 0.05, "tooltip: sale en 50 ms")
    expectEq(IslandMotionBudget.iconSwap.fromScale, 0.25, "icon swap: el orb se vuelve parar desde 0,25")
    expectEq(IslandMotionBudget.iconSwap.duration, 0.2, "icon swap: 200 ms")
}

@MainActor func testStopIsTheOrbWhileItSpeaks() {
    let speaking = IslandState(size: .bar, meter: .agent, line: .speaking, showsStop: true)
    expect(IslandStop.asOrb(speaking), "hablando: el orb es el botón rojo de parar")
    expect(!IslandStop.asChip(speaking), "hablando: sin chip repetido")
    let thinking = IslandState(size: .bar, line: .thinking, showsStop: true)
    expect(!IslandStop.asOrb(thinking), "pensando: el orb no")
    expect(IslandStop.asChip(thinking), "pensando: el chip Parar")
}

@MainActor func testCancelledIsAShortPill() {
    let idle = SessionProjection()
    let cancelled = IslandState.from(idle, pebbleHidden: false, cancelled: true)
    expectEq(cancelled.size, .bar, "cancelado: la píldora bajo la muesca")
    expectEq(cancelled.line, .cancelled, "cancelado: dice que paró")
    expectEq(IslandState.from(idle, pebbleHidden: false, composing: true, cancelled: true).size, .nudge,
             "cancelado: escribir gana")
    expectEq(IslandState.from(idle, pebbleHidden: false).line, IslandState.Line.none, "sin cancelar: reposo")
    expectEq(IslandStop.cancelledFor, 2, "cancelado: 2 s")
}

/// The 18:10 capture of Incredible (spec 16i §9).
@MainActor func testCouldntHearIsACardWithAWayOut() async {
    await Localized.scoped(to: .es) {
        let card = IslandNotice.content(for: .couldntHear)
        expectEq(card?.symbol, "mic.slash.fill", "no te oí: micrófono tachado")
        expectEq(card?.title, Localized.string("island.notice.couldntHear.title"), "no te oí: título corto")
        expectEq(card?.lifetime, SessionMachine.noticeDelay, "no te oí: se va sola a los 6 s")
        expectEq(card?.action, .openPermission(.micDenied), "no te oí: revisar micrófono")
        let keys = IslandNotice.content(for: .failure(.noProviders))
        expectEq(keys?.action, .openKeys, "sin claves: abre Claves")
        expectEq(keys?.lifetime, nil, "sin claves: no se va sola")
        expectEq(IslandNotice.content(for: .thinking), nil, "pensando: no es un aviso")
        let notice = IslandState.from(
            { var p = SessionProjection(); p.notice = .couldntHear; return p }(), pebbleHidden: false)
        expectEq(notice.size, .card, "no te oí: tarjeta ancha, no la barra")
    }
}

@MainActor func testTheNoticeCountsDown() {
    expectEq(IslandNotice.remaining(elapsed: 0, lifetime: 6), 1, "anillo: lleno al salir")
    expectEq(IslandNotice.remaining(elapsed: 3, lifetime: 6), 0.5, "anillo: a la mitad")
    expectEq(IslandNotice.remaining(elapsed: 9, lifetime: 6), 0, "anillo: nunca negativo")
    expectEq(IslandNotice.remaining(elapsed: -1, lifetime: 6), 1, "anillo: nunca más que lleno")
}

/// 0 in the stored preferences means "never set" and reads back as 100 %.
@MainActor func testTheVoiceVolumeNeverReadsAsUnset() {
    expectEq(IslandVolume.clamped(0), IslandVolume.floor, "volumen: el mínimo no se lee como sin ajustar")
    expectEq(IslandVolume.clamped(2), 1, "volumen: tope 100 %")
    expectEq(IslandVolume.clamped(0.5), 0.5, "volumen: en medio, tal cual")
    expectEq(IslandVolume.percent(0.456), 46, "volumen: por ciento redondeado")
}

@MainActor func testTheNewWordsAreInBothLanguages() async {
    let keys = ["island.cancelled", "island.tip.talk", "island.tip.send", "island.tip.stop",
                "island.tip.volume", "island.volume", "island.notice.couldntHear.title",
                "island.notice.couldntHear.body", "island.notice.checkMic", "island.notice.dismiss"]
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in keys {
                expect(Localized.string(key) != key, "\(language): \(key) está en el catálogo")
            }
        }
    }
}

/// Security review 16i-1 (HIGH): a display or menu-bar change moved the
/// notch but kept the old click area, so an invisible strip beside the
/// smaller notch ate clicks meant for the menu bar.
@Test @MainActor func aNotchChangeResizesTheClickArea() {
    let wide = hardwareNotch(aux: 662, top: 38)
    let narrow = hardwareNotch(aux: 690, top: 32)
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(notch: wide), onHover: { _ in })
    // The panel docks on this Mac's real screen when built; pin the notch.
    panel.renotch(wide)
    panel.present(size: .pebble, contentHeight: 0)
    expectEq(panel.hitArea, CGSize(width: 188, height: 38), "reposo: el área es la muesca")
    panel.renotch(narrow)
    expectEq(panel.hitArea, CGSize(width: 132, height: 32), "muesca nueva: el área la sigue")
    panel.orderOut(nil)
}

/// Code review 16i-1 (MEDIUM): hiding while hovered left a late leave task
/// that told the session "left" after the island was back under a still pointer.
@Test @MainActor func hidingEndsTheHoverAtOnce() async throws {
    let notch = hardwareNotch(aux: 662, top: 38)
    var heard: [Bool] = []
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(notch: notch),
                            onHover: { heard.append($0) })
    panel.renotch(notch)
    panel.present(size: .pebble, contentHeight: 0)
    panel.track(CGPoint(x: 756, y: 970))
    // The main actor is shared with the whole suite: wait for the dwell,
    // bounded, instead of guessing how long it takes under load.
    for _ in 0..<50 where heard.isEmpty {
        try await Task.sleep(for: .seconds(IslandMotion.peekDwell))
    }
    expectEq(heard, [true], "hover: se queda y abre")
    panel.present(size: .hidden, contentHeight: 0)
    expectEq(heard, [true, false], "ocultar: el hover termina ya, no un rato después")
    expect(!panel.geometry.peeking, "ocultar: sin asomo")
    panel.present(size: .pebble, contentHeight: 0)
    try await Task.sleep(for: .seconds(MotionTime.fast + 0.1))
    expectEq(heard, [true, false], "volver: ningún aviso tardío")
    panel.orderOut(nil)
}

private func hardwareNotch(aux: CGFloat, top: CGFloat) -> Notch {
    NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 982 - top,
        safeTop: top, leftAuxWidth: aux, rightAuxWidth: aux))
}
