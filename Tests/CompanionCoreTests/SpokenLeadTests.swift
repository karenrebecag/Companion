import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// La voz dice la frase de entrada y calla donde empieza la tabla o la lista:
// eso es del documento, no de la voz.

private func spoken(_ deltas: [String]) -> (said: String, open: Bool) {
    var lead = SpokenLead()
    let said = deltas.map { lead.admit($0) }.joined()
    return (said, lead.documentOpen)
}

@Test func theVoiceStopsWhereTheTableStartsEvenSplitAcrossDeltas() {
    let result = spoken(["Aquí tienes la comparación.", "\n", "\n|", " Modelo | Batería |", "\n| iPhone |"])
    expectEq(result.said, "Aquí tienes la comparación.\n", "voz: solo la frase de entrada")
    expect(result.open, "voz: la tabla abre el documento")
}

@Test func aNumberedListOpensOnlyWhenABlankFollowsTheMark() {
    let list = spoken(["Son cinco pasos.\n1", ".", " Hierve el agua.\n2. Vierte."])
    expectEq(list.said, "Son cinco pasos.\n", "voz: '1. ' es una lista")
    let number = spoken(["Pi vale\n3.14 y poco más."])
    expectEq(number.said, "Pi vale\n3.14 y poco más.", "voz: '3.14' es un numero, se dice")
    expect(!number.open, "voz: sin documento")
}

@Test func aPlainReplyIsSaidWhole() {
    let result = spoken(["En Tokio son las 6:40 ", "de la mañana.\n\n50 personas lo ven."])
    expectEq(result.said, "En Tokio son las 6:40 de la mañana.\n\n50 personas lo ven.", "voz: prosa entera")
    expect(!result.open, "voz: sin documento")
}

// En vivo 2026-10-12: el stream cortado en frases recortadas pegaba las filas
// ("| Modelo | Pantalla ||---|---||"); ni el documento ni la voz veian tabla.
@Test func aStreamedTableKeepsItsLineBreaks() {
    var buffer = "Aquí tienes la comparación de los tres:\n\n| Modelo | Pantalla |\n|---|---|\n| iPhone 17 | 6.3 pulgadas |\n"
    var joined = ""
    while let cut = SentenceSplitter.takeSpan(buffer) {
        joined += cut.span
        buffer = cut.rest
    }
    joined += buffer
    expect(joined.contains("| Modelo | Pantalla |\n|---|---|\n"), "stream: cada fila en su linea")
    expect(ReplyRichness.isRich(joined), "stream: la tabla cuenta como documento")
}

@Test func aFencedMarkdownTableIsTheDocumentAndTheVoiceStopsAtTheFence() {
    let reply = "Aquí tienes la comparación:```markdown\n| Modelo | Pantalla |\n|---|---|\n| iPhone 17 | 6.3 |\n```"
    var lead = SpokenLead()
    expectEq(lead.admit(reply), "Aquí tienes la comparación:", "voz: calla en la valla, no dice 'markdown'")
    let unfenced = SpeechMarkdown.unfenced(reply)
    expect(!unfenced.contains("```"), "documento: sin la valla de codigo")
    expect(ReplyRichness.isRich(unfenced), "documento: la tabla cuenta")
}
