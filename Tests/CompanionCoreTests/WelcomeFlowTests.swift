import CompanionCore
import CompanionTestKit
import Testing

// Wave 16c (spec 16c §2): Incredible's welcome, one idea per screen. Seven
// screens; Continue opens only when the screen's own condition holds; the
// last one does not end without a real hold, and "Skip" is always there on
// the two that need hardware.

@Test @MainActor func welcomeFlowTests() {
    testTheSevenScreensInOrder()
    testContinueWaitsForEachScreensCondition()
    testTheLastScreenEndsOnlyWithARealHold()
    testSkipExistsOnlyWhereHardwareCanFail()
    testBackNeverLeavesTheCover()
    testAReturningUserWithoutAKeyStartsAtKeys()
}

private func facts(
    key: Bool = false, granted: Set<WelcomePermission> = [], mic: Bool = false, hold: Bool = false
) -> WelcomeFacts {
    WelcomeFacts(keyReady: key, granted: granted, micHeard: mic, holdDone: hold)
}

private let all = Set(WelcomePermission.allCases)

@MainActor func testTheSevenScreensInOrder() {
    expectEq(WelcomeStep.allCases, [.cover, .hello, .keys, .permissions, .holdKey, .microphone, .yourTurn],
             "bienvenida: siete pantallas en el orden de Incredible")
    expectEq(WelcomePermission.allCases, [.microphone, .accessibility, .screenRecording, .speechRecognition],
             "permisos: cuatro filas en una pantalla")
    var flow = WelcomeFlow()
    let ready = facts(key: true, granted: all, mic: true, hold: true)
    var seen: [WelcomeStep] = [flow.step]
    while flow.advance(ready) { seen.append(flow.step) }
    expectEq(seen, WelcomeStep.allCases, "avanza por todas")
    expect(flow.finished, "la última, con el hold hecho, termina")
}

@MainActor func testContinueWaitsForEachScreensCondition() {
    var flow = WelcomeFlow(step: .keys)
    expect(!flow.canContinue(facts()), "claves: sin OpenAI no se sigue")
    expect(flow.canContinue(facts(key: true)), "claves: con OpenAI sí")
    flow = WelcomeFlow(step: .permissions)
    expect(!flow.canContinue(facts(granted: [.microphone, .accessibility, .screenRecording])),
           "permisos: tres de cuatro no bastan")
    expect(flow.canContinue(facts(granted: all)), "permisos: los cuatro")
    flow = WelcomeFlow(step: .microphone)
    expect(!flow.canContinue(facts()), "micro: hasta oír nivel")
    expect(flow.canContinue(facts(mic: true)), "micro: con nivel")
    for step in [WelcomeStep.cover, .hello, .holdKey] {
        expect(WelcomeFlow(step: step).canContinue(facts()), "\(step): siempre se puede seguir")
    }
    var blocked = WelcomeFlow(step: .keys)
    expect(!blocked.advance(facts()), "avanzar sin la condición: no se mueve")
    expectEq(blocked.step, .keys, "se queda en claves")
}

@MainActor func testTheLastScreenEndsOnlyWithARealHold() {
    var flow = WelcomeFlow(step: .yourTurn)
    expect(!flow.advance(facts(key: true, granted: all, mic: true)), "tu turno: sin hold no termina")
    expect(!flow.finished, "tu turno: sigue abierta")
    expect(!flow.advance(facts(hold: true)), "tu turno: con hold termina, no hay pantalla siguiente")
    expect(flow.finished, "tu turno: terminada")
}

@MainActor func testSkipExistsOnlyWhereHardwareCanFail() {
    expectEq(WelcomeStep.allCases.filter(\.skippable), [.microphone, .yourTurn],
             "saltar: solo micro y tu turno")
    var flow = WelcomeFlow(step: .microphone)
    flow.skip()
    expectEq(flow.step, .yourTurn, "saltar el micro lleva a tu turno")
    flow.skip()
    expect(flow.finished, "saltar tu turno termina")
    var keys = WelcomeFlow(step: .keys)
    keys.skip()
    expectEq(keys.step, .keys, "claves: no se salta")
}

@MainActor func testBackNeverLeavesTheCover() {
    var flow = WelcomeFlow()
    flow.back()
    expectEq(flow.step, .cover, "atrás en la portada: se queda")
    flow = WelcomeFlow(step: .permissions)
    flow.back()
    expectEq(flow.step, .keys, "atrás: la anterior")
}

@MainActor func testAReturningUserWithoutAKeyStartsAtKeys() {
    expectEq(WelcomeFlow.start(welcomeDone: false).step, .cover, "primera vez: portada")
    var back = WelcomeFlow.start(welcomeDone: true)
    expectEq(back.step, .keys, "ya la vio y falta clave: claves")
    _ = back.advance(facts(key: true))
    expect(back.finished, "ya la vio: con la clave termina, no repite el resto")
}
