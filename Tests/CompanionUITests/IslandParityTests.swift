import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Wave 16e (spec 16c §2, "La isla como app"). Incredible's notch bar is the
// app: a light that says "needs you" or "done", a listening pill with no
// status words, "didn't hear you" that leaves on its own, errors that carry
// their way out, a menu of five and results as cards.

@Test @MainActor func islandParityTests() {
    testTheLightIsAmberWhenItNeedsYouAndGreenWhenDone()
    testListeningHasNoStatusWords()
    testANoticeFadesAfterSixSeconds()
    testAFreshNoticeRearmsItsTimer()
    testAnErrorCarriesItsWayOut()
    testTheMenuHasFiveEntriesAndClearingIsLast()
    testAReplyBecomesACard()
}

private func projection(_ mutate: (inout SessionMachine) -> Void) -> SessionProjection {
    var m = SessionMachine()
    mutate(&m)
    return m.projection
}

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

private func notices(_ effects: [SessionEffect]) -> [SessionEffect] {
    effects.filter { if case .scheduleNoticeExpiry = $0 { true } else { false } }
}

@MainActor func testTheLightIsAmberWhenItNeedsYouAndGreenWhenDone() {
    let asking = projection {
        _ = $0.handle(.job(.started(goal: "x")))
        _ = $0.handle(.job(.approvalRequested(request("r1"))))
    }
    expectEq(IslandState.from(asking, pebbleHidden: false).light, .amber, "luz: una hoja espera = ámbar")
    expectEq(IslandState.from(asking, pebbleHidden: false, mainInFront: true).light, .amber,
             "luz: ámbar aunque la hoja se pinte en la ventana")

    let done = projection { _ = $0.handle(.typedSubmitted); _ = $0.handle(.typedReplyFinished) }
    expectEq(IslandState.from(done, pebbleHidden: false).light, .green, "luz: terminado = verde")

    let running = projection { _ = $0.handle(.job(.started(goal: "x"))) }
    expectEq(IslandState.from(running, pebbleHidden: false).light, IslandState.Light.none,
             "luz: trabajando, sin luz")
    expectEq(IslandState.from(SessionProjection(), pebbleHidden: false).light, IslandState.Light.none,
             "luz: en reposo, sin luz")
}

@MainActor func testListeningHasNoStatusWords() {
    let listening = projection { _ = $0.handle(.pressed); _ = $0.handle(.partialTranscript("abre")) }
    let state = IslandState.from(listening, pebbleHidden: false)
    expectEq(state.line, IslandState.Line.none, "escucha: sin «Escuchando…»")
    expectEq(state.meter, .mic, "escucha: solo las barras")
    expectEq(state.partial, "abre", "escucha: el parcial debajo")
}

@MainActor func testANoticeFadesAfterSixSeconds() {
    expectEq(SessionMachine.noticeDelay, 6, "aviso: seis segundos, como Incredible")
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.released)
    let fx = m.handle(.heardNothing)
    expectEq(notices(fx), [.scheduleNoticeExpiry(SessionMachine.noticeDelay)], "no te oí: arma su cierre")
    _ = m.handle(.noticeExpired(.couldntHear))
    expect(m.projection.notice == nil, "no te oí: se va solo")
    expectEq(IslandState.from(m.projection, pebbleHidden: false).size, .pebble, "no te oí: vuelve al reposo")

    var hint = SessionMachine()
    _ = hint.handle(.pressed)
    expectEq(notices(hint.handle(.tapped)).count, 1, "pista: también se va sola")

    var denied = SessionMachine()
    _ = denied.handle(.voice(TurnSnapshot(state: .error, failure: .micDenied)))
    _ = denied.handle(.noticeExpired(.permission(.micDenied)))
    expectEq(denied.projection.notice, .permission(.micDenied),
             "permiso: no se va solo, lleva la salida")
}

@MainActor func testAFreshNoticeRearmsItsTimer() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.released)
    _ = m.handle(.heardNothing)
    _ = m.handle(.pressed)
    _ = m.handle(.released)
    expectEq(notices(m.handle(.heardNothing)).count, 1, "segundo «no te oí»: timer nuevo")
    var fromVoice = SessionMachine()
    let fx = fromVoice.handle(.voice(TurnSnapshot(state: .error, failure: .notHeard)))
    expectEq(notices(fx).count, 1, "la voz sin oír nada: también se va sola")
}

@MainActor func testAnErrorCarriesItsWayOut() {
    let keys = projection { _ = $0.handle(.voice(TurnSnapshot(state: .error, failure: .noProviders))) }
    expectEq(IslandState.from(keys, pebbleHidden: false).action, .openKeys, "error: sin clave → Claves")
    let mic = projection { _ = $0.handle(.voice(TurnSnapshot(state: .error, failure: .micDenied))) }
    expectEq(IslandState.from(mic, pebbleHidden: false).action, .openPermission(.micDenied),
             "error: permiso → su panel")
    let net = projection { _ = $0.handle(.voice(TurnSnapshot(state: .error, failure: .networkUnavailable))) }
    expect(IslandState.from(net, pebbleHidden: false).action == nil,
           "error: sin red, la frase sola; el próximo hold reconecta")
    expect(IslandState.from(SessionProjection(), pebbleHidden: false).action == nil, "reposo: sin acción")
}

