import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 20-1 (spec 20 §6.1-3): the data fences reach the cards, a broken one
// stays visible as code, and the words exist in both languages.

@Test @MainActor func dataCardsTests() async {
    testTheDataFencesBecomeCards()
    testChartPointsKeepEverySeries()
    testTheDeltaReadsItsSign()
    await testTheCardWordsAreInBothLanguages()
    testTheModelHearsThatDataWasShown()
}

@MainActor func testTheDataFencesBecomeCards() {
    let stats = MarkdownView.dataCard(language: CompanionBlocks.statsLanguage,
                                      body: #"{"items":[{"label":"a","value":"1"}]}"#)
    guard case .stats? = stats else { return expect(false, "fence stats: tarjeta de cifras") }
    let table = MarkdownView.dataCard(language: CompanionBlocks.tableLanguage,
                                      body: #"{"columns":["a"],"rows":[["1"]]}"#)
    guard case .table? = table else { return expect(false, "fence table: tabla") }
    let chart = MarkdownView.dataCard(language: CompanionBlocks.chartLanguage,
                                      body: #"{"kind":"bar","labels":["a"],"series":[{"values":[1]}]}"#)
    guard case .chart? = chart else { return expect(false, "fence chart: gráfica") }
    expect(MarkdownView.dataCard(language: CompanionBlocks.chartLanguage, body: "{roto") == nil,
           "fence roto: nil, se queda como código visible")
    expect(MarkdownView.dataCard(language: "swift", body: "{}") == nil, "un fence normal no es tarjeta")
}

@MainActor func testChartPointsKeepEverySeries() {
    let block = ChartBlock(kind: .bar, labels: ["ene", "feb"], series: [
        .init(name: "A", values: [1, 2]), .init(values: [3, 4]),
    ])
    let points = ChartPoint.flatten(block)
    expectEq(points.count, 4, "gráfica: una fila por serie y etiqueta")
    expectEq(points.last?.seriesName, "2", "gráfica: una serie sin nombre se numera")
    expectEq(Set(points.map(\.id)).count, 4, "gráfica: ids únicos")
}

@MainActor func testTheDeltaReadsItsSign() {
    expectEq(DataCardInk.tone("+8 %"), .up, "variación positiva: verde")
    expectEq(DataCardInk.tone("\u{2212}3"), .down, "variación negativa (signo menos tipográfico): rojo")
    expectEq(DataCardInk.tone("-3"), .down, "variación negativa con guion")
    expectEq(DataCardInk.tone("igual"), .flat, "sin signo: neutra")
}

@MainActor func testTheCardWordsAreInBothLanguages() async {
    for language in [AppLanguage.es, .en] {
        await Localized.scoped(to: language) {
            for key in ["card.table.truncated", "card.chart", "chat.card.data"] {
                expect(Localized.string(key) != key, "\(language): \(key) está en el catálogo")
            }
        }
    }
}

@MainActor func testTheModelHearsThatDataWasShown() {
    let card = Card(payload: .table(TableBlock(columns: ["a"], rows: [["1"]])), source: .tool)
    expect(!ChatCopy.cardShown(card).isEmpty, "el modelo sabe que se mostró una tabla")
}
