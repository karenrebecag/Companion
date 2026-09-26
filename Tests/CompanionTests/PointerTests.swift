import CompanionCore
import CompanionServices
import CompanionUI
import CoreGraphics
import Foundation
import Testing

// Wave 16o-3: pointing with the cursor while holding fn, from
// docs/research/incredible-fn-glow-pointer.md.

@Test @MainActor func pointerTrailTests() {
    expectEq([PointerTrail.life, PointerTrail.taper, PointerTrail.alpha], [0.62, 0.2, 0.3], "16o rastro: vida, afinado, alfa")
    expectEq([PointerTrail.maxWidth, PointerTrail.minStep, PointerTrail.breakJump], [16, 1.5, 260], "16o rastro: medidas")
    expectEq(PointerTrail.ink.hex, "4678F5", "16o rastro: tinta rgb(70,120,245)")

    var trail = PointerTrail()
    trail.add(CGPoint(x: 0, y: 0), at: 0)
    trail.add(CGPoint(x: 100, y: 0), at: 0.016)
    expectEq(trail.points.last?.position, CGPoint(x: 30, y: 0), "16o rastro: sigue al 0.3")

    let before = trail.points.count
    trail.add(CGPoint(x: 31, y: 0), at: 0.032)
    expectEq(trail.points.count, before, "16o rastro: menos de 1.5 no añade punto")

    trail.add(CGPoint(x: 600, y: 0), at: 0.05)
    let strokes = Set(trail.points.map(\.stroke))
    expectEq(strokes.count, 2, "16o rastro: un salto de más de 260 corta el trazo")
    expectEq(trail.points.last?.position, CGPoint(x: 600, y: 0), "16o rastro: el trazo nuevo nace en el cursor")

    trail.prune(at: 0.7)
    expect(trail.points.allSatisfy { 0.7 - $0.time <= PointerTrail.life }, "16o rastro: caduca a los 620 ms")

    expectEq(PointerTrail.width(age: 0.1), 16, "16o rastro: ancho lleno al nacer")
    expectEq(PointerTrail.width(age: 0.62), 0, "16o rastro: nada al morir")
    let mid = PointerTrail.width(age: 0.62 - 0.062)
    expect(abs(mid - 8) < 1e-9, "16o rastro: se afina en el último 20 %")

    trail.reset()
    expect(trail.points.isEmpty, "16o rastro: se borra al soltar")
}

@Test @MainActor func pointerOrbTests() {
    expectEq(PointerOrb.size, 32, "16o orbe: 32")
    expectEq(PointerOrb.offset, CGSize(width: 14, height: 17), "16o orbe: +14, +17 del cursor")
    expectEq(PointerOrb.follow, 0.16, "16o orbe: sigue al 0.16")
    let next = PointerOrb.step(from: .zero, cursor: CGPoint(x: 86, y: 83))
    expect(abs(next.x - 16) < 1e-9 && abs(next.y - 16) < 1e-9, "16o orbe: un paso hacia cursor + desplazamiento")
}

@Test func pointerTraceTests() {
    let a = PointedElement(app: "Safari", role: "AXLink", text: "Precios", at: 0.1)
    let a2 = PointedElement(app: "Safari", role: "AXLink", text: "Precios", at: 0.2)
    let b = PointedElement(app: "Safari", role: "AXButton", text: "Comprar", at: 0.9)
    let empty = PointedElement(app: "Safari", role: "AXGroup", text: "  ", at: 1.0)
    expectEq(PointerTrace.collapse([a, a2, b, empty, a]), [a, b, PointedElement(app: "Safari", role: "AXLink", text: "Precios", at: 0.1)],
             "16o señalado: repetidos seguidos se juntan y lo vacío no viaja")
    let many = (0..<20).map { PointedElement(app: "A", role: "r", text: "t\($0)", at: Double($0)) }
    expectEq(PointerTrace.collapse(many).count, PointerTrace.maxItems, "16o señalado: tope de elementos")
    expectEq(PointerTrace.collapse(many).first?.text, "t0", "16o señalado: se guardan los primeros")
}

