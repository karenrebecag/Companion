import CompanionCore
import CompanionTestKit
import CompanionUI
import Foundation
import Metal
import SwiftUI
import Testing

// Incredible 0.2.36's screen glow ("gl-waves", its default): a shader on the screen's edges
// while it listens, dimmed while it waits, faded by a linear fill.

@Test @MainActor func screenGlowModeTests() {
    for previous in [ScreenGlow.Mode.off, .listening, .waiting] {
        expectEq(ScreenGlow.mode(.listening, enabled: true, previous: previous), .listening,
                 "modo: escuchar enciende desde \(previous)")
    }
    for phase in [SessionPhase.pending, .thinking, .toolExecuting, .subAgentRunning] {
        expectEq(ScreenGlow.mode(.processing(phase), enabled: true, previous: .listening), .waiting,
                 "modo: tras escuchar, esperar atenua (\(phase))")
        expectEq(ScreenGlow.mode(.processing(phase), enabled: true, previous: .waiting), .waiting,
                 "modo: esperando sigue esperando (\(phase))")
        expectEq(ScreenGlow.mode(.processing(phase), enabled: true, previous: .off), .off,
                 "modo: esperar no la enciende si estaba apagada (\(phase))")
    }
    for kind in [SessionKind.idle, .hover, .processing(.speaking), .processing(.completed)] {
        expectEq(ScreenGlow.mode(kind, enabled: true, previous: .listening), .off, "modo: \(kind) apaga")
    }
    expectEq(ScreenGlow.mode(.listening, enabled: false, previous: .listening), .off,
             "modo: el interruptor apagado nunca la muestra")
}

/// Decision de UX de Karen (2026-10-03), como Incredible: el brillo es de la voz, y un
/// agente actuando por el puente no lo enciende. Reemplaza el candado de la revision de
/// seguridad de la wave 20b, que pedia lo contrario.
@Test @MainActor func screenGlowHandsTests() {
    let kinds: [SessionKind] = [.idle, .hover, .listening, .processing(.pending), .processing(.thinking),
                                .processing(.toolExecuting), .processing(.subAgentRunning),
                                .processing(.speaking), .processing(.completed)]
    for kind in kinds {
        for previous in [ScreenGlow.Mode.off, .listening, .waiting] {
            var acting = SessionProjection()
            acting.kind = kind
            acting.handsActing = true
            var resting = acting
            resting.handsActing = false
            expectEq(ScreenGlow.mode(acting, enabled: true, previous: previous),
                     ScreenGlow.mode(resting, enabled: true, previous: previous),
                     "manos: \(kind) desde \(previous) es igual con o sin manos")
        }
    }
    var acting = SessionProjection()
    acting.handsActing = true
    expectEq(ScreenGlow.mode(acting, enabled: true, previous: .off), .off, "manos: en reposo, apagado")
}

/// The view threads `previous` through every change; the fold is the real sequence.
@Test @MainActor func screenGlowModeSequences() {
    func fold(_ steps: [(SessionKind, Bool)]) -> [ScreenGlow.Mode] {
        var previous = ScreenGlow.Mode.off
        return steps.map { kind, enabled in
            previous = ScreenGlow.mode(kind, enabled: enabled, previous: previous)
            return previous
        }
    }
    expectEq(fold([(.listening, true), (.processing(.thinking), true),
                   (.processing(.speaking), true), (.processing(.thinking), true)]),
             [.listening, .waiting, .off, .off], "secuencia: tras hablar, pensar otra vez queda a oscuras")
    expectEq(fold([(.listening, true), (.listening, false), (.processing(.thinking), true)]),
             [.listening, .off, .off], "secuencia: apagarla corta la espera")
}

