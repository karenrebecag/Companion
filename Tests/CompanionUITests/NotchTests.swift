import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Wave 16f (spec 16f): the island grows out of the notch. The notch is
// measured, the window never moves, the shape does, and the motion follows
// the numbers taken from Karen's recording of Incredible.

@Test @MainActor func notchTests() {
    testANotchIsMeasuredFromTheScreen()
    testWithoutANotchItIsAPillAsTallAsTheMenuBar()
    testTheNotchedScreenWins()
    testTheWindowNeverMoves()
    testTheShapeRestsAsTheNotch()
    testThePointerOnlyCountsInsideTheShape()
    testOpeningIsShapeFirstThenContent()
    testClosingIsContentFirstThenShape()
    testAnOpenIslandGrowsWithTheIslandCurveAndShrinksWithoutBounce()
    testTheContentFadesWithTheCssEase()
    testTheIslandCurveOvershootsAsIncrediblesDoes()
    testTheContentFadesInBeforePhaseTwo()
    testGrowingIsMoreArea()
    testReduceMotionHasNoSpring()
    testWordsArriveAtSpeakingPace()
    testTheReplyIsTheSpokenPartInPlainWords()
    testTypingNeverWidensTheClickableArea()
    testALinkFloodIsCheap()
    testTheShapeSettlesBeforeAllowCanBeClicked()
    testClosingKeepsTheClickAreaUntilTheShapeIsSmall()
    testAStrayBracketDoesNotStopTheLinks()
}

private let macbook = ScreenShape(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982), visibleMaxY: 945,
    safeTop: 38, leftAuxWidth: 662, rightAuxWidth: 662)
private let external = ScreenShape(
    frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), visibleMaxY: 1415,
    safeTop: 0, leftAuxWidth: nil, rightAuxWidth: nil)

func testANotchIsMeasuredFromTheScreen() {
    let notch = NotchGeometry.notch(on: macbook)
    expect(notch.isHardware, "notch: la Mac tiene muesca")
    expectEq(notch.width, 188, "notch: ancho = pantalla menos las dos zonas de la barra")
    expectEq(notch.height, 38, "notch: alto = el inset de arriba")
    expectEq(notch.midX, 756, "notch: centrado")
    expectEq(notch.top, 982, "notch: pegado al borde de la pantalla, no a la barra de menús")
}

func testWithoutANotchItIsAPillAsTallAsTheMenuBar() {
    let pill = NotchGeometry.notch(on: external)
    expect(!pill.isHardware, "sin muesca: píldora")
    expectEq(pill.width, NotchGeometry.pillWidth, "sin muesca: ancho de píldora")
    expectEq(pill.height, 25, "sin muesca: el alto de la barra de menús")
    expectEq(pill.midX, 1512 + 1280, "sin muesca: centrada en esa pantalla")
    let odd = ScreenShape(frame: macbook.frame, visibleMaxY: 982, safeTop: 0,
                          leftAuxWidth: nil, rightAuxWidth: nil)
    expectEq(NotchGeometry.notch(on: odd).height, NotchGeometry.minHeight, "sin barra: alto mínimo")
    let lopsided = ScreenShape(frame: macbook.frame, visibleMaxY: 945, safeTop: 38,
                               leftAuxWidth: 600, rightAuxWidth: 700)
    expectEq(NotchGeometry.notch(on: lopsided).midX, 756, "notch descentrado imposible: centrado")
}

func testTheNotchedScreenWins() {
    expectEq(NotchGeometry.pick([external, macbook]), 1, "pantallas: la que tiene muesca")
    expectEq(NotchGeometry.pick([external]), 0, "pantallas: sin muesca, la primera (la de la barra)")
    expectEq(NotchGeometry.pick([]), nil, "pantallas: ninguna")
}

@MainActor func testTheWindowNeverMoves() {
    let notch = NotchGeometry.notch(on: macbook)
    let frames = IslandState.Size.allCases.map { _ in IslandChrome.canvasFrame(for: notch) }
    expect(Set(frames.map { "\($0)" }).count == 1, "ventana: un solo marco para todos los tamaños")
    let frame = IslandChrome.canvasFrame(for: notch)
    expectEq(frame.maxY, notch.top, "ventana: arriba del todo, sobre la barra de menús")
    expectEq(frame.midX, notch.midX, "ventana: centrada en la muesca")
    expect(frame.width >= IslandChrome.cardWidth, "ventana: cabe la tarjeta")
}

