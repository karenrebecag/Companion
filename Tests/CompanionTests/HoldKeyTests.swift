import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 12b. La tecla que se mantiene, lo que la island decide con la
// proyección, y la fila del permiso de Monitoreo de entrada. Todo puro.

@Test @MainActor func holdKeyTests() {
    pinLanguage()
    testTapVersusHold()
    testKeyboardHoldWaitsToArm()
    testKeyboardChordIsNotAHold()
    testFNArmsOnTheWayDown()
    testACancelledHoldClosesTheMicQuietly()
    testFNConfirmsTheHoldAtTheThreshold()
    testTheSessionHoldsNetworkWorkUntilTheConfirm()
    testACancelledTapDuringAReplyKeepsTheReplyOnScreen()
    testStopInsideTheReleaseTailCancelsTheCommit()
    testHoldTalkRowUsesAccessibility()
    testIslandStateFromProjection()
    testIslandYieldsTheSheetToMain()
    testPebbleShowsWhileTheMicIsEngaged()
    testApprovalClickGuard()
    testIslandCarriesThePartial()
    testTheHoldHintLearns()
    testInputMonitoringRow()
    testIslandShowsTheDictation()
    testTheNudgeDoesNotTeachADeadKey()
}

/// 1. Bajar emite `.pressed` de inmediato (la latencia manda); subir antes
/// del umbral es un tap, después un hold. Un up sin down y un auto-repeat
/// no emiten nada.
@MainActor func testTapVersusHold() {
    var k = HoldKeyClassifier(tapThreshold: 0.25)
    expectEq(k.up(at: 1), nil, "tecla: up sin down no es nada")
    expectEq(k.down(at: 1), .pressed, "tecla: bajar es pressed ya")
    expectEq(k.down(at: 1.05), nil, "tecla: el auto-repeat no vuelve a pulsar")
    expectEq(k.up(at: 1.1), .tapped, "tecla: soltar a 100 ms es un tap")
    expectEq(k.down(at: 2), .pressed, "tecla: otra vez")
    expectEq(k.up(at: 2.6), .released, "tecla: soltar a 600 ms es un hold")
    expectEq(k.up(at: 2.7), nil, "tecla: un segundo up no hace nada")

    // The island's mouse press must survive the island growing under it
    // (seen live 2026-09-06: the gesture left with the nudge and the
    // release never came, so the hold listened forever).
    var mouse = HoldKeyClassifier()
    expect(!mouse.isDown, "ratón: en reposo no está abajo")
    _ = mouse.down(at: 3)
    expect(mouse.isDown, "ratón: abajo mientras se mantiene")
    expect(IslandState.acceptsPointer(size: .bar, pointerDown: true), "island: la barra sigue el gesto que empezó en el nudge")
    expect(!IslandState.acceptsPointer(size: .nudge, pointerDown: false),
           "island: el nudge tiene un campo (16e); el hold empieza en la marca")
    expect(!IslandState.acceptsPointer(size: .bar, pointerDown: false), "island: la barra en reposo no roba clics a sus botones")
    expect(!IslandState.acceptsPointer(size: .card, pointerDown: false), "island: la card tampoco")
    _ = mouse.up(at: 4)
    expect(!mouse.isDown, "ratón: soltar lo levanta")
}

/// Keyboard path (12h): a tap must not arm the mic. Pressed fires only
/// after the threshold, while the key is still down.
@MainActor func testKeyboardHoldWaitsToArm() {
    var k = HoldKeyClassifier(tapThreshold: 0.25)
    expectEq(k.begin(at: 1), nil, "tecla: bajar no arma el micro")
    expect(k.isDown, "tecla: está abajo")
    expectEq(k.confirm(at: 1.1), nil, "tecla: antes del umbral no confirma")
    expectEq(k.up(at: 1.15), .tapped, "tecla: soltar pronto es un tap")
    expectEq(k.begin(at: 2), nil, "tecla: otra vez")
    expectEq(k.confirm(at: 2.25), .pressed, "tecla: al umbral sí arma")
    expectEq(k.confirm(at: 2.3), nil, "tecla: confirmar dos veces no vuelve a pulsar")
    expectEq(k.up(at: 2.8), .released, "tecla: soltar después es un hold")
}

