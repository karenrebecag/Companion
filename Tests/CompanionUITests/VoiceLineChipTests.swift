import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// P3: Incredible's voice line chip (referencia local), its click area and which reply
// it carries.

private let shape = CGRect(x: 600, y: 940, width: 200, height: 40)
private let chip = CGRect(x: 560, y: 860, width: 280, height: 48)

@Test @MainActor func theChipTakesClicksWithoutOpeningTheIsland() {
    expectEq(IslandChrome.pointerTarget(CGPoint(x: 700, y: 880), shape: shape, portal: nil,
                                        answer: nil, voiceLine: chip), .voiceLine,
             "sobre el chip: toma el clic, pero no es hover de la isla")
    expectEq(IslandChrome.pointerTarget(CGPoint(x: 700, y: 960), shape: shape, portal: nil,
                                        answer: nil, voiceLine: chip), .island, "sobre la isla, la isla")
    expectEq(IslandChrome.pointerTarget(CGPoint(x: 100, y: 100), shape: shape, portal: nil,
                                        answer: nil, voiceLine: chip), .outside, "afuera, pasa a la app de atras")
    expectEq(IslandChrome.pointerTarget(CGPoint(x: 700, y: 880), shape: shape, portal: nil,
                                        answer: nil, voiceLine: nil), .outside, "sin chip, nada ahi")
    let overlapping = CGRect(x: 600, y: 930, width: 200, height: 40)
    expectEq(IslandChrome.pointerTarget(CGPoint(x: 700, y: 960), shape: shape, portal: nil,
                                        answer: nil, voiceLine: overlapping), .island, "donde se cruzan, gana la isla")
}

@Test @MainActor func theChipKeepsIncrediblesMeasures() {
    expectEq(VoiceLineChipMetrics.maxWidth, 480, "ancho maximo")
    expectEq(VoiceLineChipMetrics.columnGap, 10, "orbe a texto")
    expectEq(VoiceLineChipMetrics.lineGap, 6, "lineas al expandir")
    expectEq(VoiceLineChipMetrics.orb, IslandChrome.meterSide, "orbe de 32")
    expectEq(VoiceLineChipMetrics.radius, Radius.panel, "radio 28")
    expectEq(VoiceLineChipMetrics.textSize, TypeSize.heroBody, "texto 15")
    expectEq(VoiceLineChipMetrics.lineHeight, 20, "interlinea 20")
    expectEq(VoiceLineChipMetrics.top, 40, "40 bajo el borde de la isla")
    expectEq(VoiceLineChipMetrics.caret, 10, "flecha de 10")
    expectEq(VoiceLineChipMotion.hiddenOffset, -4, "oculto: 4 arriba")
    expectEq(VoiceLineChipMotion.hiddenScale, 0.98, "oculto: 0.98")
    expectEq(VoiceLineChipMotion.hiddenBlur, 4, "oculto: blur 4")
    expectEq(VoiceLineChipMotion.reelBlur, 2.5, "el carrete desenfoca 2.5")
    expectEq(VoiceLineChipMotion.lineOut.duration, 0.26, "la linea vieja sale en 260 ms")
    expectEq(VoiceLineChipMotion.lineIn.duration, 0.42, "la nueva entra en 420 ms")
    expectEq(VoiceLineChipMotion.enter.duration, 0.36, "el chip entra en 360 ms")
}

@MainActor private let previous = ChatMessage(role: .assistant, text: "Lo de antes.")
@MainActor private let current = ChatMessage(role: .assistant, text: "Listo. Ya mande el correo.")

private func quiet(_ phase: SessionPhase = .speaking) -> (IslandState, SessionProjection) {
    var p = SessionProjection()
    p.kind = .processing(phase)
    p.voice = .live
    p.presence = .passive
    return (IslandState.from(p, pebbleHidden: false), p)
}

