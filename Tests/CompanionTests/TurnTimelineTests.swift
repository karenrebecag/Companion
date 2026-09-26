import CompanionCore
import Foundation
import Testing

// Wave 12c. La línea de tiempos de un hold: pura, en milisegundos enteros,
// con huecos honestos.

@Test @MainActor func turnTimelineTests() {
    testTimelineLine()
    testToolCallAndDoneSegments()
    testTurnWithoutToolMarks()
    testToolCallSeenFirstMarkWins()
    testToolDoneWithoutToolCallSeen()
    testDecisionMarkAppearsInTheLine()
    testDecisionFirstMarkWins()
    testReleaseToAudioSegment()
    testFirstTokenAppearsInTheLine()
    testFirstTokenFirstMarkWins()
    testEarFinalAndMouthSegments()
    testTheMouthSegmentsOfTheFirstSentence()
    testCommitToContextAppearsInTheLine()
}

/// Wave 15g-5 (spec §3b): commit→firstToken mixed the context fan-out
/// (vision wait, AX, clipboard) with the model; `contextReady` is marked
/// right before the chat request so the two read apart.
@MainActor func testCommitToContextAppearsInTheLine() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.contextReady, at: 10.62)
    t.mark(.contextReady, at: 11)
    t.mark(.firstToken, at: 11.1)
    let line = t.line() ?? ""
    expect(line.contains("· commit→context 120 · commit→firstToken 600"),
           "15g-5: commit→context se ve, la primera marca gana, y va antes de commit→firstToken (\(line))")
}

/// 5. Sin `pressed` no hay línea; la primera marca gana; los huecos son «—».
@MainActor func testTimelineLine() {
    var t = TurnTimeline()
    expect(t.line() == nil, "tiempos: sin pulsar no hay línea")
    t.mark(.pressed, at: 10)
    t.mark(.micReady, at: 10.082)
    t.mark(.earReady, at: 10.61)
    t.mark(.sessionReady, at: 10.94)
    t.mark(.sessionReady, at: 12)
    t.mark(.firstPartial, at: 11.42)
    t.mark(.released, at: 13)
    t.mark(.committed, at: 13.26)
    t.mark(.firstAudio, at: 14.14)
    expectEq(t.line(),
             "voice timeline: press→mic 82 · press→ear 610 · press→ready 940 · press→partial 1420 · release→commit 260 · release→earFinal — · release→audio 1140 · firstToken→audio — · firstCut→ttsRequest — · ttsRequest→firstByte — · firstByte→audible — · commit→audio 880 · commit→context — · commit→firstToken — · commit→decision — · commit→tool — · tool→done —",
             "tiempos: la línea entera")
    var gaps = TurnTimeline()
    gaps.mark(.pressed, at: 1)
    gaps.mark(.released, at: 1.5)
    expectEq(gaps.line(),
             "voice timeline: press→mic — · press→ear — · press→ready — · press→partial — · release→commit — · release→earFinal — · release→audio — · firstToken→audio — · firstCut→ttsRequest — · ttsRequest→firstByte — · firstByte→audible — · commit→audio — · commit→context — · commit→firstToken — · commit→decision — · commit→tool — · tool→done —",
             "tiempos: los huecos se ven")
    expect(TurnTimeline() == TurnTimeline(), "tiempos: igualable")
}

/// Prueba 1: después de `.pressed`, `.released`, `.committed` a las 13.26, marcar
/// `.toolCallSeen` a 14.1 y `.toolDone` a 14.35 → `line()` termina con `· commit→tool 840 · tool→done 250`.
@MainActor func testToolCallAndDoneSegments() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 13)
    t.mark(.released, at: 13.15)
    t.mark(.committed, at: 13.26)
    t.mark(.toolCallSeen, at: 14.1)
    t.mark(.toolDone, at: 14.35)
    let line = t.line()
    expect(line?.hasSuffix("· commit→tool 840 · tool→done 250") ?? false,
           "herramientas: commit→tool y tool→done milisegundos correctos")
}

/// Prueba 2: un turno sin marcas de herramienta muestra los dos huecos nuevos como «—»
/// y todo lo demás sin cambios.
@MainActor func testTurnWithoutToolMarks() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.released, at: 10.5)
    t.mark(.committed, at: 10.7)
    let line = t.line()
    expect(line?.hasSuffix("· commit→tool — · tool→done —") ?? false,
           "herramientas: sin marcas muestra guiones")
}