/// FN+flecha no es hablar: un acorde antes de armar se descarta.
@MainActor func testKeyboardChordIsNotAHold() {
    var k = HoldKeyClassifier(tapThreshold: 0.25)
    expectEq(k.begin(at: 1), nil, "acorde: FN abajo")
    expectEq(k.chord(), nil, "acorde: antes de armar no emite")
    expectEq(k.confirm(at: 1.3), nil, "acorde: no arma")
    expectEq(k.up(at: 1.4), nil, "acorde: soltar no es tap ni hold")
    expect(!k.isDown, "acorde: quedó en reposo")

    expectEq(k.begin(at: 2), nil, "acorde: FN otra vez")
    expectEq(k.confirm(at: 2.25), .pressed, "acorde: ya armó")
    expectEq(k.chord(), .tapped, "acorde: una tecla más descarta el hold, no lo envía")
    expect(!k.isDown, "acorde: no sigue escuchando")
    expectEq(k.up(at: 2.4), nil, "acorde: el up ya no es un release")
}

/// Wave 15d-1 (TDD row 1, key side): FN opens the mic on the way down —
/// the 250 ms tap threshold was eating the first word. A short up or a
/// chord cancels what opened; a long up is the release.
@MainActor func testFNArmsOnTheWayDown() {
    var k = HoldKeyClassifier(tapThreshold: 0.25)
    expectEq(k.press(at: 1), .pressed, "FN: bajar ya es pressed")
    expectEq(k.press(at: 1.05), nil, "FN: el auto-repeat no vuelve a pulsar")
    expectEq(k.up(at: 1.1), .cancelled, "FN: soltar a 100 ms cancela, no es un tap que enseña")
    expect(!k.isDown, "FN: queda en reposo")
    expectEq(k.press(at: 2), .pressed, "FN: otra vez")
    expectEq(k.up(at: 2.4), .released, "FN: soltar a 400 ms es el hold")
    expectEq(k.press(at: 3), .pressed, "FN: y otra")
    expectEq(k.chord(), .cancelled, "FN+tecla: cancela lo que abrió")
    expectEq(k.up(at: 3.6), nil, "FN+tecla: el up ya no es un release")
    expectEq(k.press(at: 4), .pressed, "FN: tras el acorde, vuelve a armar")
    expectEq(k.chord(), .cancelled, "FN+tecla antes del umbral: también cancela")
}

/// 15d-1: a cancelled hold closes the mic without sending — and unlike a
/// pointer tap, teaches nothing: FN tapped was never a mistake to correct.
@MainActor func testACancelledHoldClosesTheMicQuietly() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    let effects = m.handle(.holdCancelled)
    expect(effects.contains(.stopListening(commit: false)), "cancelado: cierra el micro sin enviar")
    expect(!effects.contains(.stopListening(commit: true)), "cancelado: nunca envía")
    expectEq(m.projection.kind, .idle, "cancelado: vuelve a reposo")
    expect(m.projection.notice == nil, "cancelado: sin aviso")
    expect(!m.projection.holding, "cancelado: ya no mantiene")
    expectEq(m.handle(.holdCancelled), [], "cancelado: sin hold no hay nada que cerrar")
}

