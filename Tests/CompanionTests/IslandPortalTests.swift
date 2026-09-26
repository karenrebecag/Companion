import CompanionCore
import CompanionUI
import CoreGraphics
import Testing

// Wave 16o-1: tooltips and dropdowns drawn in a portal over the island's
// clip, placed inside the canvas and never under the notch.

private let canvas = CGSize(width: 560, height: 620)
private let notchBand = CGRect(x: 280 - 92, y: 0, width: 184, height: 38)

@Test @MainActor func portalPlacementTests() {
    let size = CGSize(width: 120, height: 28)

    // Room above: centred over the trigger, 4 pt up.
    let orb = CGRect(x: 60, y: 120, width: 36, height: 36)
    let up = PortalPlacement.place(anchor: orb, size: size, canvas: canvas, forbidden: notchBand)
    expectEq(up.side, .above, "16o portal: arriba cuando cabe")
    expectEq(up.origin, CGPoint(x: 18, y: 88), "16o portal: centrado, 4 arriba")

    // A header icon in the notch band: above leaves the canvas, so below, 6 pt down.
    let icon = CGRect(x: 40, y: 4, width: 30, height: 30)
    let down = PortalPlacement.place(anchor: icon, size: size, canvas: canvas, forbidden: notchBand)
    expectEq(down.side, .below, "16o portal: abajo si arriba se sale del lienzo")
    expectEq(down.origin.y, 40, "16o portal: 6 abajo")
    expectEq(down.origin.x, 8, "16o portal: pegado al margen de 8, nunca cortado")

    // Above would cover the notch: below.
    let underNotch = CGRect(x: 250, y: 60, width: 30, height: 30)
    let avoid = PortalPlacement.place(anchor: underNotch, size: size, canvas: canvas, forbidden: notchBand)
    expectEq(avoid.side, .below, "16o portal: nunca bajo la muesca")

    // Right edge: clamped inside with the same margin.
    let right = CGRect(x: 540, y: 200, width: 20, height: 20)
    let clamped = PortalPlacement.place(anchor: right, size: size, canvas: canvas, forbidden: notchBand)
    expectEq(clamped.origin.x, canvas.width - 8 - size.width, "16o portal: ajustado a la derecha")

    // A dropdown prefers below and starts at its trigger's leading edge.
    let menu = PortalPlacement.place(anchor: icon, size: CGSize(width: 230, height: 200), canvas: canvas,
                                     forbidden: notchBand, prefers: .below, align: .leading)
    expectEq(menu.side, .below, "16o menú: cae bajo su botón")
    expectEq(menu.origin, CGPoint(x: 40, y: 40), "16o menú: alineado al borde del botón")
}

@Test @MainActor func portalHitAreaTests() {
    // The canvas hangs from the top of the screen at y = 1000.
    let frame = CGRect(x: 100, y: 380, width: 560, height: 620)
    let popover = CGRect(x: 40, y: 40, width: 230, height: 200)
    let screen = IslandChrome.portalScreenRect(popover, canvas: frame)
    expectEq(screen, CGRect(x: 140, y: 760, width: 230, height: 200), "16o portal: lienzo a pantalla")

    let shape = CGRect(x: 134, y: 900, width: 492, height: 100)
    let inPopoverOnly = CGPoint(x: 200, y: 800)
    expect(IslandChrome.pointerInside(inPopoverOnly, shape: shape, portal: screen),
           "16o clics: el menú abierto recibe clics fuera de la forma")
    expect(!IslandChrome.pointerInside(inPopoverOnly, shape: shape, portal: nil),
           "16o clics: sin menú, solo la forma")
    expect(IslandChrome.pointerInside(CGPoint(x: 300, y: 950), shape: shape, portal: nil),
           "16o clics: la forma sigue recibiendo clics")
}

// Security review 16o (MEDIUM): the header popover only lives in `.nudge`;
// leaving it for any size, open or resting, must close it at once so its
// click area never outlives it.
@Test @MainActor func popoverClosesWhenLeavingNudgeTests() {
    expect(IslandPopoverToggle.survives(size: .nudge), "16o: el menú sigue abierto en nudge")
    for size in [IslandState.Size.hidden, .pebble, .bar, .card] {
        expect(!IslandPopoverToggle.survives(size: size), "16o: el menú se cierra al pasar a \(size)")
    }
}

// Code review 16o (HIGH): switching volume -> menu, the volume popover's late
// disappearance must not erase the menu's click area.
@Test @MainActor func portalFrameOwnershipTests() {
    let menu = CGRect(x: 40, y: 40, width: 230, height: 200)
    expectEq(PortalFrame.next(current: menu, report: nil, from: .volume, active: .menu), menu,
             "16o: el que se va no borra al que llegó")
    expectEq(PortalFrame.next(current: menu, report: nil, from: .menu, active: nil), nil,
             "16o: cerrar el activo sí borra")
    expectEq(PortalFrame.next(current: nil, report: menu, from: .menu, active: .menu), menu,
             "16o: el activo publica su marco")
    expectEq(PortalFrame.next(current: menu, report: CGRect(x: 0, y: 0, width: 1, height: 1), from: .volume, active: .menu), menu,
             "16o: un marco del que se va no pisa al activo")
}
