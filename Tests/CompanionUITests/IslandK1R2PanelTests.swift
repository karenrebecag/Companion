import AppKit
import CompanionCore
import CoreGraphics
@testable import CompanionUI
import CompanionTestKit
import SwiftUI
import Testing

private final class HoverLog: @unchecked Sendable {
    var heard: [Bool] = []
}

/// One hovered panel at a time. A screen-parameter notification reaches
/// every panel, so two hover tests would close each other.
@MainActor enum PanelHoverGate {
    private static var locked = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []

    static func enter() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    static func leave() {
        if waiters.isEmpty {
            locked = false
            return
        }
        waiters.removeFirst().resume()
    }
}

@MainActor private func hoveredPanel(_ log: HoverLog) async throws -> IslandPanel {
    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 982 - 38,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(notch: notch),
                            onHover: { log.heard.append($0) })
    panel.renotch(notch)
    panel.present(size: IslandState.Size.pebble, contentHeight: 0)
    panel.track(CGPoint(x: 756, y: 970))
    for _ in 0..<50 where !log.heard.contains(true) {
        try await Task.sleep(for: .seconds(IslandMotion.peekDwell))
    }
    expectEq(log.heard, [true], "K1: el puntero abre y la sesión se entera")
    return panel
}

// A fixed base and binary-exact steps: Date() carries a fraction that makes
// a speed that sits exactly on 450 pt/s round either way.
private let base = Date(timeIntervalSinceReferenceDate: 1_000)

@Test @MainActor func k1R2FastThenSlowDwells() {
    var tracker = HoverTracker()
    _ = tracker.pointer(at: .zero, now: base, inside: true)
    let fast = tracker.pointer(
        at: CGPoint(x: 62.5, y: 0), now: base.addingTimeInterval(0.125), inside: true)
    let slow = tracker.pointer(
        at: CGPoint(x: 118.75, y: 0), now: base.addingTimeInterval(0.25), inside: true)
    expectEq(fast, .dwell(0.3), "K1: un cruce rápido (500 pt/s) espera 300 ms")
    expectEq(slow, .dwell(0.15), "K1: el siguiente, lento (450 pt/s), espera 150 ms")
}

@Test @MainActor func k1R2TheFastBoundaryIsMeasured() {
    var edge = HoverTracker()
    _ = edge.pointer(at: .zero, now: base, inside: true)
    expectEq(edge.pointer(at: CGPoint(x: 56.25, y: 0), now: base.addingTimeInterval(0.125), inside: true),
             .dwell(0.15), "K1: 450 pt/s exactos siguen en 150 ms")

    var below = HoverTracker()
    _ = below.pointer(at: .zero, now: base, inside: true)
    expectEq(below.pointer(at: CGPoint(x: 56, y: 0), now: base.addingTimeInterval(0.125), inside: true),
             .dwell(0.15), "K1: por debajo de 450 pt/s espera 150 ms")

    var above = HoverTracker()
    _ = above.pointer(at: .zero, now: base, inside: true)
    expectEq(above.pointer(at: CGPoint(x: 56.5, y: 0), now: base.addingTimeInterval(0.125), inside: true),
             .dwell(0.3), "K1: por encima de 450 pt/s espera 300 ms")
}

@Test @MainActor func k1R2LeavingJustAfterOpenWaitsTheRemainder() {
    var tracker = HoverTracker()
    let opened = base
    tracker.markOpened(at: opened)
    let leave = tracker.pointer(
        at: CGPoint(x: 8, y: 8), now: opened.addingTimeInterval(0.1), inside: false)
    expectEq(leave, .leave(0.25), "K1: salir 0,1 s después de abrir espera la caída de nivel")
    var fresh = HoverTracker()
    fresh.markOpened(at: opened)
    let early = fresh.pointer(
        at: CGPoint(x: 8, y: 8), now: opened.addingTimeInterval(0.02), inside: false)
    expectEq(early, .leave(0.28), "K1: salir 0,02 s después de abrir espera lo que falta de la histéresis")
}