/// Code review 2026-09-24: FN opens the mic on the way down, so the tap
/// threshold now has to be said out loud — `.confirmed` is when a press
/// stops being a possible tap and network work may start.
@MainActor func testFNConfirmsTheHoldAtTheThreshold() {
    var k = HoldKeyClassifier(tapThreshold: 0.25)
    expectEq(k.press(at: 1), .pressed, "confirmar: bajar sigue siendo pressed")
    expectEq(k.confirm(at: 1.1), nil, "confirmar: antes del umbral nada")
    expectEq(k.confirm(at: 1.25), .confirmed, "confirmar: al umbral, confirmed")
    expectEq(k.confirm(at: 1.3), nil, "confirmar: una sola vez")
    expectEq(k.up(at: 1.6), .released, "confirmar: y soltar es el hold")
    expectEq(k.press(at: 2), .pressed, "confirmar: otra vez")
    expectEq(k.up(at: 2.1), .cancelled, "confirmar: un tap nunca confirma")
    expectEq(k.press(at: 3), .pressed, "confirmar: y otra")
    expectEq(k.confirm(at: 3.3), .confirmed, "confirmar: confirmado")
    expectEq(k.chord(), .cancelled, "confirmar: un acorde después sigue cancelando")
    var mouse = HoldKeyClassifier(tapThreshold: 0.25)
    _ = mouse.down(at: 4)
    expectEq(mouse.confirm(at: 4.3), nil, "confirmar: el puntero no emite confirmed")
}

@MainActor func testTheSessionHoldsNetworkWorkUntilTheConfirm() {
    var m = SessionMachine()
    let down = m.handle(.pressedProvisionally)
    expectEq(down.filter { if case .logTransition = $0 { false } else { true } },
             [.startProvisionalListening], "sesión: FN abajo abre solo lo local")
    expectEq(m.projection.kind, .listening, "sesión: el chrome escucha ya")
    expectEq(m.handle(.holdConfirmed), [.confirmListening], "sesión: al umbral, confirma")
    _ = m.handle(.released)
    expectEq(m.handle(.holdConfirmed), [], "sesión: sin hold no hay nada que confirmar")
}

/// A tap during a reply never cut it; the chrome goes back to the reply
/// instead of painting idle over a voice that is still talking.
@MainActor func testACancelledTapDuringAReplyKeepsTheReplyOnScreen() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic)))
    _ = m.handle(.pressedProvisionally)
    _ = m.handle(.holdCancelled)
    expectEq(m.projection.kind, .processing(.speaking), "tap en respuesta: el chrome sigue hablando")
}

/// Esc during the 300 ms release tail: the voice is still `.listening`, so
/// the old stop sent it nothing and the tail committed anyway.
@MainActor func testStopInsideTheReleaseTailCancelsTheCommit() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, holdArmed: true)))
    _ = m.handle(.released)
    expectEq(m.projection.kind, .processing(.pending), "cola: pending")
    let effects = m.handle(.stop)
    expect(effects.contains(.stopListening(commit: false)), "cola: Esc descarta lo que iba a enviar")
    expect(!effects.contains(.stopListening(commit: true)), "cola: nunca lo envía")
}

private func projection(_ mutate: (inout SessionMachine) -> Void) -> SessionProjection {
    var m = SessionMachine()
    mutate(&m)
    return m.projection
}

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