@Test @MainActor func screenGlowEnvelopeEdges() {
    let half = ScreenGlow.Envelope(fill: 0.5, dim: 1)
    expectEq(half.step(.listening, ms: -50), half, "borde: un tiempo negativo no mueve nada")
    expect(abs(half.step(.listening, ms: 26).fill - 0.6) < 1e-9, "borde: a medio fundido sube desde donde esta")
    expect(abs(ScreenGlow.Envelope(fill: 0.4, dim: 0.5).step(.off, ms: 90).fill - 0.3) < 1e-9,
           "borde: apagar a medio camino drena desde donde esta")
    let waking = ScreenGlow.Envelope(fill: 0, dim: 1).step(.waiting, ms: 65)
    expect(abs(waking.fill - 0.25) < 1e-9 && abs(waking.dim - 0.87) < 1e-9, "borde: esperar desde vacia llena y atenua a la vez")
    expect(abs(ScreenGlow.Envelope(fill: 0.5, dim: 0.5).step(.off, ms: 50).dim - 0.6) < 1e-9,
           "borde: apagada, la atenuacion vuelve a 1 mientras drena")
    expect(ScreenGlow.Envelope(fill: 0, dim: 1).drawing(.waiting), "dibuja: esperar desde vacia")
    expect(ScreenGlow.Envelope(fill: 1e-12, dim: 1).drawing(.off), "dibuja: hasta la ultima traza")
    var draining = ScreenGlow.Envelope(fill: 1, dim: 1)
    var frames = 0
    while draining.drawing(.off), frames < 200 {
        draining = draining.step(.off, ms: 16)
        frames += 1
    }
    expectEq(frames, 57, "dibuja: drena en 900 ms de cuadros de 16 ms")
    expectEq(ScreenGlow.phase(random: 0.9999), 1, "fase: una vuelta entera; el shader la toma con fract")
}

@Test @MainActor func screenGlowFillIsLinearQuickInSoftOut() {
    let off = ScreenGlow.Envelope.start(.off)
    expectEq(off, ScreenGlow.Envelope(fill: 0, dim: 1), "relleno: arranca apagado, sin atenuar")
    expectEq(ScreenGlow.Envelope.start(.listening).fill, 1, "relleno: montada encendida, llena")
    expect(abs(off.step(.listening, ms: 65).fill - 0.25) < 1e-9, "relleno: entra lineal, 260 ms")
    expectEq(off.step(.listening, ms: 65).step(.listening, ms: 65).step(.listening, ms: 65)
        .step(.listening, ms: 65).fill, 1, "relleno: lleno a los 260 ms")
    let full = ScreenGlow.Envelope(fill: 1, dim: 1)
    expect(abs(full.step(.off, ms: 90).fill - 0.9) < 1e-9, "relleno: sale lineal, 900 ms")
    expectEq(ScreenGlow.Envelope(fill: 0.05, dim: 1).step(.off, ms: 90).fill, 0, "relleno: nunca baja de 0")
    expect(abs(off.step(.listening, ms: 400).fill - 100.0 / 260) < 1e-9, "relleno: un cuadro largo cuenta 100 ms")
}

@Test @MainActor func screenGlowDimsWhileWaiting() {
    let lit = ScreenGlow.Envelope(fill: 1, dim: 1)
    expect(abs(lit.step(.waiting, ms: 50).dim - 0.9) < 1e-9, "atenuar: se acerca a 0.5, una fraccion de 250 ms por paso")
    expect(abs(lit.step(.waiting, ms: 400).dim - 0.8) < 1e-9, "atenuar: el paso tambien tope de 100 ms")
    expect(abs(ScreenGlow.Envelope(fill: 1, dim: 0.5).step(.listening, ms: 50).dim - 0.6) < 1e-9,
           "atenuar: al volver a escuchar sube igual")
    expectEq(lit.step(.waiting, ms: 16).fill, 1, "atenuar: esperar no vacia el relleno")
    expect(abs(ScreenGlow.Envelope(fill: 0.5, dim: 0.5).alpha - 0.125) < 1e-9,
           "alfa: relleno por atenuacion por el techo de 0.5")
    expect(ScreenGlow.Envelope(fill: 0, dim: 1).drawing(.listening), "dibuja: mientras entra")
    expect(ScreenGlow.Envelope(fill: 0.2, dim: 1).drawing(.off), "dibuja: mientras sale")
    expect(!ScreenGlow.Envelope(fill: 0, dim: 1).drawing(.off), "dibuja: apagada y vacia, nada")
}

