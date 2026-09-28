import CompanionCore
import CompanionUI
import Foundation
import Testing

// Wave 16o-2: the screen edge glow while listening, from
// docs/research/incredible-fn-glow-pointer.md.

@Test @MainActor func screenGlowTargetTests() {
    expectEq(ScreenGlow.target(.listening, enabled: true), 0.5, "16o brillo: escuchando, techo 0.5")
    for phase in [SessionPhase.pending, .thinking, .toolExecuting, .subAgentRunning] {
        expectEq(ScreenGlow.target(.processing(phase), enabled: true), 0.25, "16o brillo: esperando, a la mitad (\(phase))")
    }
    for kind in [SessionKind.idle, .hover, .processing(.speaking), .processing(.completed)] {
        expectEq(ScreenGlow.target(kind, enabled: true), 0, "16o brillo: apagado (\(kind))")
    }
    expectEq(ScreenGlow.target(.listening, enabled: false), 0, "16o brillo: el interruptor apagado nunca lo muestra")
}

/// El aura mientras el puente tiene las manos: la pantalla dice quién está
/// actuando aunque la sesión de voz esté en reposo. Su turno (voz) manda
/// sobre el nivel; el interruptor general sigue apagándolo todo.
@Test @MainActor func screenGlowHandsTests() {
    expectEq(ScreenGlow.target(.idle, enabled: true, hands: true), ScreenGlow.waiting,
             "manos brillo: en reposo con las manos prestadas, encendida")
    expectEq(ScreenGlow.target(.hover, enabled: true, hands: true), ScreenGlow.waiting,
             "manos brillo: hover es reposo")
    expectEq(ScreenGlow.target(.listening, enabled: true, hands: true), ScreenGlow.listening,
             "manos brillo: su turno conserva su nivel")
    expectEq(ScreenGlow.target(.processing(.speaking), enabled: true, hands: true), 0,
             "manos brillo: hablando es su turno, apagada")
    expectEq(ScreenGlow.target(.idle, enabled: true, hands: false), 0,
             "manos brillo: sin manos, el reposo sigue apagado")
    expectEq(ScreenGlow.target(.idle, enabled: false, hands: true), 0,
             "manos brillo: el interruptor apagado tambien la apaga")
    // Candado: las manos solo cambian el reposo; todo lo demas conserva
    // exactamente su nivel de voz.
    for kind in [SessionKind.listening, .processing(.pending), .processing(.thinking),
                 .processing(.toolExecuting), .processing(.subAgentRunning),
                 .processing(.speaking), .processing(.completed)] {
        expectEq(ScreenGlow.target(kind, enabled: true, hands: true),
                 ScreenGlow.target(kind, enabled: true, hands: false),
                 "manos brillo: \(kind) no cambia con las manos")
    }
}

@Test @MainActor func screenGlowTimingTests() {
    expectEq(ScreenGlow.fade(from: 0, to: 0.5), ScreenGlow.fadeIn, "16o brillo: entra en 260 ms")
    expectEq(ScreenGlow.fade(from: 0.5, to: 0), ScreenGlow.fadeOut, "16o brillo: sale en 900 ms")
    expectEq(ScreenGlow.fade(from: 0.5, to: 0.25), ScreenGlow.fadeOut, "16o brillo: bajar es salir")
    expectEq([ScreenGlow.fadeIn, ScreenGlow.fadeOut], [0.26, 0.9], "16o brillo: tiempos de Incredible")
    expectEq(ScreenGlow.reach, 120, "16o brillo: 120 hacia dentro")
}

@Test @MainActor func screenGlowColorTests() {
    expectEq(ScreenGlow.colors.map(\.hex), ["1C69F0", "0AB4AF", "8C46E6", "1496DC"], "16o brillo: la rueda")
    expectEq(ScreenGlow.rotation(at: 0, phase: 1), 1, "16o brillo: arranca en su fase")
    let quarter = ScreenGlow.rotation(at: ScreenGlow.period / 4, phase: 0)
    expect(abs(quarter - Double.pi / 2) < 1e-9, "16o brillo: un cuarto de vuelta en period/4")
    expect(ScreenGlow.rotation(at: ScreenGlow.period * 3, phase: 0.5) < 2 * Double.pi, "16o brillo: ángulo acotado")
    expectEq(ScreenGlow.period, 71, "16o brillo: una vuelta en ~71 s")
    expectEq(ScreenGlow.rotation(at: 30, phase: 0.5, animated: false), 0.5, "16o brillo: Reducir movimiento no gira")
}

@Test @MainActor func screenGlowPreferenceTests() {
    let store = UserDefaults(suiteName: "screen-glow-tests")!
    store.removePersistentDomain(forName: "screen-glow-tests")
    expect(ScreenGlowPreference.enabled(in: store), "16o brillo: encendido por defecto")
    ScreenGlowPreference.set(false, in: store)
    expect(!ScreenGlowPreference.enabled(in: store), "16o brillo: se puede apagar")
    store.removePersistentDomain(forName: "screen-glow-tests")
}

@Test @MainActor func screenGlowShaderCompilesTests() {
    let error = ScreenGlowShader.compileError()
    expect(error == nil, "16o brillo: el shader compila (\(error ?? ""))")
}