@MainActor func testTheShapeRestsAsTheNotch() {
    let notch = NotchGeometry.notch(on: macbook)
    let rest = IslandChrome.shapeSize(for: .pebble, contentHeight: 300, notch: notch)
    expectEq(rest, CGSize(width: notch.width, height: notch.height), "forma: en reposo es la muesca")
    let open = IslandChrome.shapeSize(for: .card, contentHeight: 300, notch: notch)
    expectEq(open.width, IslandChrome.cardWidth, "forma: abierta, el ancho del rol")
    expectEq(open.height, 300, "forma: abierta, el alto del contenido")
    let tiny = IslandChrome.shapeSize(for: .bar, contentHeight: 10, notch: notch)
    expect(tiny.height >= notch.height, "forma: nunca más baja que la muesca")
    let huge = IslandChrome.shapeSize(for: .card, contentHeight: 5_000, notch: notch)
    expect(huge.height <= IslandChrome.canvasHeight, "forma: nunca más alta que la ventana")
    expectEq(NotchShape.clampedRadius(40, height: 30), 15, "forma: el radio no pasa de la mitad del alto")
}

@MainActor func testThePointerOnlyCountsInsideTheShape() {
    let notch = NotchGeometry.notch(on: macbook)
    let rest = IslandChrome.shapeRect(IslandChrome.shapeSize(for: .pebble, contentHeight: 0, notch: notch),
                                      notch: notch)
    expect(IslandChrome.pointerInside(CGPoint(x: 756, y: 975), rect: rest), "puntero: sobre la muesca abre")
    expect(!IslandChrome.pointerInside(CGPoint(x: 756, y: 800), rect: rest), "puntero: debajo, no")
    expect(!IslandChrome.pointerInside(CGPoint(x: 300, y: 975), rect: rest), "puntero: en la barra de menús, no")
    let open = IslandChrome.shapeRect(IslandChrome.shapeSize(for: .card, contentHeight: 300, notch: notch),
                                      notch: notch)
    expect(IslandChrome.pointerInside(CGPoint(x: 756, y: 700), rect: open), "puntero: dentro del panel")
    expect(!IslandChrome.pointerInside(CGPoint(x: 756, y: 600), rect: open),
           "puntero: bajo el panel pasa a la app de atrás")
}

@MainActor func testOpeningIsShapeFirstThenContent() {
    let steps = IslandMotion.steps(from: .pebble, to: .nudge, reduceMotion: false)
    expectEq(steps.map(\.stage), [.pill, .full], "abrir: píldora y luego panel")
    expectEq(steps.first?.delay, 0, "abrir: la píldora sale ya")
    expectEq(steps.last?.delay, IslandMotion.secondPhase, "abrir: el panel a los 160 ms")
    // Incredible 0.2.36: every shape change is one 330 ms --ease-island curve (D5b, literal).
    expectEq(steps.first?.curve, .timing(MotionCurve.island, 0.33), "abrir: fase 1 con la curva de la isla")
    expectEq(steps.last?.curve, .timing(MotionCurve.island, 0.33), "abrir: fase 2 con la misma curva")
    expectEq(MotionCurve.island, [0.22, 1.22, 0.36, 1], "abrir: --ease-island")
    expectEq(IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false), 0.06,
             "abrir: el contenido entra a los 60 ms de empezar a abrir")
    expectEq(IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: true), 0,
             "reducir movimiento: el contenido no espera")
    expectEq(IslandMotion.steps(from: .bar, to: .card, reduceMotion: false).map(\.stage), [.full],
             "cambio dentro del panel: una sola interpolación")
}

@MainActor func testClosingIsContentFirstThenShape() {
    let steps = IslandMotion.steps(from: .card, to: .pebble, reduceMotion: false)
    expectEq(steps.map(\.stage), [.notch], "cerrar: de vuelta a la muesca")
    expectEq(steps.first?.delay, 0, "cerrar: la forma y el contenido se van juntos (16i §5)")
    expectEq(steps.first?.curve, .timing(MotionCurve.standard, 0.28), "cerrar: 280 ms standard, sin rebote")
    expectEq(IslandMotion.closeFade, IslandMotionBudget.contentIn.duration,
             "cerrar: el contenido sale en lo mismo que entra, 130 ms")
}

