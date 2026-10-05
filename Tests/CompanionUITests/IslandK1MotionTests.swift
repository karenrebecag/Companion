import CoreGraphics
@testable import CompanionUI
import CompanionTestKit
import Testing

@Test @MainActor func k1ASlowPointerDwellsBriefly() {
    expectEq(IslandMotion.entryDwell(from: nil, to: CGPoint(x: 400, y: 0), dt: 0),
             IslandMotion.peekDwell, "K1: la primera muestra no tiene velocidad")
    expectEq(IslandMotion.hoverDwell(pointsPerSecond: IslandMotion.fastPointer),
             IslandMotion.peekDwell, "K1: justo a 450 px/s sigue el dwell corto")
    expectEq(IslandMotion.hoverDwell(from: .zero, to: CGPoint(x: 45, y: 0), dt: 0.1),
             IslandMotion.peekDwell, "K1: un puntero lento abre con el dwell corto")
}

@Test @MainActor func k1AFastPointerDwellsLonger() {
    expectEq(IslandMotion.hoverDwell(pointsPerSecond: IslandMotion.fastPointer + 1),
             IslandMotion.fastHoverDwell, "K1: por encima de 450 px/s el dwell es el largo")
    expectEq(IslandMotion.hoverDwell(from: .zero, to: CGPoint(x: 46, y: 0), dt: 0.1),
             IslandMotion.fastHoverDwell, "K1: un cruce rápido espera más")
    expectEq(IslandMotion.hoverDwell(from: .zero, to: .zero, dt: 0),
             IslandMotion.fastHoverDwell, "K1: un salto sin tiempo cuenta como rápido")
}

@Test @MainActor func k1LeaveWaitsOutTheHysteresis() {
    expectEq(IslandMotion.leaveDelay(openFor: 0), IslandMotion.hoverHysteresis,
             "K1: un nivel recién abierto espera la histéresis")
    expectEq(IslandMotion.leaveDelay(openFor: 0.02), 0.28,
             "K1: sale cuando se cumple el mínimo de permanencia")
    expectEq(IslandMotion.leaveDelay(openFor: 1), IslandMotion.levelDrop,
             "K1: pasado ese mínimo, cierra con la caída de nivel")
}
