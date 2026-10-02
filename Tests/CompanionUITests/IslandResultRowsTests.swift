import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// K6 (brief isla-ciclo-y-legibilidad, signed by Karen): every past reply
// became a "Ver →" card, so plain answers stacked up as cards with nothing
// behind them. Only a reply that brings a result does: a data card, from the
// card channel or a `companion:` fence. Prose alone does not.

private let salesFence = "```companion:stats\n{\"title\":\"Ventas\",\"a\":1}\n```"

@MainActor private func reply(_ text: String, card: Card? = nil) -> ChatMessage {
    ChatMessage(role: .assistant, text: text, card: card)
}

@Test @MainActor func proseRepliesBringNoCard() {
    let messages = [reply("Listo, abrí Safari."), reply("Vuelos a Lima\n\nEl más barato sale el martes."),
                    reply("Y algo más.")]
    expect(IslandView.resultRows(messages, limit: 3).isEmpty, "prosa sola: ninguna tarjeta Ver →")
}

@Test @MainActor func aReplyWithADataCardBringsOne() {
    let fenced = reply("Las ventas del mes:\n\n" + salesFence)
    let channel = reply("", card: Card(payload: .table(TableBlock(columns: ["a"], rows: [["1"]])), source: .tool))
    let messages = [fenced, reply("Prosa."), channel, reply("La última.")]
    let rows = IslandView.resultRows(messages, limit: 3)
    expectEq(rows.map(\.id), [channel.id, fenced.id], "solo las que traen resultado, la más nueva primero")
}

@Test @MainActor func proseDoesNotUseUpTheTwoCards() {
    expectEq(IslandView.maxResults, 2, "dos tarjetas bajo la respuesta")
    let first = reply(salesFence), second = reply(salesFence)
    let messages = [reply(salesFence), first, reply("Prosa."), reply("Más prosa."), second, reply("La última.")]
    expectEq(IslandView.resultRows(messages, limit: IslandView.maxResults).map(\.id), [second.id, first.id],
             "la prosa no gasta el tope; quedan las dos tarjetas más nuevas")
}

@Test @MainActor func aProseLatestReplyDoesNotHideAnOlderCard() {
    let card = reply(salesFence)
    let status = ChatMessage(role: .assistant, isStatus: true, text: "Pensando…")
    expectEq(IslandView.resultRows([card, reply("Hola."), status], limit: 2).map(\.id), [card.id],
             "la última es la prosa, no la línea de estado; la tarjeta vieja sigue")
}

@Test @MainActor func edgeRepliesMakeNoRow() {
    let untitled = reply("```companion:stats\n{\"a\":1}\n```")
    let channelLatest = reply("", card: Card(payload: .table(TableBlock(columns: ["a"], rows: [["1"]])), source: .tool))
    let user = ChatMessage(role: .user, text: salesFence)
    expect(IslandView.resultRows([untitled, user, channelLatest], limit: 2).isEmpty,
           "sin título no hay tarjeta; la del usuario no cuenta; la última, aunque sea tarjeta, va en el panel")
}

@Test @MainActor func theLatestReplyIsNeverACard() {
    // The panel already shows it as the reply; a card for it would repeat it.
    let older = reply(salesFence)
    let latest = reply(salesFence)
    expectEq(IslandView.resultRows([older, latest], limit: 3).map(\.id), [older.id],
             "la última respuesta va en el panel, no como tarjeta")
}
