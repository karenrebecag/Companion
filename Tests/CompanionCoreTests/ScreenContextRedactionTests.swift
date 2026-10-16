import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

// Valores sintéticos. La voz y el handoff leen la pantalla por otro camino que
// las tools: el resumen, los fragmentos y lo señalado.
private let card = "4111 1111 1111 1111"

@Test func screenBriefAndSnippetsComeOutMasked() {
    let brief = ScreenBrief(summary: "nota con \(card)", snippets: [ScreenSnippet(app: "Notes", text: "pago \(card)")])
    expect(!(brief.summary ?? "").contains("4111"), "resumen")
    expect(!brief.snippets[0].text.contains("4111"), "fragmento")
    let parsed = ScreenBriefParser.parse("SUMMARY: tarjeta \(card)\nSNIPPETS:\n[Notes] \"cvv \(card)\"")
    expect(!(parsed.summary ?? "").contains("4111") && !parsed.snippets[0].text.contains("4111"), "parser")
    let harvested = ScreenTextSnippets.snippets(from: [String(repeating: "x", count: 70) + " " + card], app: "Notes")
    expect(!harvested[0].text.contains("4111"), "AX")
}

@Test func voiceContextBlockAndHandoffSourcesAreMasked() {
    let ctx = TurnContext(
        source: .voice, screenSummary: "tarjeta \(card)",
        pointed: [PointedElement(app: "Notes", role: "AXStaticText", text: card, at: 1)],
        focusedWindow: "Notas \(card)")
    expect(!ContextBlock.render(ctx, language: .es).contains("4111"), "bloque de contexto")
    expect(!HandoffProposal.echoSources(ctx).joined().contains("4111"), "handoff")
}