@Test @MainActor func screenGlowShaderValuesAreIncredibles() {
    expectEq(ScreenGlow.colors.map(\.hex), ["1C69F0", "0AB4AF", "8C46E6", "1496DC"], "colores: la rueda")
    expectEq(ScreenGlow.reach, 120, "alcance: 120 px del lienzo hacia dentro")
    expectEq(ScreenGlow.seed, 9, "semilla: fija en 9")
    expectEq(ScreenGlow.density(backing: 2), 1.25, "densidad: el lienzo tope en 1.25")
    expectEq(ScreenGlow.density(backing: 1), 1, "densidad: en 1x, 1")
    expectEq(ScreenGlow.phase(random: 0), 0, "fase: grados enteros sobre 360")
    expectEq(ScreenGlow.phase(random: 0.5), 0.5, "fase: media vuelta")
    expectEq(ScreenGlow.phase(random: 0.001), 0, "fase: redondea al grado de abajo")
    expectEq(ScreenGlow.phase(random: 0.0014), 1.0 / 360, "fase: y al de arriba")
}

@Test @MainActor func screenGlowContainerTiming() {
    expectEq(ScreenGlow.waitingScale, 0.996, "esperando: se encoge a 0.996")
    expectEq(ScreenGlow.settle, 0.7, "transicion del contenedor: 700 ms settle")
    expectEq(ScreenGlow.leaveDelay, 0.8, "al apagarse, el contenedor espera 800 ms")
    expectEq(ScreenGlow.linger(reduceMotion: false), 1.5, "renderer: vive hasta que el contenedor se apaga")
    expectEq(ScreenGlow.linger(reduceMotion: true), 0.9, "reducido: el contenedor se va al instante, el relleno drena igual")
    expect(ScreenGlow.opacityAnimation(off: false, reduceMotion: false) == nil, "encender: el contenedor aparece al instante")
    expect(ScreenGlow.opacityAnimation(off: true, reduceMotion: true) == nil, "reducido: apagar sin transicion")
    expect(ScreenGlow.opacityAnimation(off: true, reduceMotion: false)
        == MotionCurve.animation(MotionCurve.settle, 0.7).delay(0.8), "apagar: 700 ms settle tras 800 ms")
    expect(ScreenGlow.scaleAnimation(off: false, reduceMotion: false)
        == MotionCurve.animation(MotionCurve.settle, 0.7), "esperar: encoge en 700 ms settle")
    expect(ScreenGlow.scaleAnimation(off: true, reduceMotion: false) == nil, "apagar: la escala vuelve sin transicion")
    expect(ScreenGlow.scaleAnimation(off: false, reduceMotion: true) == nil, "reducido: sin transicion de escala")
}

@Test @MainActor func screenGlowRippleRingsAreIncredibles() {
    let ripple = ScreenGlow.Ripple.self
    expectEq(ripple.outer.map(\.swatch.hex), ["784CD6", "784CD6", "246EEB", "12A0C4", "12A0C4"], "anillo: tonos de fuera")
    expectEq(ripple.outer.map(\.alpha), [0, 0.2, 0.3, 0.28, 0], "anillo: alfas de fuera")
    expectEq(ripple.outer.map(\.at), [0.26, 0.33, 0.39, 0.45, 0.54], "anillo: posiciones de fuera")
    expectEq(ripple.inner.map(\.alpha), [0, 0.14, 0], "anillo: alfas de dentro")
    expectEq(ripple.inner.map(\.at), [0.12, 0.2, 0.28], "anillo: posiciones de dentro")
    expectEq(ripple.blur, 10, "anillo: desenfoque de 10 pt")
    expectEq(ripple.radius(in: CGSize(width: 1600, height: 600)), 1000, "anillo: hasta la esquina mas lejana")
}

@Test @MainActor func screenGlowRippleRisesFromTheNotch() {
    let ripple = ScreenGlow.Ripple.self
    expectEq(ripple.duration, 0.85, "onda: 850 ms")
    let start = ripple.state(at: 0)
    expectEq(start.scale, 0.05, "onda: nace a 0.05")
    expectEq(start.opacity, 0, "onda: nace invisible")
    let peak = ripple.state(at: 0.3 * ripple.duration)
    expect(abs(peak.opacity - 0.55) < 1e-9, "onda: 0.55 al 30 %")
    let end = ripple.state(at: ripple.duration)
    expectEq(end.scale, 2.3, "onda: termina a 2.3")
    expectEq(end.opacity, 0, "onda: termina invisible")
    expectEq(ripple.state(at: 5).opacity, 0, "onda: despues, nada")
    let mid = ripple.state(at: 0.15 * ripple.duration)
    let curve = MotionCurve.value([0.25, 0.55, 0.35, 1], at: 0.5)
    expect(abs(mid.opacity - 0.55 * curve) < 1e-9, "onda: cada tramo con la curva (.25,.55,.35,1)")
    let falling = ripple.state(at: 0.65 * ripple.duration)
    let down = MotionCurve.value([0.25, 0.55, 0.35, 1], at: 0.35 / 0.7)
    expect(abs(falling.opacity - 0.55 * (1 - down)) < 1e-9, "onda: baja en su propio tramo, del 30 % al final")
    let halfway = ripple.state(at: 0.5 * ripple.duration)
    expect(abs(halfway.scale - (0.05 + 2.25 * curve)) < 1e-9, "onda: la escala corre un solo tramo")
    let times = stride(from: 0.0, through: ripple.duration, by: 0.01).map { ripple.state(at: $0) }
    expect(zip(times, times.dropFirst()).allSatisfy { $1.scale >= $0.scale }, "onda: la escala nunca encoge")
    expectEq(ripple.state(at: -1).scale, ripple.state(at: 0).scale, "onda: antes de empezar, como al empezar")
}