@Test @MainActor func k1R2AStaleSampleCountsAsFirst() {
    var tracker = HoverTracker()
    let start = base
    _ = tracker.pointer(at: .zero, now: start, inside: true)
    _ = tracker.pointer(at: CGPoint(x: 500, y: 0), now: start.addingTimeInterval(0.1), inside: true)
    tracker.reset()
    let again = tracker.pointer(
        at: CGPoint(x: 900, y: 0), now: start.addingTimeInterval(0.11), inside: true)
    expectEq(again, .dwell(IslandMotion.peekDwell), "K1: una muestra vieja no cuenta")
}

@Test @MainActor func k1R2TheLiteralsStayPut() {
    expectEq(SessionMachine.settleDelay, 0.2, "0.2")
    expectEq(SessionMachine.settleFloor, 1.5, "1.5")
    expectEq(IslandMotion.peekDwell, 0.15, "0.15")
    expectEq(IslandMotion.fastHoverDwell, 0.3, "0.3")
    expectEq(IslandMotion.fastPointer, 450, "450")
    expectEq(IslandMotion.levelDrop, 0.25, "0.25")
    expectEq(IslandMotion.hoverHysteresis, 0.3, "0.3")
}

@Test @MainActor func k1R2HidingSendsTheLeave() async throws {
    await PanelHoverGate.enter()
    defer { PanelHoverGate.leave() }
    let log = HoverLog()
    let panel = try await hoveredPanel(log)
    panel.present(size: IslandState.Size.hidden, contentHeight: 0)
    expectEq(log.heard, [true, false], "K1: ocultar avisa que el puntero se fue")
    panel.orderOut(nil)
}

@Test @MainActor func k1R4AFlickBeforeTheDwellStillSendsTheLeave() async throws {
    await PanelHoverGate.enter()
    defer { PanelHoverGate.leave() }
    let log = HoverLog()
    let notch = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 982 - 38,
        safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662))
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(notch: notch),
                            onHover: { log.heard.append($0) })
    panel.renotch(notch)
    panel.present(size: IslandState.Size.pebble, contentHeight: 0)
    panel.track(CGPoint(x: 756, y: 970))
    panel.track(CGPoint(x: 100, y: 100))
    for _ in 0..<100 where log.heard.isEmpty {
        try await Task.sleep(for: .seconds(0.01))
    }
    expectEq(log.heard, [false],
             "K1: entrar y salir antes del dwell avisa la salida, por si la tarjeta perdió la suya")
    await settle(0.2)
    expectEq(log.heard, [false], "K1: y nada más llega después, ni el dwell que ya no cuenta")
    panel.orderOut(nil)
}

@Test @MainActor func k1R3HidingForgetsThePointerApproach() async throws {
    await PanelHoverGate.enter()
    defer { PanelHoverGate.leave() }
    let log = HoverLog()
    let panel = try await hoveredPanel(log)
    expect(panel.hover.hasSample, "K1: el panel guarda la muestra del puntero que abrió")
    panel.present(size: IslandState.Size.hidden, contentHeight: 0)
    expect(!panel.hover.hasSample,
           "K1: ocultar olvida la aproximación, así el siguiente dwell es peekDwell")
    panel.orderOut(nil)
}

@Test @MainActor func k1R2RenotchSendsTheLeave() async throws {
    await PanelHoverGate.enter()
    defer { PanelHoverGate.leave() }
    let log = HoverLog()
    let panel = try await hoveredPanel(log)
    let moved = NotchGeometry.notch(on: ScreenShape(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 982 - 32,
        safeTop: 32, leftAuxWidth: 690, rightAuxWidth: 690))
    panel.renotch(moved)
    expectEq(log.heard, [true, false], "K1: cambiar de muesca avisa que el puntero se fue")
    panel.orderOut(nil)
}

@Test @MainActor func k1R2ScreenChangeSendsTheLeave() async throws {
    await PanelHoverGate.enter()
    defer { PanelHoverGate.leave() }
    let log = HoverLog()
    let panel = try await hoveredPanel(log)
    NotificationCenter.default.post(
        name: NSApplication.didChangeScreenParametersNotification, object: nil)
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { done.resume() }
    }
    expectEq(log.heard, [true, false], "K1: un cambio de pantalla avisa la salida en el acto")
    panel.orderOut(nil)
}