/// Prueba 3: dos marcas `.toolCallSeen` → la primera gana (el hueco refleja la primera).
@MainActor func testToolCallSeenFirstMarkWins() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.toolCallSeen, at: 11)
    t.mark(.toolCallSeen, at: 12)
    let line = t.line()
    expect(line?.contains("commit→tool 500") ?? false,
           "herramientas: primera toolCallSeen gana")
}

/// Prueba 4: `.toolDone` sin `.toolCallSeen` → `tool→done —`, sin crash.
@MainActor func testToolDoneWithoutToolCallSeen() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.toolDone, at: 11)
    let line = t.line()
    expect(line?.contains("· tool→done —") ?? false,
           "herramientas: toolDone sin toolCallSeen muestra guion")
}

/// DM1c-1: `commit→decision` aparece entre `commit→audio` y `commit→tool`,
/// con el mismo estilo de hueco que las demás marcas.
@MainActor func testDecisionMarkAppearsInTheLine() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.decision, at: 10.9)
    let line = t.line()
    expect(line?.contains("· commit→decision 400 · commit→tool") ?? false,
           "decision: commit→decision se ve y va antes de commit→tool")
}

/// La primera marca de `.decision` gana, igual que `.toolCallSeen`.
@MainActor func testDecisionFirstMarkWins() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.decision, at: 11)
    t.mark(.decision, at: 12)
    let line = t.line()
    expect(line?.contains("commit→decision 500") ?? false,
           "decision: la primera marca gana")
}

/// 15b-0: `release→audio` is a direct released→firstAudio gap, independent
/// of `committed` — the number Done §6.3 measures (soltar → primer audio).
@MainActor func testReleaseToAudioSegment() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.released, at: 10.5)
    t.mark(.firstAudio, at: 11.2)
    let line = t.line()
    expect(line?.contains("release→audio 700") ?? false,
           "release→audio: released hasta firstAudio, en milisegundos")
}

/// Wave 15c-0: `commit→firstToken` measures the brain, apart from the mouth
/// (`commit→audio`) — the number that told us the escalera, not the router,
/// was the slow half of the tube (wave-15c §1).
@MainActor func testFirstTokenAppearsInTheLine() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.firstToken, at: 10.9)
    let line = t.line()
    expect(line?.contains("· commit→firstToken 400 · commit→decision") ?? false,
           "firstToken: commit→firstToken se ve y va antes de commit→decision")
}

/// La primera marca de `.firstToken` gana, igual que `.decision`.
@MainActor func testFirstTokenFirstMarkWins() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.firstToken, at: 11)
    t.mark(.firstToken, at: 12)
    let line = t.line()
    expect(line?.contains("commit→firstToken 500") ?? false,
           "firstToken: la primera marca gana")
}

/// Wave 15d-0 (TDD §3): `commit→audio` mixed ear, brain and mouth. The
/// ear's final and the brain's first token each get their own segment so
/// a slow ear, a slow model and a slow voice read apart.
@MainActor func testEarFinalAndMouthSegments() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.released, at: 12)
    t.mark(.committed, at: 12.3)
    t.mark(.earFinal, at: 12.75)
    t.mark(.earFinal, at: 13)
    t.mark(.firstToken, at: 13.2)
    t.mark(.firstAudio, at: 13.65)
    let line = t.line() ?? ""
    expect(line.contains("release→earFinal 750"), "15d-0: soltar hasta el texto final del oído")
    expect(line.contains("firstToken→audio 450"), "15d-0: primer token hasta el primer audio")
    expect(line.contains("press→mic"), "15d-0: press→mic sigue en la línea")
}

/// Wave 15f-5 (spec §4 row 8): inside the mouth, the first sentence's cut,
/// request, first byte and audible instant each get a segment; the first
/// mark wins and `firstToken→audio` stays.
@MainActor func testTheMouthSegmentsOfTheFirstSentence() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.released, at: 12)
    t.mark(.firstToken, at: 12.9)
    t.mark(.firstCut, at: 13)
    t.mark(.firstCut, at: 13.5)
    t.mark(.ttsRequest, at: 13.02)
    t.mark(.ttsRequest, at: 14)
    t.mark(.firstByte, at: 13.62)
    t.mark(.firstByte, at: 14.5)
    t.mark(.firstAudio, at: 13.65)
    let line = t.line() ?? ""
    expect(line.contains("firstToken→audio 750 · firstCut→ttsRequest 20 · ttsRequest→firstByte 600 · firstByte→audible 30"),
           "15f-5: los tres tramos de la boca siguen a firstToken→audio (\(line))")
}
