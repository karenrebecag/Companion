import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// La lógica del microscopio de voz, pura. La pregunta que responde: cuando el
// modelo se traga parte de una instrucción, ¿el audio llegó a OpenAI o se
// cortó antes? La línea cuenta frames reenviados vs filtrados, nunca palabras.

@Test func voiceAuditReportTests() {
    testTallyCounts()
    testTurnLineCarriesBothSidesAndCounts()
}

func testTallyCounts() {
    var tally = FrameTally()
    tally.add(forwarded: true, reason: nil)
    tally.add(forwarded: true, reason: nil)
    tally.add(forwarded: false, reason: .muted)
    tally.add(forwarded: false, reason: .noAEC)
    tally.add(forwarded: false, reason: .muted)
    expectEq(tally.forwarded, 2, "tally: cuenta lo reenviado")
    expectEq(tally.gatedTotal, 3, "tally: cuenta lo filtrado")
    expectEq(tally.gated[.muted], 2, "tally: agrupa por razón")
    expectEq(tally.total, 5, "tally: total = reenviado + filtrado")
}

func testTurnLineCarriesBothSidesAndCounts() {
    var tally = FrameTally()
    for _ in 0..<80 { tally.add(forwarded: true, reason: nil) }
    for _ in 0..<5 { tally.add(forwarded: false, reason: .muted) }
    let line = VoiceAuditReport.turnLine(
        native: "crea prueba en el escritorio",
        openAI: "crea prueba", tally: tally, goal: "crear archivo")
    // Code review 2026-09-24: counts, never the words — the main log is
    // shared in bug reports.
    expect(line.contains("native=28 chars"), "línea: cuánto oyó el oído nativo")
    expect(line.contains("openai=11 chars"), "línea: cuánto transcribió OpenAI")
    expect(!line.contains("escritorio"), "línea: nunca lo dicho")
    expect(line.contains("fwd=80"), "línea: frames reenviados")
    expect(line.contains("gated=5") && line.contains("muted 5"),
           "línea: filtrados, con razón")
    expect(line.contains("goal=13 chars"), "línea: el goal, contado")
    expect(!line.contains("crear archivo"), "línea: el goal nunca en claro")
}