/// 26. Lo que la island pinta sale de una función pura sobre la proyección.
@MainActor func testIslandStateFromProjection() {
    let idle = IslandState.from(SessionProjection(), pebbleHidden: false)
    expectEq(idle.size, .pebble, "island: idle es el pebble")
    expectEq(idle.meter, .none, "island: sin medidor")
    expectEq(idle.line, .none, "island: sin texto")
    expect(!idle.showsStop, "island: sin stop")

    let hidden = IslandState.from(SessionProjection(), pebbleHidden: true)
    expectEq(hidden.size, .hidden, "island: pebble oculto")

    let hover = projection { _ = $0.handle(.hoverEntered) }
    let h = IslandState.from(hover, pebbleHidden: true)
    expectEq(h.size, .nudge, "island: hover crece aunque el pebble esté oculto")
    expectEq(h.line, .holdHint, "island: hover enseña el hold")

    let listening = projection { _ = $0.handle(.pressed) }
    let l = IslandState.from(listening, pebbleHidden: false)
    expectEq(l.size, .bar, "island: escuchando es la barra")
    expectEq(l.meter, .mic, "island: medidor del micro")
    expectEq(l.line, IslandState.Line.none, "island: sin texto de estado (16e)")
    expect(!l.showsStop, "island: en hold no hay stop, se suelta")

    let handsFree = projection { _ = $0.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime))) }
    expect(IslandState.from(handsFree, pebbleHidden: false).showsStop,
           "island: manos libres sí tiene stop")

    let pending = projection { _ = $0.handle(.pressed); _ = $0.handle(.released) }
    let p = IslandState.from(pending, pebbleHidden: false)
    expectEq(p.line, .pending, "island: soltar es «…»")
    expectEq(p.meter, .none, "island: el medidor se apaga al soltar")
    expect(p.showsStop, "island: y ya se puede parar")

    let acting = projection { _ = $0.handle(.typedSubmitted); _ = $0.handle(.parentActing(targets: ["Safari"])) }
    expectEq(IslandState.from(acting, pebbleHidden: false).line, .acting(["Safari"]),
             "island: las manos del padre nombran el objetivo")

    let speaking = projection {
        _ = $0.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime)))
        _ = $0.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime)))
    }
    expectEq(IslandState.from(speaking, pebbleHidden: false).meter, .agent, "island: nivel del agente")

    let job = projection {
        _ = $0.handle(.job(.started(goal: "buscar vuelos")))
        _ = $0.handle(.job(.stepStarted(tool: "WebSearch", summary: "Lima")))
    }
    let j = IslandState.from(job, pebbleHidden: false)
    expectEq(j.size, .card, "island: el encargo es una fila grande")
    expectEq(j.line, .job(goal: "buscar vuelos", step: "WebSearch: Lima", steps: 1), "island: la fila del hijo")
    expect(j.showsStop, "island: el hijo se puede parar")

    let approval = projection {
        _ = $0.handle(.job(.started(goal: "x")))
        _ = $0.handle(.job(.approvalRequested(request("r1"))))
    }
    let a = IslandState.from(approval, pebbleHidden: false)
    expectEq(a.size, .card, "island: la hoja es la card grande")
    expectEq(a.approval?.requestId, "r1", "island: y lleva la petición")

    let completed = projection { _ = $0.handle(.typedSubmitted); _ = $0.handle(.typedReplyFinished) }
    expectEq(IslandState.from(completed, pebbleHidden: false).line, .completed, "island: hecho")

    let denied = projection { _ = $0.handle(.voice(TurnSnapshot(state: .error, failure: .micDenied))) }
    let d = IslandState.from(denied, pebbleHidden: true)
    expectEq(d.size, .card, "island: un permiso denegado se ve aunque el pebble esté oculto")
    expectEq(d.line, .permission(.micDenied), "island: con el enlace")

    let nothing = projection { _ = $0.handle(.pressed); _ = $0.handle(.released); _ = $0.handle(.heardNothing) }
    let n = IslandState.from(nothing, pebbleHidden: false)
    expectEq(n.line, .couldntHear, "island: «no te oí»")
    expectEq(n.size, .card, "island: como card, no como pebble")
}

/// 26b. Code review 2026-09-06 (alto): con main delante, la hoja se pinta
/// en la ventana y la island no la duplica.
@MainActor func testIslandYieldsTheSheetToMain() {
    let approval = projection {
        _ = $0.handle(.job(.started(goal: "x")))
        _ = $0.handle(.job(.approvalRequested(request("r1"))))
    }
    let behind = IslandState.from(approval, pebbleHidden: false, mainInFront: false)
    expectEq(behind.approval?.requestId, "r1", "hoja: con main detrás la island la hospeda")
    let front = IslandState.from(approval, pebbleHidden: false, mainInFront: true)
    expect(front.approval == nil, "hoja: con main delante la island no la duplica")
    expectEq(front.size, .card, "hoja: la fila del encargo sigue")
}

/// 26c. Security review 2026-09-06 (alto): mientras la sesión de voz sigue
/// abierta el pebble no se esconde: es el único indicador propio de que el
/// micro está tomado.
@MainActor func testPebbleShowsWhileTheMicIsEngaged() {
    let warm = projection {
        _ = $0.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)))
    }
    expectEq(IslandState.from(warm, pebbleHidden: true).size, .pebble,
             "pebble: con la voz caliente no se oculta")
    expectEq(IslandState.from(SessionProjection(), pebbleHidden: true).size, .hidden,
             "pebble: con la voz apagada sí")
}

