import CompanionCore
import Foundation
import Testing

// La lógica del microscopio de voz, pura. La pregunta que responde: cuando el
// modelo se traga parte de una instrucción ("en el escritorio"), ¿el audio
// llegó a OpenAI o se cortó antes? El veredicto se juzga contra lo que OpenAI
// de verdad recibió (frames reenviados vs filtrados).

@Test func voiceAuditReportTests() {
    testTallyCounts()
    testGateReasonMapsEachBranch()
    testTurnLineCarriesBothSidesAndCounts()
    testVerdictFullUtterance()
    testVerdictClippedBeforeOpenAI()
    testVerdictOpenAIDroppedIt()
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

func testGateReasonMapsEachBranch() {
    expectEq(RealtimeGate.reason(muted: false, emptyPCM: true, micEnabled: true,
                                 state: .listening, echoGuarded: false, aec: true),
             .empty, "gate: un frame vacío")
    expectEq(RealtimeGate.reason(muted: true, emptyPCM: false, micEnabled: true,
                                 state: .listening, echoGuarded: false, aec: true),
             .muted, "gate: mic silenciado")
    expectEq(RealtimeGate.reason(muted: false, emptyPCM: false, micEnabled: true,
                                 state: .listening, echoGuarded: true, aec: true),
             .echoGuard, "gate: escuchando, protegido del eco propio")
    expectEq(RealtimeGate.reason(muted: false, emptyPCM: false, micEnabled: true,
                                 state: .speaking, echoGuarded: false, aec: false),
             .noAEC, "gate: el agente habla y no hay cancelación de eco")
    expectEq(RealtimeGate.reason(muted: false, emptyPCM: false, micEnabled: true,
                                 state: .speaking, echoGuarded: false, aec: true),
             .backchannel, "gate: hablando con AEC — el gate lo juzgó backchannel")
}

func testTurnLineCarriesBothSidesAndCounts() {
    var tally = FrameTally()
    for _ in 0..<80 { tally.add(forwarded: true, reason: nil) }
    for _ in 0..<5 { tally.add(forwarded: false, reason: .muted) }
    let line = VoiceAuditReport.turnLine(
        native: "crea prueba en el escritorio",
        openAI: "crea prueba", tally: tally, goal: "crear archivo")
    expect(line.contains("native=«crea prueba en el escritorio»"),
           "línea: la verdad nativa entera")
    expect(line.contains("openai=«crea prueba»"), "línea: lo que OpenAI transcribió")
    expect(line.contains("fwd=80"), "línea: frames reenviados")
    expect(line.contains("gated=5") && line.contains("muted 5"),
           "línea: filtrados, con razón")
    expect(line.contains("goal=«crear archivo»"), "línea: el goal que armó el modelo")
}

func testVerdictFullUtterance() {
    var tally = FrameTally()
    for _ in 0..<100 { tally.add(forwarded: true, reason: nil) }
    let v = VoiceAuditReport.verdict(
        native: "crea prueba en el escritorio",
        openAI: "crea prueba en el escritorio", tally: tally)
    expect(v.contains("full utterance"),
           "veredicto: OpenAI recibió todo — nada que investigar")
}

func testVerdictClippedBeforeOpenAI() {
    var tally = FrameTally()
    for _ in 0..<100 { tally.add(forwarded: true, reason: nil) }
    for _ in 0..<40 { tally.add(forwarded: false, reason: .noAEC) }
    let v = VoiceAuditReport.verdict(
        native: "crea prueba en el escritorio",
        openAI: "crea prueba", tally: tally)
    expect(v.contains("CLIPPED before OpenAI"),
           "veredicto: mucho audio filtrado — se cortó antes de OpenAI")
    expect(v.contains("escritorio"), "veredicto: nombra lo que faltó")
}

func testVerdictOpenAIDroppedIt() {
    var tally = FrameTally()
    for _ in 0..<100 { tally.add(forwarded: true, reason: nil) }
    let v = VoiceAuditReport.verdict(
        native: "crea prueba en el escritorio",
        openAI: "crea prueba", tally: tally)
    expect(v.contains("OpenAI GOT the audio"),
           "veredicto: OpenAI recibió el audio pero su transcript/modelo lo soltó")
    expect(v.contains("escritorio"), "veredicto: nombra la palabra perdida")
}
