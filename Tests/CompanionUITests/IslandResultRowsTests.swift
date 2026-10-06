import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// K6 (brief isla-ciclo-y-legibilidad, signed by Karen): every past reply
// became a "Ver →" card, so plain answers stacked up as cards with nothing
// behind them. Only a reply that brings a result does: a data card, from the
// card channel the popup can draw, or a `companion:` fence the popup draws
// (.card or .diagram). Prose alone does not.
// A gallery is excluded on purpose: GalleryCard loads and opens file paths
// from the card; pending the same validation fence galleries wait for
// (AnswerBlocks.swift:155). NOT DONE: a finished file or a sheet deliverable
// still has no opener, so it gets no Ver row.

private let salesFence = "```companion:stats\n{\"title\":\"Ventas\",\"items\":[{\"label\":\"a\",\"value\":\"1\"}]}\n```"
private let galleryFence = "```companion:gallery\n{\"title\":\"Fotos\",\"images\":[{\"path\":\"/tmp/a.png\"}]}\n```"
private let richProse = String(repeating: "palabra ", count: 80)

@MainActor private func reply(_ text: String, card: Card? = nil) -> ChatMessage {
    ChatMessage(role: .assistant, text: text, card: card)
}

private func tableCard(cell: String = "K6CELL") -> Card {
    Card(payload: .table(TableBlock(columns: ["a"], rows: [[cell]])), source: .tool)
}

private func galleryCard() -> Card {
    Card(payload: .gallery(GalleryBlock(images: [.init(path: "/tmp/a.png")])), source: .tool)
}

@Test @MainActor func proseRepliesBringNoCard() {
    let messages = [reply("Listo, abrí Safari."), reply("Vuelos a Lima\n\nEl más barato sale el martes."),
                    reply("Y algo más.")]
    expect(IslandView.resultRows(messages, limit: 3).isEmpty, "prosa sola: ninguna tarjeta Ver →")
}

@Test @MainActor func aReplyWithADataCardBringsOne() {
    let fenced = reply("Las ventas del mes:\n\n" + salesFence)
    let channel = reply("", card: tableCard(cell: "1"))
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
    let channelLatest = reply("", card: tableCard(cell: "1"))
    let user = ChatMessage(role: .user, text: salesFence)
    expect(IslandView.resultRows([untitled, user, channelLatest], limit: 2).isEmpty,
           "sin título no hay tarjeta; la del usuario no cuenta; la última, aunque sea tarjeta, va en el panel")
}

@Test @MainActor func aGalleryOnTheChannelIsNotARow() {
    let gallery = reply("", card: galleryCard())
    expect(IslandView.resultRows([gallery, reply("Última.")], limit: 2).isEmpty,
           "galería en el canal: el popup no la dibuja, a propósito, así que no hay Ver")
}

@Test @MainActor func aTableOnTheChannelIsARow() {
    let table = reply("", card: tableCard(cell: "1"))
    expectEq(IslandView.resultRows([table, reply("Última.")], limit: 2).map(\.id), [table.id],
             "una tabla del canal sí se puede abrir")
}

@Test @MainActor func aGalleryIsNotDrawnInThePopup() {
    expect(!IslandView.opensInPopup(reply("", card: galleryCard())),
           "galería: el popup no la dibuja, a propósito")
}

@Test @MainActor func aTableChannelOpensInThePopup() {
    expect(IslandView.opensInPopup(reply("", card: tableCard(cell: "1"))),
           "tabla: Ver abre el popup con la tarjeta")
}

@Test @MainActor func shortProseDoesNotOpenThePopup() {
    expect(!IslandView.opensInPopup(reply("Solo prosa.")), "prosa corta: sigue abriendo la ventana")
}

@Test @MainActor func channelCardDropsAGallery() {
    expectEq(IslandView.channelCard(on: reply("", card: galleryCard())), nil,
             "galería en el canal: el helper no se la pasa al popup")
}

@Test @MainActor func channelCardKeepsATable() {
    let table = tableCard()
    expectEq(IslandView.channelCard(on: reply("", card: table)), table,
             "tabla en el canal: el helper devuelve esa tarjeta")
}