@Test func pointedContextBlockTests() {
    var ctx = TurnContext(source: .voice)
    ctx.pointed = [PointedElement(app: "Safari", role: "AXLink", text: "Precios <b>", at: 1.24)]
    let block = ContextBlock.render(ctx, language: .es)
    expect(block.contains("<pointed_while_speaking>"), "16o contexto: lo señalado viaja en el turno")
    expect(block.contains("Precios &lt;b&gt;"), "16o contexto: el texto va escapado")
    expect(block.contains("<at s=\"1.2\""), "16o contexto: con el segundo en que se señaló")
    expect(!ContextBlock.compact(ctx, language: .es).contains("Precios"), "16o contexto: la memoria no guarda lo señalado")
    ctx.pointed = [PointedElement(app: "Evil\" role=\"x", role: "AXLink", text: "t", at: 0)]
    expect(ContextBlock.render(ctx, language: .es).contains("Evil&quot; role=&quot;x"),
           "16o contexto: una comilla en el nombre no cierra el atributo")
}

@Test func pointerSamplerTests() {
    let clock = PointerClock()
    let sampler = PointerSampler(
        probe: { _ in PointedElement(app: "Notas", role: "AXTextArea", text: "lista", at: 0) },
        location: { CGPoint(x: 10, y: 10) },
        now: { clock.now },
        ticks: false)
    sampler.start()
    clock.now = 0.5
    sampler.sample()
    clock.now = 0.8
    sampler.sample()
    let items = sampler.stop()
    expectEq(items.map(\.at), [0.5], "16o muestreo: hora relativa al pulsar, repetidos juntos")
    expect(sampler.stop().isEmpty, "16o muestreo: al terminar el turno no queda nada")
    sampler.sample()
    expect(sampler.stop().isEmpty, "16o muestreo: sin pulsar no se muestrea")
}

private final class PointerClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

// Code review 16o (MEDIUM): the trail runs on the display the hold started
// on, never under Reduce Motion, only while listening.
@Test @MainActor func pointerLayerGateTests() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let inside = CGPoint(x: 100, y: 100), outside = CGPoint(x: 2000, y: 100)
    expect(PointerOrb.shows(kind: .listening, reduceMotion: false, screen: screen, cursor: inside), "16o rastro: escuchando, en esta pantalla")
    expect(!PointerOrb.shows(kind: .listening, reduceMotion: false, screen: screen, cursor: outside), "16o rastro: otra pantalla no dibuja")
    expect(!PointerOrb.shows(kind: .listening, reduceMotion: true, screen: screen, cursor: inside), "16o rastro: Reducir movimiento lo apaga")
    expect(!PointerOrb.shows(kind: .processing(.thinking), reduceMotion: false, screen: screen, cursor: inside), "16o rastro: solo con fn abajo")
}

// Crash 2026-09-26 00:20: over Companion's own window, the AX hit test runs
// our SwiftUI body on the sampler's queue and trips the main-actor check.
// Over our own window the probe must never be called.
@Test func pointerSamplerSkipsOwnWindowsTests() {
    let probed = ProbeCounter()
    let sampler = PointerSampler(
        probe: { _ in probed.hit(); return PointedElement(app: "Companion", role: "AXWindow", text: "x", at: 0) },
        location: { CGPoint(x: 10, y: 10) },
        ownsPoint: { _ in true },
        now: { 0 },
        ticks: false)
    sampler.start()
    sampler.sample()
    expectEq(probed.count, 0, "crash fn: sobre una ventana propia no se pregunta a Accesibilidad")
    expect(sampler.stop().isEmpty, "crash fn: nada señalado sobre Companion")
}

private final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var hits = 0
    var count: Int { lock.withLock { hits } }
    func hit() { lock.withLock { hits += 1 } }
}