/// 26d. Security review 2026-09-06 (medio): la hoja recién aparecida sobre
/// otra app ignora el clic que ya iba en camino.
@MainActor func testApprovalClickGuard() {
    let guardOn = ApprovalClickGuard(shownAt: 10)
    expect(!guardOn.accepts(at: 10.2), "hoja: un clic a 200 ms no cuenta")
    expect(guardOn.accepts(at: 11), "hoja: pasado el reposo sí")
}

/// 28 (12c). La island lleva el parcial en Listening y en Pending, y en
/// ninguna otra fase.
@MainActor func testIslandCarriesThePartial() {
    let listening = projection { _ = $0.handle(.pressed); _ = $0.handle(.partialTranscript("abre")) }
    expectEq(IslandState.from(listening, pebbleHidden: false).partial, "abre", "parcial: escuchando lo lleva")
    let pending = projection {
        _ = $0.handle(.pressed); _ = $0.handle(.partialTranscript("abre")); _ = $0.handle(.released)
    }
    expectEq(IslandState.from(pending, pebbleHidden: false).partial, "abre", "parcial: enviando lo conserva")
    let thinking = projection {
        _ = $0.handle(.pressed); _ = $0.handle(.partialTranscript("abre")); _ = $0.handle(.released)
        _ = $0.handle(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime, holdArmed: true)))
    }
    expect(IslandState.from(thinking, pebbleHidden: false).partial == nil, "parcial: pensando no")
}

/// 29 (12c). La pista del hold se enseña hasta el primer hold completado;
/// un tap la pide siempre.
@MainActor func testTheHoldHintLearns() {
    let hover = projection { _ = $0.handle(.hoverEntered) }
    expectEq(IslandState.from(hover, pebbleHidden: false, holdLearned: false).line, .holdHint,
             "pista: la primera vez se enseña")
    let learned = IslandState.from(hover, pebbleHidden: false, holdLearned: true)
    expectEq(learned.size, .nudge, "pista: aprendida, el hover sigue creciendo")
    expectEq(learned.line, .none, "pista: aprendida, sin texto")
    let tapped = projection { _ = $0.handle(.tapped) }
    expectEq(IslandState.from(tapped, pebbleHidden: false, holdLearned: true).line, .holdHint,
             "pista: un tap la pide aunque esté aprendida")
}

/// 27. La fila de Monitoreo de entrada: título, cuerpo y enlace.
@MainActor func testInputMonitoringRow() {
    let row = PermissionRowModel(kind: .inputMonitoring, granted: false)
    expect(!row.title.contains("permission."), "fila: título del catálogo")
    expect(!row.body.contains("permission."), "fila: cuerpo del catálogo")
    expectEq(row.link, PermissionSettingsLink.inputMonitoring, "fila: el enlace correcto")
    expect(row.link.absoluteString.contains("Privacy_ListenEvent"), "fila: al panel de Monitoreo de entrada")
    expect(row.showsButton, "fila: sin permiso hay botón")
}

/// 12h. FN usa Accesibilidad (como Incredible), no Monitoreo de entrada.
@MainActor func testHoldTalkRowUsesAccessibility() {
    let hold = HoldSettingsModel(permission: FakeAccessibility(trusted: false))
    expectEq(hold.row.kind, .accessibility, "hablar: la fila es Accesibilidad")
    expectEq(hold.row.link, PermissionSettingsLink.accessibility, "hablar: enlace al panel correcto")
    expect(!hold.granted, "hablar: sin confianza AX el tap no está")
    expect(hold.row.showsButton, "hablar: sin permiso hay botón")
}