@MainActor func testAnOpenIslandGrowsWithTheIslandCurveAndShrinksWithoutBounce() {
    expectEq(IslandMotion.steps(from: .bar, to: .card, reduceMotion: false, growing: true).first?.curve,
             .timing(MotionCurve.island, 0.33), "abierta: crecer con la misma curva que abrir")
    expectEq(IslandMotion.steps(from: .card, to: .bar, reduceMotion: false, growing: false).first?.curve,
             .timing(MotionCurve.standard, 0.26), "abierta: encoger en 260 ms standard")
    expectEq(IslandMotion.resize(growing: true), .timing(MotionCurve.island, 0.33), "contenido que crece")
    expectEq(IslandMotion.resize(growing: false), .timing(MotionCurve.standard, 0.26), "contenido que encoge")
}

/// Code review (HIGH): the content waited for the loop over the shape's steps, so it
/// faded in at 160 ms with phase 2 instead of at 60 ms.
@MainActor func testTheContentFadesInBeforePhaseTwo() {
    let opening = IslandMotion.timeline(from: .pebble, to: .nudge, reduceMotion: false)
    expectEq(opening.map(\.at), [0, 0.06, 0.16], "abrir: píldora, contenido, panel")
    expectEq(opening.map(\.event), [.shape(.pill), .content, .shape(.full)], "abrir: el contenido antes de la fase 2")
    let closing = IslandMotion.timeline(from: .card, to: .pebble, reduceMotion: false)
    expectEq(closing.map(\.event), [.shape(.notch)], "cerrar: el contenido no vuelve a entrar")
    expectEq(IslandMotion.timeline(from: .pebble, to: .nudge, reduceMotion: true).map(\.at), [0, 0],
             "reducir movimiento: todo a la vez")
    expectEq(IslandMotion.emptyPanel(from: .pebble, to: .nudge), 0, "abrir: el panel nunca se ve vacío")
}

@MainActor func testGrowingIsMoreArea() {
    expect(IslandMotion.grows(from: CGSize(width: 400, height: 100), to: CGSize(width: 400, height: 200)), "más alto crece")
    expect(!IslandMotion.grows(from: CGSize(width: 400, height: 200), to: CGSize(width: 400, height: 100)), "más bajo encoge")
    expect(!IslandMotion.grows(from: CGSize(width: 500, height: 100), to: CGSize(width: 400, height: 100)),
           "solo más angosto encoge, sin sobrepaso")
    expect(!IslandMotion.grows(from: CGSize(width: 400, height: 100), to: CGSize(width: 400, height: 100)),
           "igual no rebota")
}

@MainActor func testTheContentFadesWithTheCssEase() {
    let move = IslandMotionBudget.contentIn
    expectEq(move.duration, 0.13, "contenido: 130 ms")
    expectEq(move.curve, MotionCurve.ease, "contenido: curva ease de CSS")
    expectEq(IslandMotionBudget.contentOut.duration, 0.13, "contenido: sale en 130 ms")
    expectEq(IslandMotionBudget.contentOut.curve, MotionCurve.ease, "contenido: sale con ease de CSS")
    expectEq(IslandMotion.closeFade, IslandMotionBudget.contentOut.duration, "cerrar: el fundido es contentOut")
    expectEq(MotionCurve.ease, [0.25, 0.1, 0.25, 1], "ease de CSS, no easeInOut")
    expectEq(move.blur, 0, "contenido: solo fundido, sin desenfoque")
    expectEq(move.offset, 0, "contenido: solo fundido, sin subir")
}

