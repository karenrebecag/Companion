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

// Wave 20b D1: the hands glow marks "an agent is acting now" on the display
// of the app it acts on, not "a session is open" on every display.

/// Two displays side by side, primary (1440x900) on the left and a taller
/// one on its right, in AppKit space (bottom-left origin, y up).
private let leftScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
private let rightScreen = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
private let bothScreens = [leftScreen, rightScreen]

@Test @MainActor func screenGlowAXFrameConversionTests() {
    // AX: top-left origin, y down, measured from the primary's top edge.
    let converted = ScreenGlow.appKitFrame(
        fromAX: CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 900)
    expectEq(converted, CGRect(x: 100, y: 550, width: 400, height: 300), "aura pantalla: AX arriba-izq a AppKit abajo-izq")
    let below = ScreenGlow.appKitFrame(
        fromAX: CGRect(x: 1500, y: 950, width: 200, height: 100), primaryHeight: 900)
    expectEq(below.origin.y, -150, "aura pantalla: un monitor bajo el primario queda en y negativa")
}

@Test @MainActor func screenGlowHandsScreenSelectionTests() {
    let onLeft = CGRect(x: 200, y: 300, width: 500, height: 400)
    let onRight = CGRect(x: 1800, y: 100, width: 600, height: 500)
    func lit(_ screen: CGRect, _ target: CGRect?, cursor: CGPoint = .zero) -> Bool {
        ScreenGlow.handsOnScreen(screenFrame: screen, screens: bothScreens, target: target, cursor: cursor)
    }
    expect(lit(leftScreen, onLeft), "aura pantalla: la ventana en el primario enciende el primario")
    expect(!lit(rightScreen, onLeft), "aura pantalla: y no el otro")
    expect(lit(rightScreen, onRight), "aura pantalla: la ventana en el segundo enciende el segundo")
    expect(!lit(leftScreen, onRight), "aura pantalla: y no el primario")
    // A window straddling the seam belongs to the display holding most of it.
    let straddling = CGRect(x: 1240, y: 300, width: 600, height: 400)
    expect(lit(rightScreen, straddling), "aura pantalla: a horcajadas, gana el de mayor area (derecha)")
    expect(!lit(leftScreen, straddling), "aura pantalla: nunca dos monitores a la vez")
    // Ties resolve to exactly one display too.
    let even = CGRect(x: 1240, y: 300, width: 400, height: 400)
    expectEq([lit(leftScreen, even), lit(rightScreen, even)].filter { $0 }.count, 1, "aura pantalla: empate, uno solo")
}

@Test @MainActor func screenGlowHandsCursorFallbackTests() {
    let cursorRight = CGPoint(x: 2000, y: 200)
    for target in [CGRect?.none, CGRect(x: 9000, y: 9000, width: 10, height: 10)] {
        expect(ScreenGlow.handsOnScreen(screenFrame: rightScreen, screens: bothScreens, target: target, cursor: cursorRight),
               "aura pantalla: sin ventana util, el monitor del cursor")
        expect(!ScreenGlow.handsOnScreen(screenFrame: leftScreen, screens: bothScreens, target: target, cursor: cursorRight),
               "aura pantalla: el otro apagado")
    }
    expect(!ScreenGlow.handsOnScreen(screenFrame: leftScreen, screens: bothScreens, target: nil, cursor: CGPoint(x: -5000, y: 0)),
           "aura pantalla: cursor fuera de todo, ninguno")
    expect(ScreenGlow.handsOnScreen(screenFrame: leftScreen, screens: [leftScreen], target: nil, cursor: CGPoint(x: 10, y: 10)),
           "aura pantalla: un solo monitor con cursor, enciende")
}

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