/// 30 (12e). La island dice dónde dicta, que pega, y dónde pegó; el fallo
/// de Accesibilidad lleva su enlace.
@MainActor func testIslandShowsTheDictation() {
    let listening = projection {
        _ = $0.handle(.pressed)
        _ = $0.handle(.dictating(app: "Slack"))
        _ = $0.handle(.partialTranscript("hola"))
    }
    let l = IslandState.from(listening, pebbleHidden: false)
    expectEq(l.line, .dictating("Slack"), "island: «dictando en Slack»")
    expectEq(l.meter, .mic, "island: con el medidor del micro")
    expectEq(l.partial, "hola", "island: y el parcial")
    expect(!l.showsStop, "island: en hold no hay stop")

    let pending = projection {
        _ = $0.handle(.pressed)
        _ = $0.handle(.dictating(app: "Slack"))
        _ = $0.handle(.released)
    }
    expectEq(IslandState.from(pending, pebbleHidden: false).line, .pasting, "island: «pegando»")

    let done = projection {
        _ = $0.handle(.pressed)
        _ = $0.handle(.dictating(app: "Slack"))
        _ = $0.handle(.released)
        _ = $0.handle(.dictated(app: "Slack"))
    }
    let d = IslandState.from(done, pebbleHidden: false)
    expectEq(d.size, .bar, "island: pegado es la barra")
    expectEq(d.line, .dictated("Slack"), "island: «pegado en Slack»")

    let plain = projection { _ = $0.handle(.typedSubmitted); _ = $0.handle(.typedReplyFinished) }
    expectEq(IslandState.from(plain, pebbleHidden: false).line, .completed, "island: sin dictado, «listo»")

    let denied = projection {
        _ = $0.handle(.pressed)
        _ = $0.handle(.released)
        _ = $0.handle(.dictationFailed(.needsAccessibility))
        // The words went to Companion: its turn runs and the chrome rests.
        _ = $0.handle(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime)))
        _ = $0.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true)))
        _ = $0.handle(.completedTimerExpired)
    }
    let n = IslandState.from(denied, pebbleHidden: false)
    expectEq(n.line, .permission(.accessibilityDenied), "island: el permiso que falta")
    expectEq(VoiceCopy.settingsLink(for: .accessibilityDenied), PermissionSettingsLink.accessibility,
             "island: con el enlace a Accesibilidad")
    expect(IslandCopy.line(.dictating("Slack")).contains("Slack"), "copy: nombra la app")
    expect(IslandCopy.line(.dictated("Slack")).contains("Slack"), "copy: y al pegar también")
    expect(!IslandCopy.line(.pasting).isEmpty, "copy: pegando tiene texto")
    expect(IslandCopy.shimmers(.pasting), "copy: pegando brilla como enviar")
    expect(!VoiceCopy.failure(.accessibilityDenied).isEmpty, "copy: el fallo tiene texto")
}

/// 31 (12e, en vivo 2026-09-06). Sin Monitoreo de entrada la tecla no
/// existe: el nudge no puede enseñar "Mantén FN" como si funcionara.
@MainActor func testTheNudgeDoesNotTeachADeadKey() {
    let hover = projection { _ = $0.handle(.hoverEntered) }
    let live = IslandState.from(hover, pebbleHidden: false, keyListening: true)
    expectEq(live.line, .holdHint, "tecla viva: enseña el hold")

    let dead = IslandState.from(hover, pebbleHidden: false, keyListening: false)
    expectEq(dead.size, .nudge, "tecla muerta: el nudge sigue creciendo")
    expectEq(dead.line, .keyBlocked, "tecla muerta: dice que FN no está activa")

    let learned = IslandState.from(
        hover, pebbleHidden: false, holdLearned: true, keyListening: false)
    expectEq(learned.line, .keyBlocked,
             "tecla muerta: aunque ya sepa el hold, la tecla sigue sin oírse")
    expectEq(IslandState.from(hover, pebbleHidden: false, holdLearned: true).line, .none,
             "tecla viva y aprendida: nada que enseñar")

    let listening = projection { _ = $0.handle(.pressed) }
    let pointerHold = IslandState.from(listening, pebbleHidden: false, keyListening: false)
    expectEq(pointerHold.meter, .mic, "tecla muerta: el clic mantenido sigue escuchando igual")
    expectEq(pointerHold.line, IslandState.Line.none, "tecla muerta: sin texto de estado (16e)")
    expect(!IslandCopy.line(.keyBlocked).isEmpty, "copy: la línea tiene texto")
}