@MainActor func testTheIslandCurveOvershootsAsIncrediblesDoes() {
    let peak = (0...200).map { MotionCurve.value(MotionCurve.island, at: Double($0) / 200) }.max() ?? 0
    expect(peak > 1.01 && peak < 1.02, "--ease-island sobrepasa ~1,5 %: \(peak)")
    expect(abs(MotionCurve.settledAt(MotionCurve.island, duration: 0.33) - 0.126) < 0.005,
           "--ease-island queda a 2 % a los ~126 ms")
    expect(abs(MotionCurve.value(MotionCurve.standard, at: 1) - 1) < 1e-6, "standard llega")
    expect(abs(MotionCurve.value(MotionCurve.standard, at: 0)) < 1e-6, "standard arranca en 0")
    expect(abs(MotionCurve.value([0, 0, 1, 1], at: 0.5) - 0.5) < 1e-6, "lineal: la mitad a la mitad")
    expect(abs(MotionCurve.value(MotionCurve.ease, at: 0.5) - 0.8024) < 0.001, "ease de CSS en x = 0,5")
    expectEq(MotionCurve.settledAt([0, 0, 1, 1], duration: 1), 0.98, "lineal: entra al 2 % al 98 %")
}

@MainActor func testReduceMotionHasNoSpring() {
    for (from, to) in [(IslandState.Size.pebble, IslandState.Size.nudge), (.card, .pebble), (.bar, .card)] {
        let steps = IslandMotion.steps(from: from, to: to, reduceMotion: true)
        expectEq(steps.count, 1, "reducir movimiento: un paso")
        expect(steps.allSatisfy { if case .fade = $0.curve { true } else { false } },
               "reducir movimiento: fundido, sin resorte")
    }
}

@MainActor func testWordsArriveAtSpeakingPace() {
    expectEq(IslandReveal.shown(words: 10, elapsed: 0, speaking: true), 1, "palabras: la primera ya")
    expectEq(IslandReveal.shown(words: 10, elapsed: 1, speaking: true), 1 + Int(IslandReveal.wordsPerSecond),
             "palabras: al ritmo de la voz")
    expectEq(IslandReveal.shown(words: 10, elapsed: 60, speaking: true), 10, "palabras: nunca más de las que hay")
    expectEq(IslandReveal.shown(words: 10, elapsed: 0, speaking: false), 10, "palabras: sin voz, todas")
}

@MainActor func testTheReplyIsTheSpokenPartInPlainWords() {
    // F2 (brief isla-maquetacion-incredible): every paragraph, not the first.
    expectEq(IslandReplyText.spoken(from: "## Vuelos a Lima\n\nEl más **barato** sale el martes."),
             "Vuelos a Lima\n\nEl más barato sale el martes.", "respuesta: todos los párrafos, sin marcas")
    expectEq(IslandReplyText.spoken(from: "Listo. Abrí [Safari](https://apple.com) y `busqué`."),
             "Listo. Abrí Safari y busqué.", "respuesta: enlaces y código como texto")
    let long = String(repeating: "palabra ", count: 80)
    expectEq(IslandReplyText.spoken(from: long).split(separator: " ").count, 80, "respuesta: entera, sin corte")
    expectEq(IslandReplyText.spoken(from: "   "), "", "respuesta: vacía")
}

/// Security review 16f (HIGH): with the field focused the whole canvas took
/// clicks, eating the menu bar and the app behind outside the shape.
@MainActor func testTypingNeverWidensTheClickableArea() {
    expect(IslandChrome.ignoresPointer(inside: false, isKey: true), "teclado: fuera de la forma, el clic pasa")
    expect(IslandChrome.ignoresPointer(inside: false, isKey: false), "fuera de la forma, el clic pasa")
    expect(!IslandChrome.ignoresPointer(inside: true, isKey: false), "dentro de la forma, el clic es de la isla")
}

/// Security review 16f (MEDIUM): model text with thousands of links made
/// the stripping quadratic on the main thread, on every streamed token.
@MainActor func testALinkFloodIsCheap() {
    let flood = String(repeating: "[x](https://a.b/c) ", count: 20_000)
    let start = Date()
    let text = IslandReplyText.spoken(from: flood)
    expect(Date().timeIntervalSince(start) < 0.2, "respuesta: miles de enlaces no congelan la isla")
    expect(text.split(whereSeparator: \.isWhitespace).count <= IslandReplyText.wordCap, "respuesta: con tope de palabras")
}

