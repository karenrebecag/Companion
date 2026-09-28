import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 20b D3: the island shows prose only. A `companion:` fence is a card for
// the chat window; on the island it read as raw JSON.

@Test @MainActor func islandCardsTests() {
    testProseWithoutCardsDropsOnlyCards()
    testTheIslandNeverShowsAFence()
    testACardOnlyReplyUsesTheCardTitle()
}

private let stats = "texto:\n```companion:stats\n{\"title\":\"Ventas\",\"a\":1}\n```"

@MainActor func testProseWithoutCardsDropsOnlyCards() {
    expectEq(MarkdownSplitter.proseWithoutCards(stats), "texto:", "sin tarjetas: queda la prosa")
    let code = MarkdownSplitter.proseWithoutCards("uso:\n```swift\nlet a = 1\n```")
    expect(code.contains("let a = 1"), "sin tarjetas: el codigo normal se queda")
    expectEq(MarkdownSplitter.proseWithoutCards("hola\n```companion:stats\n{\"ti"), "hola",
             "sin tarjetas: una tarjeta a medio llegar no se asoma")
    expectEq(MarkdownSplitter.proseWithoutCards(""), "", "sin tarjetas: vacio")
}

@MainActor func testTheIslandNeverShowsAFence() {
    expectEq(IslandReplyText.spoken(from: stats), "texto:", "isla: la voz no ve el fence")
    expectEq(IslandReplyText.spoken(from: "hola\n```companion:stats\n{\"ti"), "hola",
             "isla: streaming, sin JSON a medias")
    let card = IslandResult(reply: stats)
    expectEq(card?.title, "texto:", "tarjeta: el titulo es la prosa")
    expect(card?.line == nil, "tarjeta: sin linea de JSON")
}

@MainActor func testACardOnlyReplyUsesTheCardTitle() {
    let only = "```companion:stats\n{\"title\":\"Ventas\",\"a\":1}\n```"
    expectEq(IslandResult(reply: only)?.title, "Ventas", "tarjeta: solo tarjetas, su titulo")
    expect(IslandResult(reply: "```companion:stats\n{\"a\":1}\n```") == nil,
           "tarjeta: sin titulo, nada; nunca una llave")
    expectEq(IslandReplyText.spoken(from: only), "", "isla: solo tarjetas, sin texto")
}
