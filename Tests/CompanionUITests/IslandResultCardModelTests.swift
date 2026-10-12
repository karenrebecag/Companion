import CompanionCore
import CompanionTestKit
import CompanionUIPro
@testable import CompanionUI
import Foundation
import Testing

// The result card's mapping, apart from the view: what becomes a step, a
// chip, a title and a clickable address.

private func source(_ title: String, _ url: String) -> MarkdownSplitter.SourceLink {
    MarkdownSplitter.SourceLink(title: title, url: url)
}

@Test @MainActor func testSourcesBecomeOpenableChipsAndOnlyWebAddressesOpen() {
    let links = IslandResultCardModel.links(apps: ["Notes"], sources: [
        source("Webflow", "https://webflow.com/docs"),
        source("Local", "file:///etc/passwd"),
        source("Script", "javascript:alert(1)"),
        source("Webflow again", "https://webflow.com/docs"),
        source("", "http://example.com/a"),
    ])
    expectEq(links.chips.map(\.label), ["Webflow", "example.com"],
             "enlaces: solo http(s), sin repetir, y el titulo vacio cae al host")
    expectEq(links.chips.map(\.kind), [.source, .source], "enlaces: son fuentes")
    expectEq(Set(links.urls.keys), Set(links.chips.map(\.id)), "enlaces: cada chip abierto tiene direccion")
}

@Test @MainActor func testAppsAreLabelsWithNoAddressSoNoChipIsADeadButton() {
    let links = IslandResultCardModel.links(apps: ["Notes", "Notes", "  ", "Safari"], sources: [])
    expectEq(links.chips.map(\.label), ["Notes", "Safari"], "apps: sin repetir ni vacias")
    expectEq(links.chips.map(\.kind), [.app, .app], "apps: tipo app")
    expect(links.urls.isEmpty, "apps: sin direccion, la tarjeta no pasa onOpen")
}

@Test @MainActor func testSourcesWithNoUsableAddressFallBackToTheApps() {
    let links = IslandResultCardModel.links(
        apps: ["Notes"], sources: [source("x", "ftp://host/file")])
    expectEq(links.chips.map(\.label), ["Notes"], "apps: una fuente que no abre no desplaza a las apps")
    expect(links.urls.isEmpty, "apps: nada que abrir")
}

@Test @MainActor func testTheTitleIsTheQuestionOnOneLineCutWithItsMarkOrTheFallback() {
    expectEq(IslandResultCardModel.title(question: "  abre\nNotas  y  escribe ", fallback: "Resultado"),
             "abre Notas y escribe", "titulo: una linea, espacios normalizados")
    expectEq(IslandResultCardModel.title(question: nil, fallback: "Resultado"), "Resultado", "titulo: sin pregunta")
    expectEq(IslandResultCardModel.title(question: " \n ", fallback: "Resultado"), "Resultado", "titulo: pregunta en blanco")
    let long = IslandResultCardModel.title(question: String(repeating: "a", count: 200), fallback: "x")
    expectEq(long.count, IslandResultCardModel.titleMax, "titulo: acotado")
    expect(long.hasSuffix("…"), "titulo: el corte se ve")
}

@Test @MainActor func testTheSourcesListLeavesTheProseAndTravelsAsChips() {
    let reply = "Webflow publica en el CDN.\n\n## Fuentes\n\n- [Docs](https://webflow.com/docs)\n- [Blog](https://webflow.com/blog)"
    let parts = IslandResultCardModel.proseAndSources(of: reply)
    expectEq(parts.sources.map(\.url), ["https://webflow.com/docs", "https://webflow.com/blog"], "fuentes: las dos")
    expect(parts.prose.contains("CDN") && !parts.prose.contains("webflow.com"), "fuentes: la prosa no las repite — \(parts.prose)")
    expectEq(IslandResultCardModel.proseAndSources(of: "Solo texto.").prose, "Solo texto.", "fuentes: sin lista, sin cambios")
}

@Test @MainActor func testOnlyAFinishedPlainReplyTakesTheCardAndTheCardIsTheCardWidth() {
    var done = IslandState(size: .card, line: .completed)
    expect(IslandView.showsCompletedCard(done), "tarjeta: la respuesta terminada la usa")
    done.approval = ApprovalRequest(requestId: "r", toolName: "Bash", summary: "x", inputJSON: "{}")
    expect(!IslandView.showsCompletedCard(done), "tarjeta: la hoja de aprobacion conserva su fila")
    expectEq(IslandState.from(
        {
            var p = SessionProjection()
            p.kind = .processing(.completed)
            return p
        }(), pebbleHidden: false).size, .card, "tarjeta: terminada es del ancho de tarjeta")
}

@Test @MainActor func testTheThreadReplySplitsItsSourcesLikeTheCardDoes() {
    let message = ChatMessage(role: .assistant, text:
        "Webflow publica en el CDN.\n\nSources:\n\n- [Docs](https://webflow.com/docs)")
    let words = IslandView.threadWords(message)
    expectEq(words.sources.map(\.url), ["https://webflow.com/docs"], "hilo: la fuente sale como chip")
    expect(words.text.contains("CDN") && !words.text.contains("Sources") && !words.text.contains("webflow.com"),
           "hilo: la prosa no repite la lista — \(words.text)")
}