@Test @MainActor func screenGlowPreferenceTests() {
    let store = UserDefaults(suiteName: "screen-glow-tests")!
    store.removePersistentDomain(forName: "screen-glow-tests")
    expect(ScreenGlowPreference.enabled(in: store), "16o brillo: encendido por defecto")
    ScreenGlowPreference.set(false, in: store)
    expect(!ScreenGlowPreference.enabled(in: store), "16o brillo: se puede apagar")
    store.removePersistentDomain(forName: "screen-glow-tests")
}

// QA review (HIGH): without a device the compile would pass having compiled nothing.
@Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "sin dispositivo Metal no hay shader que compilar"))
@MainActor func screenGlowShaderCompilesTests() {
    let error = ScreenGlowShader.compileError()
    expect(error == nil, "16o brillo: el shader compila (\(error ?? ""))")
}

// The bridge still records that an agent is acting (self-inspection reports it); it
// just no longer lights the glow.
@Test @MainActor func screenGlowHandsLingerReducerTests() {
    var m = SessionMachine()
    let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
    expect(!m.projection.handsActing, "aura linger: en reposo, apagada")
    var fx = m.handle(.handsLent(client: "Claude Code"))
    expect(!m.projection.handsActing, "aura linger: abrir la sesion no la enciende")
    expect(fx.isEmpty, "aura linger: abrir la sesion no agenda nada")
    fx = m.handle(.handsWorking(target: frame))
    expect(m.projection.handsActing, "aura linger: una llamada la enciende")
    expectEq(m.projection.handsTarget, frame, "aura linger: guarda el marco objetivo")
    expect(fx.contains(.scheduleHandsGlowExpiry(SessionMachine.handsGlowLinger)), "aura linger: agenda el apagado")
    expectEq(SessionMachine.handsGlowLinger, 4, "aura linger: 4 s tras la ultima llamada")
    let next = CGRect(x: 1, y: 2, width: 3, height: 4)
    fx = m.handle(.handsWorking(target: next))
    expectEq(m.projection.handsTarget, next, "aura linger: cada llamada recalcula el marco")
    expect(fx.contains(.scheduleHandsGlowExpiry(SessionMachine.handsGlowLinger)), "aura linger: cada llamada reinicia el plazo")
    _ = m.handle(.handsGlowExpired)
    expect(!m.projection.handsActing, "aura linger: el plazo la apaga")
    expectEq(m.projection.handsTarget, nil, "aura linger: y suelta el marco")
    expectEq(m.projection.handsLentTo, "Claude Code", "aura linger: el chip sigue con la sesion abierta")
    _ = m.handle(.handsWorking(target: nil))
    expectEq(m.projection.handsTarget, nil, "aura linger: sin ventana, sin marco (cae al cursor)")
    _ = m.handle(.handsLent(client: nil))
    expect(!m.projection.handsActing, "aura linger: cerrar la sesion apaga el aura al instante")
    let timerless = m.handle(.handsGlowExpired)
    expect(timerless.isEmpty && !m.projection.handsActing, "aura linger: un plazo tardio es inocuo")
    // Code review 20b (MEDIUM): a call still in flight when the session
    // closed must not light the aura with nobody holding the hands.
    let late = m.handle(.handsWorking(target: frame))
    expect(!m.projection.handsActing && late.isEmpty, "aura linger: una llamada tardia sin sesion no la enciende")
}