/// Security review 16f (note): the shape now grows under a still pointer,
/// so it has to be done moving before the approval guard lets a click in.
@MainActor func testTheShapeSettlesBeforeAllowCanBeClicked() {
    let shape = IslandMotion.secondPhase + IslandMotion.shapeOpen.duration
    let content = IslandMotion.contentStart(from: .pebble, to: .card, reduceMotion: false)
        + IslandMotionBudget.contentIn.duration
    expect(max(shape, content) < ApprovalClickGuard.dwell,
           "aprobación: la forma y el contenido terminan antes de que Permitir acepte un clic")
    // The approval card can also grow an island that is already open, under a still pointer.
    let growsOpen = IslandMotion.resize(growing: true).duration
    expect(max(growsOpen, IslandMotionBudget.card.enter.duration) < ApprovalClickGuard.dwell,
           "aprobación: crecer abierta y la tarjeta terminan antes de que Permitir acepte un clic")
}

/// Code review 16f (HIGH): the click area jumped to the notch the moment
/// closing began, so a click on the still-visible panel fell to the app behind.
@MainActor func testClosingKeepsTheClickAreaUntilTheShapeIsSmall() {
    let big = CGSize(width: 492, height: 300)
    let notch = CGSize(width: 188, height: 38)
    let closing = IslandChrome.hitSizes(current: big, target: notch)
    expectEq(closing.now, big, "cerrar: el área sigue grande mientras se recoge")
    expectEq(closing.later, notch, "cerrar: y se achica cuando la forma ya llegó")
    let opening = IslandChrome.hitSizes(current: notch, target: big)
    expectEq(opening.now, big, "abrir: el área crece ya")
    expect(opening.later == nil, "abrir: nada pendiente")
    expect(IslandChrome.hitShrinkDelay >= IslandMotion.shapeClose.duration, "cerrar: espera a que la forma llegue")
    expect(IslandChrome.hitShrinkDelay >= IslandMotion.shapeShrink.duration, "encoger: espera a que la forma llegue")
}

/// Code review 16f (MEDIUM): one "[" used as punctuation stopped every
/// later link from being read as its label.
@MainActor func testAStrayBracketDoesNotStopTheLinks() {
    expectEq(IslandReplyText.spoken(from: "Nota [1 y luego [Safari](https://a.b) abierto"),
             "Nota [1 y luego Safari abierto", "respuesta: un corchete suelto no frena los enlaces")
}

/// Re-review 16f (MEDIUM): hiding while a shrink was pending let the late
/// task write a size nobody saw, and the next opening compared against it.
@Test @MainActor func hidingCancelsThePendingShrink() async throws {
    let panel = IslandPanel(content: EmptyView(), geometry: IslandGeometry(), onHover: { _ in })
    panel.present(size: .card, contentHeight: 300)
    panel.present(size: .bar, contentHeight: 60)
    panel.present(size: .hidden, contentHeight: 0)
    try await Task.sleep(for: .seconds(IslandChrome.hitShrinkDelay + 0.1))
    expectEq(panel.hitArea, .zero, "ocultar: sin área de clic y sin encogida tardía")
    panel.orderOut(nil)
}

/// Code review 16f-2 (HIGH): cards were keyed by position, so a new reply
/// took the "already shown" state of the card it pushed down.
@Test @MainActor func resultCardsAreKeyedByTheirMessage() async {
    let chat = ChatViewModel(chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
                             store: MemoryConversationStore(), config: Config())
    // K6: only replies with a data card make rows, and the latest reply is
    // the panel's, so a row appears once a newer reply pushes it down.
    // A stats payload the popup can draw (items), with the title a card-only
    // reply shows as its row: K6 gives a row only when "Ver" opens something.
    let card = { (title: String) in
        "```companion:stats\n{\"title\":\"\(title)\",\"items\":[{\"label\":\"Total\",\"value\":\"1\"}]}\n```"
    }
    await chat.appendAssistant(card("Uno"))
    await chat.appendAssistant(card("Dos"))
    let before = IslandView.resultRows(chat.messages, limit: 3).map(\.id)
    await chat.appendAssistant(card("Tres"))
    let after = IslandView.resultRows(chat.messages, limit: 3).map(\.id)
    expectEq(after.count, 2, "tarjetas: las dos de antes de la última")
    expectEq(after.last, before.first, "tarjetas: la vieja conserva su identidad al bajar")
    expect(after.first != before.first, "tarjetas: la nueva es otra, y entra con su animación")
}