@Test @MainActor func answerBlockListDrawsTheChannelTable() throws {
    let filled = try #require(hostedShot(AnswerBlockList(card: tableCard(), blocks: [])))
    let bare = try #require(hostedShot(AnswerBlockList(card: nil, blocks: [])))
    expect(filled.height > bare.height, "AnswerBlockList dibuja la tabla del canal")
    let popup = try #require(hostedShot(AnswerPopupView(
        blocks: [], card: tableCard(), screenWidth: 800, maxHeight: 640, onClose: {})))
    let emptyPopup = try #require(hostedShot(AnswerPopupView(
        blocks: [], card: nil, screenWidth: 800, maxHeight: 640, onClose: {})))
    expect(popup != emptyPopup, "AnswerPopupView dibuja la tabla del canal")
}

@Test @MainActor func answerBlockListDrawsNoCardWhenTheCardIsNil() throws {
    let bare = try #require(hostedShot(AnswerBlockList(card: nil, blocks: [])))
    expect(bare.height < 8, "AnswerBlockList sin tarjeta no dibuja una card view")
}

@Test @MainActor func aFencePlusATableCardIsOneRowTitledFromTheFence() {
    let message = reply(salesFence, card: tableCard())
    let rows = IslandView.resultRows([message, reply("Última.")], limit: 2)
    expectEq(rows.map(\.id), [message.id], "fence y tarjeta de canal: una sola fila")
    expectEq(rows.first?.result.title, "Ventas", "el título sale del fence")
    expect(IslandView.opensInPopup(message), "fence y tabla: Ver abre el popup")
}

@Test @MainActor func aFencePlusAGalleryChannelStillOpens() {
    let message = reply(salesFence, card: galleryCard())
    let rows = IslandView.resultRows([message, reply("Última.")], limit: 2)
    expectEq(rows.map(\.id), [message.id], "fence con galería en el canal: la fila sigue")
    expect(IslandView.opensInPopup(message), "fence con galería: el popup abre el fence")
}

@Test @MainActor func popupCanDrawOverEveryPayloadKind() {
    let draw: [(String, Card, Bool)] = [
        ("locations", Card(payload: .locations(LocationsBlock(locations: [.init(name: "Lima", lat: 1, lng: 2)])), source: .tool), true),
        ("gallery", galleryCard(), false),
        ("stats", Card(payload: .stats(StatsBlock(items: [.init(label: "a", value: "1")])), source: .tool), true),
        ("table", tableCard(), true),
        ("chart", Card(payload: .chart(ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [1])])), source: .tool), true),
    ]
    for (name, card, canDraw) in draw {
        expectEq(IslandView.popupCanDraw(card), canDraw, "popupCanDraw \(name)")
    }
}

@Test @MainActor func opensInPopupForRichTextButNotAGalleryWithProse() {
    expect(IslandView.opensInPopup(reply(richProse)), "texto rico, sin tarjeta: abre el popup")
    expect(!IslandView.opensInPopup(reply(richProse, card: galleryCard())),
           "galería con prosa: el popup no la dibuja, a propósito")
}

@Test @MainActor func aGalleryFenceIsNotARow() {
    let message = reply(galleryFence)
    expect(IslandView.resultRows([message, reply("Última.")], limit: 2).isEmpty,
           "fence de galería: el popup no la dibuja, así que no hay Ver")
    expect(!IslandView.opensInPopup(message), "fence de galería: el popup no abre el JSON crudo")
}

@Test @MainActor func theLatestReplyIsNeverACard() {
    // The panel already shows it as the reply; a card for it would repeat it.
    let older = reply(salesFence)
    let latest = reply(salesFence)
    expectEq(IslandView.resultRows([older, latest], limit: 3).map(\.id), [older.id],
             "la última respuesta va en el panel, no como tarjeta")
}

private struct HostedShot: Equatable {
    var height: Int
    var bytes: [UInt8]
}

@MainActor private func hostedShot(_ view: some View) -> HostedShot? {
    let hosting = NSHostingView(rootView: view.frame(width: 420).environment(\.colorScheme, .light))
    let fitted = hosting.fittingSize
    hosting.frame = NSRect(x: 0, y: 0, width: 420, height: max(fitted.height, 1))
    let window = NSWindow(
        contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    defer { window.close() }
    hosting.appearance = NSAppearance(named: .aqua)
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
          let data = rep.bitmapData, rep.pixelsHigh > 0
    else { return nil }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let count = rep.bytesPerRow * rep.pixelsHigh
    return HostedShot(
        height: rep.pixelsHigh,
        bytes: Array(UnsafeBufferPointer(start: data, count: count)))
}