@Test @MainActor func theChipCarriesOnlyThisTurnsReply() {
    let (state, p) = quiet()
    expect(IslandView.voiceLine(state: state, projection: p, latest: previous, replyOfTurn: nil) == nil,
           "la respuesta de antes del turno no se repite")
    let line = IslandView.voiceLine(state: state, projection: p, latest: current, replyOfTurn: current.id)
    expectEq(line?.turn, current.id, "la de este turno si")
    expectEq(line?.lines.count, 2, "en sus oraciones")
    expect(line?.settled == false, "mientras habla no esta asentada")
}

@Test @MainActor func theChipSettlesWhenTheTurnEnds() {
    let (completed, p) = quiet(.completed)
    expect(IslandView.voiceLine(state: completed, projection: p, latest: current, replyOfTurn: current.id)?.settled == true,
           "completado: asentada")
    var idle = SessionProjection()
    idle.presence = .passive
    let rested = IslandState.from(idle, pebbleHidden: false)
    expect(IslandView.voiceLine(state: rested, projection: idle, latest: current, replyOfTurn: current.id)?.settled == true,
           "de vuelta al reposo, pasivo: asentada")
}

@Test @MainActor func anActiveIslandHasNoChip() {
    var p = SessionProjection()
    p.kind = .processing(.speaking)
    p.voice = .live
    let state = IslandState.from(p, pebbleHidden: false)
    expect(IslandView.voiceLine(state: state, projection: p, latest: current, replyOfTurn: current.id) == nil,
           "activo: la isla lleva el turno")
}

@Test @MainActor func theChipNamesTheResultCard() {
    let (state, p) = quiet()
    let card = ChatMessage(role: .assistant,
                           text: "Las ventas del mes:\n\n```companion:stats\n{\"title\":\"Ventas\",\"a\":1}\n```")
    let title = IslandView.islandResult(for: card)?.title
    expect(title != nil, "la respuesta trae tarjeta")
    expectEq(IslandView.voiceLine(state: state, projection: p, latest: card, replyOfTurn: card.id)?.label, title,
             "con tarjeta, su titulo")
}

// The reply a quiet turn carries is the one that arrived during it: a new quiet turn
// forgets the last one, so an old answer never rides again.
@Test @MainActor func theReplyOfTheTurnIsTheOneHeardDuringIt() {
    let old = UUID(), new = UUID()
    expectEq(IslandView.replyOfTurn(kept: old, wasQuiet: false, quiet: true, oldLatest: old, latest: old), nil,
             "turno callado nuevo: la de antes no cuenta")
    expectEq(IslandView.replyOfTurn(kept: nil, wasQuiet: true, quiet: true, oldLatest: old, latest: new), new,
             "llega una respuesta en el turno: esa")
    expectEq(IslandView.replyOfTurn(kept: nil, wasQuiet: false, quiet: true, oldLatest: old, latest: new), new,
             "llega junto con el turno: esa")
    expectEq(IslandView.replyOfTurn(kept: new, wasQuiet: true, quiet: false, oldLatest: new, latest: new), new,
             "el turno termina: se queda para asentarse")
    expectEq(IslandView.replyOfTurn(kept: nil, wasQuiet: false, quiet: false, oldLatest: old, latest: new), nil,
             "una respuesta con la isla activa no es del chip")
}

// A turn that stays quiet keeps the island at least a pebble, so its chip has a place.
@Test @MainActor func theChipKeepsThePanelUp() {
    var hidden = IslandState.from(SessionProjection(), pebbleHidden: true)
    expectEq(hidden.size, .hidden, "partia oculta")
    hidden = IslandView.holdingChip(hidden, chipMounted: true)
    expectEq(hidden.size, .pebble, "con el chip montado, al menos la pildora")
    let untouched = IslandView.holdingChip(IslandState.from(SessionProjection(), pebbleHidden: true), chipMounted: false)
    expectEq(untouched.size, .hidden, "sin chip, como estaba")
}

// QA review (P3): the turn's last reply can land in the same update the turn ends.
@Test @MainActor func aReplyLandingAsTheTurnEndsIsTheTurns() {
    let old = UUID(), new = UUID()
    expectEq(IslandView.replyOfTurn(kept: nil, wasQuiet: true, quiet: false, oldLatest: old, latest: new), new,
             "llega al terminar: es del turno")
}

