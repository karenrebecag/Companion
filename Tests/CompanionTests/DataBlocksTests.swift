@testable import CompanionCore
import Foundation
import Testing

// Wave 20-0 (spec 20 §5, §6.1-3): figures, tables and charts travel on the
// card channel like maps do — parsed, bounded, and never silently dropped.

@Test func dataBlocksTests() {
    testStatsParseLabelsAndValues()
    testATableKeepsItsShapeAndIsBounded()
    testARaggedRowIsPaddedOrCut()
    testAChartNeedsOneValuePerLabel()
    testAnUnknownChartKindFallsBackToATable()
    testChartsAreBounded()
    testBrokenFencesStayNil()
    testTheModelIsToldTheNewFences()
    testMemoryNamesTheNewCards()
}

func testStatsParseLabelsAndValues() {
    let body = #"{"title":"Ventas","items":[{"label":"Total","value":"$12,400","delta":"+8 %"},{"label":"Pedidos","value":312}]}"#
    guard let block = CompanionBlocks.stats(body) else { return expect(false, "stats: parsea") }
    expectEq(block.title, "Ventas", "stats: título")
    expectEq(block.items.count, 2, "stats: dos métricas")
    expectEq(block.items[0].delta, "+8 %", "stats: variación opcional")
    expectEq(block.items[1].value, "312", "stats: un número se muestra como texto")
    let many = (0..<30).map { #"{"label":"m\#($0)","value":"1"}"# }.joined(separator: ",")
    expectEq(CompanionBlocks.stats(#"{"items":[\#(many)]}"#)?.items.count, StatsBlock.maxItems,
             "stats: tope de métricas")
    expect(CompanionBlocks.stats(#"{"items":[]}"#) == nil, "stats: vacío no es tarjeta")
}

func testATableKeepsItsShapeAndIsBounded() {
    let body = #"{"columns":["Plan","Precio","Usuarios"],"rows":[["Básico","$9",1],["Pro","$29",5]]}"#
    guard let table = CompanionBlocks.table(body) else { return expect(false, "tabla: parsea") }
    expectEq(table.columns, ["Plan", "Precio", "Usuarios"], "tabla: columnas")
    expectEq(table.rows[1], ["Pro", "$29", "5"], "tabla: celdas numéricas como texto")
    expect(!table.truncated, "tabla: sin recorte")
    let rows = (0..<250).map { #"["r\#($0)","1"]"# }.joined(separator: ",")
    let big = CompanionBlocks.table(#"{"columns":["a","b"],"rows":[\#(rows)]}"#)
    expectEq(big?.rows.count, TableBlock.maxRows, "tabla: 200 filas como mucho")
    expect(big?.truncated == true, "tabla: y lo dice")
}

func testARaggedRowIsPaddedOrCut() {
    let body = #"{"columns":["a","b","c"],"rows":[["1"],["1","2","3","4"]]}"#
    let table = CompanionBlocks.table(body)
    expectEq(table?.rows[0], ["1", "", ""], "tabla: fila corta se rellena")
    expectEq(table?.rows[1], ["1", "2", "3"], "tabla: fila larga se corta")
}

func testAChartNeedsOneValuePerLabel() {
    let body = #"{"title":"Ingresos","kind":"line","unit":"USD","labels":["ene","feb","mar"],"series":[{"name":"2025","values":[10,12,9]},{"name":"2026","values":[11,15,14]}]}"#
    guard case .chart(let chart)? = CompanionBlocks.chart(body) else { return expect(false, "gráfica: parsea") }
    expectEq(chart.kind, .line, "gráfica: tipo")
    expectEq(chart.series.count, 2, "gráfica: dos series")
    expectEq(chart.unit, "USD", "gráfica: unidad")
    let mismatched = #"{"kind":"bar","labels":["a","b"],"series":[{"values":[1]}]}"#
    expect(CompanionBlocks.chart(mismatched) == nil, "gráfica: una serie más corta que las etiquetas no se dibuja")
    let donut = #"{"kind":"donut","labels":["a","b"],"series":[{"values":[1,2]}]}"#
    guard case .chart(let ring)? = CompanionBlocks.chart(donut) else { return expect(false, "donut: parsea") }
    expectEq(ring.kind, .donut, "gráfica: donut")
}

func testAnUnknownChartKindFallsBackToATable() {
    let body = #"{"kind":"radar","labels":["a","b"],"series":[{"name":"s","values":[1,2]}]}"#
    guard case .table(let table)? = CompanionBlocks.chart(body) else {
        return expect(false, "gráfica desconocida: cae a tabla, nunca a nada")
    }
    expectEq(table.columns, ["", "s"], "tabla de respaldo: etiquetas y una columna por serie")
    expectEq(table.rows, [["a", "1"], ["b", "2"]], "tabla de respaldo: los mismos datos")
}

func testChartsAreBounded() {
    let labels = (0..<600).map { "\"l\($0)\"" }.joined(separator: ",")
    let values = (0..<600).map { "\($0)" }.joined(separator: ",")
    let body = #"{"kind":"line","labels":[\#(labels)],"series":[{"values":[\#(values)]}]}"#
    guard case .chart(let chart)? = CompanionBlocks.chart(body) else { return expect(false, "gráfica larga: parsea") }
    expectEq(chart.labels.count, ChartBlock.maxPoints, "gráfica: 500 puntos como mucho")
    expectEq(chart.series[0].values.count, ChartBlock.maxPoints, "gráfica: la serie se recorta igual")
    let series = (0..<12).map { _ in #"{"values":[1]}"# }.joined(separator: ",")
    guard case .chart(let wide)? = CompanionBlocks.chart(#"{"kind":"bar","labels":["a"],"series":[\#(series)]}"#)
    else { return expect(false, "muchas series: parsea") }
    expectEq(wide.series.count, ChartBlock.maxSeries, "gráfica: 8 series como mucho")
}

func testBrokenFencesStayNil() {
    expect(CompanionBlocks.stats("{no") == nil, "stats roto: nil, queda como código")
    expect(CompanionBlocks.table(#"{"columns":[],"rows":[]}"#) == nil, "tabla sin columnas: nil")
    expect(CompanionBlocks.chart(#"{"kind":"bar","labels":["a"],"series":[{"values":[true]}]}"#) == nil,
           "gráfica: un booleano no es un número")
}

func testTheModelIsToldTheNewFences() {
    for language in [AppLanguage.en, .es] {
        let text = CardVocabulary.text(language)
        for fence in [CompanionBlocks.statsLanguage, CompanionBlocks.tableLanguage, CompanionBlocks.chartLanguage] {
            expect(text.contains(fence), "vocabulario \(language): enseña \(fence)")
        }
    }
}

func testMemoryNamesTheNewCards() {
    let reply = "Mira:\n```\(CompanionBlocks.chartLanguage)\n{\"kind\":\"bar\"}\n```\nListo."
    let kept = ConversationMemory.withoutCards(reply)
    expect(!kept.contains("\"kind\""), "memoria: el JSON de la tarjeta no vuelve al modelo")
    expect(kept.contains("["), "memoria: queda un marcador de lo que se mostró")
}
