import CompanionCore
import CompanionTestKit
@testable import CompanionUI
import Foundation
import SwiftUI
import AppKit
import Testing

// Arc's voice-orb: idle breathes, listening swells with the mic and ripples,
// thinking contracts into a slow swirl, speaking pulses with the voice. Every
// shape value springs toward its state, so a change blends instead of cutting.

@Test @MainActor func eachStateHasItsOwnShape() {
    let idle = IslandOrbParams.target(.idle), listen = IslandOrbParams.target(.listening)
    let think = IslandOrbParams.target(.thinking), speak = IslandOrbParams.target(.speaking)
    expectEq(listen.ring, 1, "escuchando: ondas")
    expect([idle, think, speak].allSatisfy { $0.ring == 0 }, "solo escuchar tiene ondas")
    expect(think.swirl > listen.swirl && think.swirl > speak.swirl, "pensando: el remolino mas rapido")
    expect(think.grow < 0, "pensando: se contrae")
    expectEq(idle.gain, 0, "en reposo no sigue ningun nivel")
    expectEq(think.gain, 0, "pensando no sigue ningun nivel")
    expect(speak.tint > listen.tint && listen.tint > idle.tint, "la luz interior sube al hablar")
}

@Test @MainActor func theOrbMapsTheTurnToFourStates() {
    expectEq(IslandOrbState(TurnState.listening), .listening, "escuchar")
    expectEq(IslandOrbState(TurnState.speaking), .speaking, "hablar")
    expectEq(IslandOrbState(TurnState.thinking), .thinking, "pensar")
    expectEq(IslandOrbState(TurnState.connecting), .thinking, "conectando se ve como pensar")
    expectEq(IslandOrbState(TurnState.idle), .idle, "reposo")
}

// The spring blends from wherever the orb is, and settles on the target.
@Test @MainActor func aNewStateBlendsInAndSettles() {
    var sim = IslandOrbSimulation(state: .idle)
    sim.step(dt: 1 / 60, state: .thinking, input: 0, output: 0)
    let after1 = sim.current.swirl
    expect(after1 > IslandOrbParams.target(.idle).swirl && after1 < IslandOrbParams.target(.thinking).swirl,
           "un cuadro despues: a medio camino")
    for _ in 0..<240 { sim.step(dt: 1 / 60, state: .thinking, input: 0, output: 0) }
    expect(abs(sim.current.swirl - IslandOrbParams.target(.thinking).swirl) < 0.01, "cuatro segundos: llego")
}

@Test @MainActor func theLevelRisesFastAndFallsSlow() {
    var sim = IslandOrbSimulation(state: .listening)
    sim.step(dt: 0.05, state: .listening, input: 1, output: 0)
    let up = sim.level
    var down = IslandOrbSimulation(state: .listening)
    down.level = 1
    down.step(dt: 0.05, state: .listening, input: 0, output: 0)
    expect(up > 1 - down.level, "sube mas rapido de lo que baja")
}

@Test @MainActor func theLevelFollowsTheRightSource() {
    var listening = IslandOrbSimulation(state: .listening)
    listening.step(dt: 0.05, state: .listening, input: 0, output: 1)
    expectEq(listening.level, 0, "escuchando: la voz del agente no cuenta")
    var speaking = IslandOrbSimulation(state: .speaking)
    speaking.step(dt: 0.05, state: .speaking, input: 1, output: 0)
    expectEq(speaking.level, 0, "hablando: el microfono no cuenta")
    var thinking = IslandOrbSimulation(state: .thinking)
    thinking.step(dt: 0.05, state: .thinking, input: 1, output: 1)
    expectEq(thinking.level, 0, "pensando: ningun nivel")
}

@Test @MainActor func aBrokenLevelIsClamped() {
    var sim = IslandOrbSimulation(state: .listening)
    sim.step(dt: 0.05, state: .listening, input: .nan, output: 0)
    expect(sim.level.isFinite && sim.level >= 0 && sim.level <= 1, "nan: el nivel sigue en rango")
    sim.step(dt: 0.05, state: .listening, input: 9, output: 0)
    expect(sim.level <= 1, "pico: topa en 1")
}

@Test @MainActor func aLongFrameDoesNotBlowUpTheSpring() {
    var long = IslandOrbSimulation(state: .idle)
    long.step(dt: 5, state: .speaking, input: 0, output: 0)
    var capped = IslandOrbSimulation(state: .idle)
    capped.step(dt: IslandOrbSimulation.maxFrame, state: .speaking, input: 0, output: 0)
    expectEq(long.current.swirl, capped.current.swirl, "un salto de 5 s se trata como 50 ms")
    expectEq(long.current.wobble, capped.current.wobble, "igual en todos los parametros")
}

@Test @MainActor func aStillQuietBlobIsACircle() {
    var p = IslandOrbParams.target(.idle)
    p.wobble = 0
    for a in stride(from: 0.0, to: 2 * .pi, by: 0.4) {
        expectEq(IslandOrbGeometry.radius(at: a, base: 10, params: p, phase: 1.3, swirl: 0.7, level: 0), 10,
                 "sin ondulacion ni voz: el radio base")
    }
}

@Test @MainActor func theVoiceRipplesTheEdge() {
    let p = IslandOrbParams.target(.speaking)
    func spread(_ level: Double) -> Double {
        let rs = (0..<IslandOrbGeometry.points).map {
            IslandOrbGeometry.radius(at: Double($0) / Double(IslandOrbGeometry.points) * 2 * .pi, base: 10,
                                    params: p, phase: 1.3, swirl: 0.7, level: level)
        }
        return (rs.max() ?? 0) - (rs.min() ?? 0)
    }
    expect(spread(1) > spread(0), "la voz ondula mas que el silencio")
}

@Test @MainActor func theBlobStaysNearItsRadius() {
    let p = IslandOrbParams.target(.speaking)
    for i in 0..<IslandOrbGeometry.points {
        let a = Double(i) / Double(IslandOrbGeometry.points) * 2 * .pi
        let r = IslandOrbGeometry.radius(at: a, base: 10, params: p, phase: 1.3, swirl: 0.7, level: 1)
        expect(r > 7 && r < 13, "el borde ondula cerca del radio")
    }
}

@Test @MainActor func theTintGlowsOnTheDarkIsland() {
    let lifted = IslandOrbGeometry.glow(r: 0.1, g: 0.2, b: 0.6)
    expect((lifted.r + lifted.g + lifted.b) / 3 > 0.5, "en oscuro el tinte se levanta a un brillo")
    expect(lifted.b > lifted.g && lifted.g > lifted.r, "conserva su matiz")
}

@Test @MainActor func theOrbRendersInEveryState() throws {
    for state in [IslandOrbState.idle, .listening, .thinking, .speaking] {
        let view = IslandOrb(state: state, size: 36, still: true)
        let image = try #require(ImageRenderer(content: view).nsImage, "\(state): se pinta")
        expectEq(image.size.width, 36, "\(state): ocupa su ranura")
    }
}

// Skipped, not green, when no snapshot directory is set.
@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil)) @MainActor
func islandOrbSnapshots() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"])
    let row = HStack(spacing: 28) {
        ForEach([IslandOrbState.idle, .listening, .thinking, .speaking], id: \.self) { state in
            IslandOrb(state: state, size: 72, still: true)
        }
    }
    .padding(40)
    .background(Color.black)
    let renderer = ImageRenderer(content: row)
    renderer.scale = 2
    let tiff = try #require(renderer.nsImage?.tiffRepresentation)
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("island-orb.png"))
}