@MainActor private func feed(_ quiet: Bool, _ message: ChatMessage?, settled: Bool = false) -> VoiceLineFeed {
    VoiceLineFeed(quiet: quiet, latest: message?.id, candidate: message.flatMap {
        VoiceLine.make(turn: $0.id, text: $0.text, spoken: 0, settled: settled, cards: [], quiet: true)
    })
}

// Code review (P3, HIGH): the reply of the last quiet turn never flashes when a new
// one starts; eligibility is decided in the same step as the edge.
@Test @MainActor func aNewQuietTurnNeverFlashesTheLastReply() {
    let step = IslandView.followVoiceLine(kept: previous.id, old: feed(false, previous, settled: true),
                                          new: feed(true, previous))
    expectEq(step.reply, nil, "la de antes se olvida")
    expect(step.line == nil, "y no se muestra ni un instante")
    let next = IslandView.followVoiceLine(kept: step.reply, old: feed(true, previous), new: feed(true, current))
    expectEq(next.line?.turn, current.id, "la nueva si")
}

@Test @MainActor func engagingTakesTheChipAway() {
    let shown = IslandView.followVoiceLine(kept: nil, old: feed(true, previous), new: feed(true, current))
    expectEq(shown.line?.turn, current.id, "en pasivo se ve")
    let engaged = VoiceLineFeed(quiet: false, latest: current.id, candidate: nil)
    expect(IslandView.followVoiceLine(kept: shown.reply, old: feed(true, current), new: engaged).line == nil,
           "activo: el chip se va y la isla lo lleva")
}

@Test @MainActor func holdingTheChipLeavesAnOpenIslandAlone() {
    let (open, _) = quiet()
    var active = SessionProjection()
    active.kind = .processing(.speaking)
    active.voice = .live
    let card = IslandState.from(active, pebbleHidden: true)
    expectEq(IslandView.holdingChip(card, chipMounted: true).size, card.size, "otro tamano: intacto")
    expectEq(IslandView.holdingChip(open, chipMounted: true).size, open.size, "la pildora sigue pildora")
}

// Code review (P3): the click area follows visibility, not only frame changes.
@Test @MainActor func theClickAreaFollowsVisibility() {
    let frame = CGRect(x: 100, y: 40, width: 300, height: 48)
    expectEq(IslandView.chipClickArea(frame, visible: true), frame, "visible: su marco")
    expect(IslandView.chipClickArea(frame, visible: false) == nil, "apagado: nada")
    let past = CGRect(x: 600, y: 40, width: 300, height: 48)
    expectEq(IslandView.chipClickArea(past, visible: true)?.maxX, IslandChrome.canvasWidth, "nunca fuera del lienzo")
}

// Code review (P3): before the voice starts, the first sentence; once over, the last.
@Test @MainActor func theChipStartsOnTheFirstSentence() {
    expectEq(VoiceLineChip.said(words: 9, settled: false, speaking: false, elapsed: 5), 0, "antes de hablar: nada dicho")
    expectEq(VoiceLineChip.said(words: 9, settled: true, speaking: false, elapsed: 0), 9, "terminado: todo dicho")
    expectEq(VoiceLineChip.said(words: 9, settled: false, speaking: true, elapsed: 1), 4, "hablando: al ritmo de la voz")
}

// QA review (P3): the chip reporting a reply and the island reporting it again count once,
// and clicking the chip counts as attending it.
@Test @MainActor func theChipAndTheIslandReportAReplyOnce() {
    var attention = IslandResultAttention()
    let id = UUID()
    expectEq(attention.replyShown(id), [.shown(.result)], "el chip la muestra")
    expectEq(attention.replyShown(id), [], "la isla otra vez: nada")
    attention.attended()
    expectEq(attention.replyShown(UUID()), [.shown(.result)], "atendida por el clic: no ignorada")
}
