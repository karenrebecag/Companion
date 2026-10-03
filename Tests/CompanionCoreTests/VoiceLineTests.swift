import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// P3: Incredible's voice line (referencia local): in passive, what the voice says rides
// in a chip under the island, one sentence at a time, instead of opening the island.

private let reply = "Listo. Mande el correo a Ana; tambien \u{201C}revise el PDF.\u{201D} Algo mas?"

@Test func theWordsAreCutIntoSentences() {
    let lines = VoiceLine.lines(reply.split(separator: " ").map(String.init))
    expectEq(lines.map { $0.joined(separator: " ") },
             ["Listo.", "Mande el correo a Ana; tambien \u{201C}revise el PDF.\u{201D}", "Algo mas?"],
             "una oracion termina en . ! ? o \u{2026}, aunque la cierre una comilla")
    expectEq(VoiceLine.lines(["sin", "punto"]).count, 1, "lo que queda sin cerrar es la ultima")
    expectEq(VoiceLine.lines(["Espera\u{2026}", "ya"]).count, 2, "los puntos suspensivos cortan")
    expectEq(VoiceLine.lines(["(si!)", "bien"]).count, 2, "un parentesis de cierre tambien")
    expectEq(VoiceLine.lines([]).count, 0, "sin palabras no hay lineas")
}

@Test func theCurrentLineIsTheFirstWithAWordStillUnsaid() {
    let lines = VoiceLine.lines(reply.split(separator: " ").map(String.init))
    expectEq(VoiceLine.current(lines, spoken: 0), 0, "nada dicho: la primera")
    expectEq(VoiceLine.current(lines, spoken: 1), 1, "dicha la primera entera: la segunda")
    expectEq(VoiceLine.current(lines, spoken: 3), 1, "a medias: sigue en la segunda")
    expectEq(VoiceLine.current(lines, spoken: 100), 2, "todo dicho: la ultima")
    expectEq(VoiceLine.current([], spoken: 0), 0, "sin lineas, cero")
}

@Test func onlyAQuietTurnWithWordsHasALine() {
    let id = UUID()
    expect(VoiceLine.make(turn: id, text: reply, spoken: 2, settled: false, cards: [], quiet: false) == nil,
           "si la isla lleva el turno, no hay chip")
    expect(VoiceLine.make(turn: id, text: "   ", spoken: 0, settled: false, cards: [], quiet: true) == nil,
           "sin palabras, no hay chip")
    let line = VoiceLine.make(turn: id, text: reply, spoken: 3, settled: false, cards: [], quiet: true)
    expectEq(line?.current, 1, "la linea que se esta diciendo")
    expectEq(line?.lines.count, 3, "con todas sus lineas para el hover")
    expectEq(line?.turn, id, "del turno que la dijo")
}

// The chip names what the turn produced; without cards, what it said.
@Test func theLabelNamesTheCardsOrElseTheWords() {
    let words = VoiceLine.make(turn: UUID(), text: "Hola. Ya.", spoken: 0, settled: true, cards: [], quiet: true)
    expectEq(words?.label, "Hola. Ya.", "sin tarjetas, las palabras")
    let cards = VoiceLine.make(turn: UUID(), text: "Hola.", spoken: 0, settled: true,
                               cards: ["Factura marzo", "Correo a Ana"], quiet: true)
    expectEq(cards?.label, "Factura marzo, Correo a Ana", "con tarjetas, sus titulos")
}

// A hostile or runaway reply cannot grow the chip without bound.
@Test func aRunawayReplyKeepsOnlyItsLastWords() {
    let long = (0..<5_000).map { "w\($0)." }.joined(separator: " ")
    let line = VoiceLine.make(turn: UUID(), text: long, spoken: 0, settled: true, cards: [], quiet: true)
    expectEq(line?.words.count, VoiceLine.wordLimit, "como Incredible, las ultimas \(VoiceLine.wordLimit)")
    expectEq(line?.words.last, "w4999.", "las ultimas, no las primeras")
}

@Test func theChipKeepsIncrediblesTimes() {
    expectEq(VoiceLine.lingerAfterSettle, 6, "6 s despues de terminar")
    expectEq(VoiceLine.leave, 0.26, "se va en 260 ms")
}

// Security review (P3): a word with no spaces cannot stretch the chip without bound.
@Test func aRunawayWordIsCut() {
    let long = String(repeating: "a", count: 5_000)
    let line = VoiceLine.make(turn: UUID(), text: "Hola " + long, spoken: 0, settled: true, cards: [], quiet: true)
    expectEq(line?.words.last?.count, VoiceLine.wordCharLimit, "cortada al tope")
    expectEq(line?.words.first, "Hola", "las normales intactas")
}