@MainActor func testTheMenuHasFiveEntriesAndClearingIsLast() {
    expectEq(IslandMenuItem.allCases, [.settings, .openWindow, .shortcuts, .feedback, .clearHistory],
             "menú: los cinco de Incredible, en su orden")
    expect(IslandMenuItem.clearHistory.destructive, "menú: borrar historial va en rojo")
    expect(IslandMenuItem.allCases.filter(\.destructive).count == 1, "menú: solo uno es destructivo")
}

@MainActor func testAReplyBecomesACard() {
    let card = IslandResult(reply: "## Vuelos a Lima\n\nEl más barato sale el martes por **3.200 MXN**.\n- Aeroméxico")
    expectEq(card?.title, "Vuelos a Lima", "tarjeta: el título sin marcas")
    expectEq(card?.line, "El más barato sale el martes por 3.200 MXN.", "tarjeta: una línea sin marcas")
    let single = IslandResult(reply: "Listo, abrí Safari.")
    expectEq(single?.title, "Listo, abrí Safari.", "tarjeta: una frase es el título")
    expect(single?.line == nil, "tarjeta: sin segunda línea")
    let long = IslandResult(reply: String(repeating: "palabra ", count: 40))
    expect((long?.title.count ?? 0) <= IslandResult.maxTitle + 1, "tarjeta: el título se recorta")
    expect(IslandResult(reply: "  \n ") == nil, "tarjeta: vacío, nada")
}

// 16e: Incredible's voice never reads a card out; it says one sentence and
// points to it. Only the voice gets the rule; the typed chat shows the card.
@Test @MainActor func theVoicePointsToTheCard() {
    let es = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es, voice: true)
    expect(es.contains("no la leas: di una frase y señálala"), "voz es: apunta a la tarjeta")
    let en = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .en, voice: true)
    expect(en.contains("never read it out: say one sentence and point to it"), "voz en: apunta a la tarjeta")
    let typed = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .es)
    expect(!typed.contains("señálala"), "chat escrito: sin la regla")
}

// 16e: the hover panel has a field. Typing in it must not collapse the panel
// when the pointer drifts off: the draft or the focus keeps it open.
@Test @MainActor func theComposerStaysOpenWhileTyping() {
    let rest = SessionProjection()
    expectEq(IslandState.from(rest, pebbleHidden: false, composing: true).size, .nudge,
             "campo: escribiendo, el panel se queda")
    expectEq(IslandState.from(rest, pebbleHidden: true, composing: true).size, .nudge,
             "campo: aunque la marca esté oculta")
    expectEq(IslandState.from(rest, pebbleHidden: false).size, .pebble, "campo: sin escribir, reposo")
    var listening = SessionProjection()
    listening.kind = .listening
    expectEq(IslandState.from(listening, pebbleHidden: false, composing: true).size, .bar,
             "campo: un hold manda sobre el borrador")
    expect(!IslandState.acceptsPointer(size: .nudge, pointerDown: false),
           "campo: el panel ya no toma el gesto entero; tiene un campo")
    expect(IslandState.acceptsPointer(size: .bar, pointerDown: true),
           "campo: un hold que empezó en la marca sigue")
}

// Security review 16 (CRITICAL): the island's field holds the keyboard. An
// approval arriving while it does swapped the field for the sheet and left
// the panel key, so the next Return — meant for the draft — pressed Allow.
@Test @MainActor func anApprovalTakesTheKeyboardAwayFromTheField() {
    var asking = SessionProjection()
    asking.approvalQueue = [ApprovalRequest(requestId: "r1", toolName: "Bash", summary: "rm", inputJSON: "{}")]
    let state = IslandState.from(asking, pebbleHidden: false, composing: true)
    expectEq(state.size, .card, "hoja: reemplaza al campo")
    expect(state.yieldsKeyboard, "hoja: el panel devuelve el teclado")
    expect(!IslandState.from(SessionProjection(), pebbleHidden: false, composing: true).yieldsKeyboard,
           "sin hoja: el campo se queda con el teclado")
    expect(ApprovalSheet.allowShortcut == nil, "hoja: Return nunca aprueba; permitir es un clic")
    expect(!ApprovalClickGuard.gate(nil, requestId: "r", contentVisible: true, now: 100).accepts, "guarda ausente: no acepta (falla cerrada)")
    expect(ApprovalClickGuard.gate(ApprovalClickGuard(shownAt: 0, requestId: "r"), requestId: "r", contentVisible: true, now: 1).accepts, "guarda pasada: acepta")
}

// Code review 16 (HIGH): clicking another app took the keyboard but nothing
// told the field, so the panel stayed open over that app for ever.
@Test @MainActor func losingTheKeyboardClosesTheField() {
    var resigned = 0
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(), onHover: { _ in })
    panel.onResignKey = { resigned += 1 }
    panel.resignKey()
    expectEq(resigned, 1, "campo: perder el teclado avisa a la vista")
}
