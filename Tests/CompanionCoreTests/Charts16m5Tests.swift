import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 16m-5a: charts in the island. The fence is the existing
// `companion:chart` (wave 20); 16m-5a adds polar and radar, and tightens the
// boundary so a chart is either whole or code, never half drawn.

@Test func chartBoundaryTests() {
    testPolarAndRadarAreKnownKinds()
    testUndrawableDataBecomesATableNotCode()
    testLegibilityCapsSendTheChartToATable()
    testOverTheCapIsBrokenNotTruncated()
    testAnySeriesLengthMismatchIsBroken()
    testNonFiniteAndNonNumericValuesAreBroken()
    testAbsurdMagnitudesAreATableNotCode()
    testTheCartesianBudgetSendsBigChartsToATable()
    testTheModelIsToldTheCaps()
    testUnknownKindStillFallsBackToATable()
    testOnlyChartFencesBecomeCharts()
    testTheModelIsToldPolarRadarAndWhenToUseThem()
    testAnOversizedFenceIsRefusedEverywhere()
}

private func fence(_ kind: String, labels: [String] = ["a", "b", "c"],
                   series: [[String]] = [["1", "2", "3"]]) -> String {
    let l = labels.map { "\"\($0)\"" }.joined(separator: ",")
    let s = series.map { "{\"values\":[\($0.joined(separator: ","))]}" }.joined(separator: ",")
    return "{\"kind\":\"\(kind)\",\"labels\":[\(l)],\"series\":[\(s)]}"
}

private func chart(_ body: String) -> ChartBlock? {
    if case .chart(let block)? = CompanionBlocks.chart(body) { return block }
    return nil
}

/// Whole data that cannot be drawn honestly: the numbers survive as a table.
private func isTable(_ body: String) -> Bool {
    if case .table? = CompanionBlocks.chart(body) { return true }
    return false
}

/// Structurally broken: nothing to show but the fence itself.
private func isBroken(_ body: String) -> Bool { CompanionBlocks.chart(body) == nil }

func testPolarAndRadarAreKnownKinds() {
    expectEq(chart(fence("polar"))?.kind, .polar, "16m-5a: polar es un tipo")
    expectEq(chart(fence("radar"))?.kind, .radar, "16m-5a: radar es un tipo")
    expectEq(chart(fence("RADAR"))?.kind, .radar, "16m-5a: el tipo no distingue mayúsculas")
    for kind in ["bar", "line", "area", "pie", "donut"] {
        expect(chart(fence(kind)) != nil, "16m-5a: \(kind) sigue parseando")
    }
}

func testUndrawableDataBecomesATableNotCode() {
    expect(isTable(fence("radar", labels: ["a", "b"], series: [["1", "2"]])),
           "16m-5a: un radar de dos ejes es tabla, los números no se tiran")
    expect(chart(fence("radar", series: [["1", "2", "3"], ["3", "2", "1"]])) != nil,
           "16m-5a: un radar compara varias series")
    for kind in ["pie", "donut", "polar"] {
        expect(isTable(fence(kind, series: [["1", "2", "3"], ["3", "2", "1"]])),
               "16m-5a: \(kind) con dos series es tabla, no se dibuja la primera")
    }
    for kind in ["pie", "donut", "polar", "radar"] {
        expect(isTable(fence(kind, series: [["1", "-2", "3"]])), "16m-5a: \(kind) con negativos es tabla")
        expect(isTable(fence(kind, series: [["0", "0", "0"]])), "16m-5a: \(kind) sin nada que dibujar es tabla")
    }
    if case .table(let table)? = CompanionBlocks.chart(fence("pie", series: [["1", "-2", "3"]])) {
        expectEq(table.rows.count, 3, "16m-5a: la tabla lleva todas las filas")
    }
    expect(chart(fence("bar", series: [["1", "-2", "3"]])) != nil, "16m-5a: una barra sí admite negativos")
    expect(chart(fence("line", series: [["-1", "-2", "-3"]])) != nil, "16m-5a: una línea sí admite negativos")
}

func testLegibilityCapsSendTheChartToATable() {
    func labels(_ n: Int) -> [String] { (0 ..< n).map { "l\($0)" } }
    func values(_ n: Int) -> [String] { (0 ..< n).map { "\($0 + 1)" } }
    let axes = ChartBlock.maxRadarAxes
    let slices = ChartBlock.maxSlices
    expect(chart(fence("radar", labels: labels(axes), series: [values(axes)])) != nil, "16m-5a: radar en el tope entra")
    expect(isTable(fence("radar", labels: labels(axes + 1), series: [values(axes + 1)])),
           "16m-5a: radar de \(axes + 1) ejes es tabla")
    for kind in ["pie", "donut", "polar"] {
        expect(chart(fence(kind, labels: labels(slices), series: [values(slices)])) != nil, "16m-5a: \(kind) en el tope entra")
        expect(isTable(fence(kind, labels: labels(slices + 1), series: [values(slices + 1)])),
               "16m-5a: \(kind) de \(slices + 1) rebanadas es tabla")
    }
    expect(chart(fence("bar", labels: labels(200), series: [values(200)])) != nil, "16m-5a: una barra larga sí se dibuja")
    expectEq(axes, 20, "16m-5a: tope de ejes")
    expectEq(slices, 12, "16m-5a: tope de rebanadas")
}

func testOverTheCapIsBrokenNotTruncated() {
    let over = ChartBlock.maxPoints + 1
    let labels = (0 ..< over).map { "l\($0)" }
    let values = (0 ..< over).map { "\($0)" }
    expect(isBroken(fence("line", labels: labels, series: [values])),
           "16m-5a: más de \(ChartBlock.maxPoints) puntos es dato roto, no se recorta")
    let atCap = ChartBlock.maxPoints
    expect(chart(fence("line", labels: Array(labels.prefix(atCap)), series: [Array(values.prefix(atCap))])) != nil,
           "16m-5a: justo el tope entra")
    let many = (0 ... ChartBlock.maxSeries).map { _ in ["1"] }
    expect(isBroken(fence("bar", labels: ["a"], series: many)), "16m-5a: más de \(ChartBlock.maxSeries) series es dato roto")
    expect(chart(fence("bar", labels: ["a"], series: Array(many.prefix(ChartBlock.maxSeries)))) != nil,
           "16m-5a: justo el tope de series entra")
}

func testAnySeriesLengthMismatchIsBroken() {
    expect(isBroken(fence("bar", series: [["1", "2"]])), "16m-5a: serie corta es dato roto")
    expect(isBroken(fence("bar", series: [["1", "2", "3", "4"]])), "16m-5a: serie larga es dato roto")
    expect(isBroken(fence("bar", series: [["1", "2", "3"], ["1"]])), "16m-5a: una sola serie mala tumba la gráfica")
}

func testNonFiniteAndNonNumericValuesAreBroken() {
    for bad in ["\"NaN\"", "\"1\"", "null", "true", "[1]", "{}", "1e999", "-1e999"] {
        expect(isBroken(fence("bar", series: [["1", bad, "3"]])), "16m-5a: el valor \(bad) no es un número finito")
    }
}

func testAbsurdMagnitudesAreATableNotCode() {
    // A huge finite number is real data the chart cannot draw: the numbers
    // survive as a table. NaN, inf and non-numbers stay broken (above).
    for body in [fence("pie", series: [["1e308", "1e308", "1"]]), fence("bar", series: [["1", "1e13", "3"]]),
                 fence("line", series: [["1", "-1e13", "3"]])] {
        expect(isTable(body), "16m-5a: magnitud fuera de techo es tabla — \(body)")
    }
    expect(chart(fence("bar", series: [["1", "1e12", "3"]])) != nil, "16m-5a: justo 1e12 entra")
    expectEq(ChartBlock.maxMagnitude, 1e12, "16m-5a: techo de magnitud con nombre")
}

func testTheCartesianBudgetSendsBigChartsToATable() {
    func labels(_ n: Int) -> [String] { (0 ..< n).map { "l\($0)" } }
    func values(_ n: Int) -> [String] { (0 ..< n).map { "\($0)" } }
    expectEq(ChartBlock.maxCartesianPoints, 1000, "16m-5a: presupuesto de puntos con nombre")
    expect(chart(fence("line", labels: labels(500), series: [values(500), values(500)])) != nil,
           "16m-5a: 500 x 2 = 1000 puntos entra")
    expect(isTable(fence("line", labels: labels(400), series: [values(400), values(400), values(400)])),
           "16m-5a: 400 x 3 = 1200 puntos es tabla")
    expect(isTable(fence("line", labels: labels(334), series: [values(334), values(334), values(334)])),
           "16m-5a: 334 x 3 = 1002 puntos es tabla")
    expect(chart(fence("line", labels: labels(333), series: [values(333), values(333), values(333)])) != nil,
           "16m-5a: 333 x 3 = 999 entra")
    expect(isTable(fence("bar", labels: labels(300), series: [values(300), values(300), values(300), values(300)])),
           "16m-5a: 300 x 4 es tabla")
    expect(chart(fence("bar", labels: labels(500), series: [values(500)])) != nil, "16m-5a: 500 x 1 entra")
}

func testUnknownKindStillFallsBackToATable() {
    guard case .table(let table)? = CompanionBlocks.chart(fence("sankey")) else {
        return expect(false, "16m-5a: un tipo desconocido queda como tabla")
    }
    expectEq(table.rows.count, 3, "16m-5a: la tabla lleva todas las filas")
}

func testOnlyChartFencesBecomeCharts() {
    for body in ["", "{", "[]", "null", "{}", "{\"kind\":\"bar\"}",
                 "{\"kind\":\"bar\",\"labels\":[],\"series\":[]}",
                 "{\"kind\":\"bar\",\"labels\":[\"a\"],\"series\":[]}",
                 "{\"kind\":\"bar\",\"labels\":[],\"series\":[{\"values\":[]}]}",
                 "{\"kind\":\"bar\",\"labels\":\"a\",\"series\":[{\"values\":[1]}]}"] {
        expect(isBroken(body), "16m-5a: «\(body)» es dato roto")
    }
    // Structurally broken data paints as code in the popup, never a half chart.
    let popup = AnswerBlocks.blocks(from: "```companion:chart\n{\"kind\":\"radar\",\"labels\":[\"a\"]}\n```")
    if case .code = popup[0] {} else { expect(false, "16m-5a: la fence rota se pinta como código") }
    let table = AnswerBlocks.blocks(from: "```companion:chart\n\(fence("radar", labels: ["a", "b"], series: [["1", "2"]]))\n```")
    if case .card(.table) = table[0] {} else { expect(false, "16m-5a: el radar sin ejes suficientes llega como tabla") }
    let good = AnswerBlocks.blocks(from: "```companion:chart\n\(fence("radar"))\n```")
    if case .card(.chart(let block)) = good[0] { expectEq(block.kind, .radar, "16m-5a: el radar llega al popup") }
    else { expect(false, "16m-5a: la fence válida llega como tarjeta de gráfica") }
}

func testTheModelIsToldPolarRadarAndWhenToUseThem() {
    for language in [AppLanguage.en, .es] {
        let text = CardVocabulary.text(language)
        expect(text.contains("polar") && text.contains("radar"), "16m-5a: \(language) enseña polar y radar")
        expect(text.contains("bar|line|area|pie|donut|scatter|polar|radar"),
               "16m-5a: \(language) lista todos los tipos")
    }
}

func testTheModelIsToldTheCaps() {
    for (language, words) in [(AppLanguage.en, ["slices", "axes", "points"]), (.es, ["rebanadas", "ejes", "puntos"])] {
        let text = CardVocabulary.text(language)
        expect(text.contains("\(ChartBlock.maxSlices) \(words[0])"), "16m-5a: \(language) dice el tope de rebanadas")
        expect(text.contains("\(ChartBlock.maxRadarAxes) \(words[1])"), "16m-5a: \(language) dice el tope de ejes")
        expect(text.contains("\(ChartBlock.maxCartesianPoints) \(words[2])"), "16m-5a: \(language) dice el tope de puntos")
    }
}

func testAnOversizedFenceIsRefusedEverywhere() {
    let pad = { (bytes: Int) in String(repeating: " ", count: bytes) }
    let chartBody = fence("bar")
    expect(isBroken(chartBody + pad(1 << 20)), "16m-5a: 1 MiB de gráfica es nil")
    expect(chart(chartBody + pad(10_000)) != nil, "16m-5a: 10 KB válidos parsean")
    expect(chart(chartBody + pad(CompanionBlocks.maxFenceBytes - chartBody.utf8.count)) != nil,
           "16m-5a: justo el tope entra")
    expect(chart(chartBody + pad(CompanionBlocks.maxFenceBytes - chartBody.utf8.count + 1)) == nil,
           "16m-5a: un byte más, no")
    expectEq(CompanionBlocks.maxFenceBytes, 256 * 1024, "16m-5a: tope de 256 KiB")
    let stats = "{\"items\":[{\"label\":\"a\",\"value\":\"1\"}]}"
    expect(CompanionBlocks.stats(stats) != nil && CompanionBlocks.stats(stats + pad(1 << 20)) == nil, "16m-5a: stats topa")
    let table = "{\"columns\":[\"a\"],\"rows\":[[\"1\"]]}"
    expect(CompanionBlocks.table(table) != nil && CompanionBlocks.table(table + pad(1 << 20)) == nil, "16m-5a: table topa")
    let places = "{\"locations\":[{\"id\":\"1\",\"name\":\"n\",\"lat\":1,\"lng\":1}]}"
    expect(CompanionBlocks.locations(places + pad(1 << 20)) == nil, "16m-5a: locations topa")
    expect(CompanionBlocks.gallery("{\"images\":[{\"url\":\"https://a.b/c.png\"}]}" + pad(1 << 20)) == nil, "16m-5a: gallery topa")
}

// MARK: - Text from the model

@Test func chartTextSanitizingTests() {
    testTheSanitizerStripsBidiAndControls()
    testTheSanitizerCapsLength()
    testTheSanitizerStripsFormatSeparatorsAndTags()
    testTheSanitizerBoundsCombiningMarks()
    testStatsTablesAndTitlesAreSanitizedToo()
    testChartTextIsSanitizedOnce()
    testDocumentsAndCSVNeverCarryHostileText()
}

func testTheSanitizerStripsBidiAndControls() {
    expectEq(TextSanitizer.display("fac\u{202E}tura\u{0000}x\u{0007}\u{2066}y\u{7F}z", maxLength: 120), "facturaxyz",
             "16m-5a: bidi y controles fuera")
    expectEq(TextSanitizer.display("línea\nnueva\tok", maxLength: 120), "línea\nnueva\tok", "16m-5a: salto y tabulador se conservan")
    expectEq(TextSanitizer.display("日本 😀 é", maxLength: 120), "日本 😀 é", "16m-5a: Unicode intacto")
    expectEq(TextSanitizer.display("", maxLength: 120), "", "16m-5a: vacío")
}

func testTheSanitizerCapsLength() {
    expectEq(TextSanitizer.display(String(repeating: "a", count: 10_000), maxLength: 120).count, 120, "16m-5a: 10 000 caracteres a 120")
    expectEq(TextSanitizer.display(String(repeating: "😀", count: 500), maxLength: 120).count, 120, "16m-5a: cuenta caracteres, no bytes")
    expectEq(TextSanitizer.maxLabel, 120, "16m-5a: tope con nombre")
}

func testTheSanitizerStripsFormatSeparatorsAndTags() {
    let d = { (t: String) in TextSanitizer.display(t, maxLength: 120) }
    expectEq(d("a\u{200B}b\u{FEFF}c\u{00AD}d"), "abcd", "16m-5a: espacios de ancho cero, BOM y guion blando fuera")
    expectEq(d("a\u{E0041}b\u{E0001}c\u{E007F}d"), "abcd", "16m-5a: etiquetas Unicode fuera")
    expectEq(d("a\u{E0100}b\u{E01EF}c"), "abc", "16m-5a: selectores de variación suplementarios fuera")
    expectEq(d("a\u{2028}b\u{2029}c"), "abc", "16m-5a: separadores de línea y párrafo fuera")
    expectEq(d("\u{2066}x\u{202E}y"), "xy", "16m-5a: bidi sigue cubierto")
    expectEq(d("👨\u{200D}👩\u{200D}👧"), "👨\u{200D}👩\u{200D}👧", "16m-5a: la familia con ZWJ queda intacta")
    expectEq(d("a\u{200C}b"), "a\u{200C}b", "16m-5a: ZWNJ se conserva (escrituras que lo necesitan)")
    expectEq(d("❤\u{FE0F}"), "❤\u{FE0F}", "16m-5a: el selector de emoji se conserva")
}

func testTheSanitizerBoundsCombiningMarks() {
    let zalgo = "a" + String(repeating: "\u{0301}", count: 5_000)
    let out = TextSanitizer.display(zalgo, maxLength: 120)
    expect(out.unicodeScalars.count <= 4 * 120, "16m-5a: zalgo acotado a 4 escalares por carácter — \(out.unicodeScalars.count)")
    expectEq(out.unicodeScalars.first, "a", "16m-5a: y el texto base sigue")
}

func testStatsTablesAndTitlesAreSanitizedToo() {
    let h = "x\\u202E\\u200B\\u0000y"
    let stats = CompanionBlocks.stats("{\"title\":\"\(h)\",\"items\":[{\"label\":\"\(h)\",\"value\":\"\(h)\",\"delta\":\"\(h)\"}]}")
    expectEq(stats?.title, "xy", "stats: título")
    expectEq(stats?.items.first?.label, "xy", "stats: etiqueta")
    expectEq(stats?.items.first?.value, "xy", "stats: valor")
    expectEq(stats?.items.first?.delta, "xy", "stats: delta")
    let table = CompanionBlocks.table("{\"title\":\"\(h)\",\"columns\":[\"\(h)\"],\"rows\":[[\"\(h)\"]]}")
    expectEq(table?.title, "xy", "tabla: título")
    expectEq(table?.columns, ["xy"], "tabla: columna")
    expectEq(table?.rows, [["xy"]], "tabla: celda")
    let long = String(repeating: "a", count: 10_000)
    let big = CompanionBlocks.table("{\"columns\":[\"\(long)\"],\"rows\":[[\"\(long)\"]]}")
    expectEq(big?.columns[0].count, TextSanitizer.maxLabel, "tabla: columna a 120")
    expectEq(big?.rows[0][0].count, TextSanitizer.maxCell, "tabla: celda al tope de celda")
    expectEq(TextSanitizer.maxCell, 500, "tope de celda con nombre")
    let reply = "```companion:chart\n{\"title\":\"\(h)\",\"kind\":\"bar\",\"labels\":[\"a\"],\"series\":[{\"values\":[1]}]}\n```"
    expectEq(MarkdownSplitter.firstCardTitle(reply), "xy", "título de la isla saneado")
}

func testChartTextIsSanitizedOnce() {
    let hostile = "x\\u202Ey\\u0000z"
    let body = "{\"title\":\"\(hostile)\",\"unit\":\"\(hostile)\",\"kind\":\"bar\",\"labels\":[\"\(hostile)\"],"
        + "\"series\":[{\"name\":\"\(hostile)\",\"values\":[1]}]}"
    guard let block = chart(body) else { return expect(false, "16m-5a: la gráfica hostil parsea") }
    expectEq(block.title, "xyz", "título saneado")
    expectEq(block.unit, "xyz", "unidad saneada")
    expectEq(block.labels, ["xyz"], "etiqueta saneada")
    expectEq(block.series[0].name, "xyz", "serie saneada")
    let long = String(repeating: "a", count: 10_000)
    let big = chart("{\"title\":\"\(long)\",\"kind\":\"bar\",\"labels\":[\"\(long)\"],\"series\":[{\"values\":[1]}]}")
    expectEq(big?.title?.count, 120, "título a 120")
    expectEq(big?.labels[0].count, 120, "etiqueta a 120")
}

func testDocumentsAndCSVNeverCarryHostileText() {
    let hostile = "\\u202E\\u0000\\u200B\\uDB40\\uDC41EVIL"
    let body = "{\"title\":\"\(hostile)\",\"kind\":\"bar\",\"labels\":[\"\(hostile)\"],\"series\":[{\"name\":\"\(hostile)\",\"values\":[1]}]}"
    guard let block = chart(body) else { return expect(false, "hostil: parsea") }
    for text in [block.csv, DocumentHTML.render(DocumentSpec(title: "X", blocks: [.chart(block)]))] {
        expect(!text.unicodeScalars.contains { [0x202E, 0, 0x200B, 0xE0041].contains($0.value) },
               "16m-5a: sin bidi, NUL, ancho cero ni etiquetas en la salida")
        expect(text.contains("EVIL"), "16m-5a: el texto legible se conserva")
    }
}

// MARK: - Documents never lose a chart in silence

@Test func documentChartTests() {
    testABrokenChartLeavesAVisibleNoteInTheDocument()
    testAnUndrawableChartLeavesATableInTheDocument()
    testAWholeDocumentIsNotHeldToTheFenceCap()
}

private func document(chart: String) -> DocumentSpec? {
    DocumentSpec.parse("{\"title\":\"T\",\"blocks\":[{\"type\":\"paragraph\",\"text\":\"antes\"},"
        + "{\"type\":\"chart\",\(chart)},{\"type\":\"paragraph\",\"text\":\"después\"}]}")
}

func testABrokenChartLeavesAVisibleNoteInTheDocument() {
    let spec = document(chart: "\"kind\":\"bar\",\"labels\":[\"a\",\"b\"],\"series\":[{\"values\":[1]}]")
    expectEq(spec?.blocks.count, 3, "16m-5a: la gráfica rota no desaparece: deja un bloque")
    if case .paragraph(let note)? = spec?.blocks[1] {
        expectEq(note, DocumentSpec.omittedChartNote, "16m-5a: la nota dice que se omitió")
        expect(note.contains("Gráfica omitida") && note.contains("Chart omitted"), "16m-5a: nota en los dos idiomas — \(note)")
    } else { expect(false, "16m-5a: el bloque de la gráfica rota es una nota") }
}

func testAnUndrawableChartLeavesATableInTheDocument() {
    let spec = document(chart: "\"kind\":\"radar\",\"labels\":[\"a\",\"b\"],\"series\":[{\"values\":[1,2]}]")
    if case .table(let table)? = spec?.blocks[1] { expectEq(table.rows.count, 2, "16m-5a: los números van en tabla") }
    else { expect(false, "16m-5a: la gráfica sin ejes suficientes es tabla en el documento") }
    let good = document(chart: "\"kind\":\"bar\",\"labels\":[\"a\"],\"series\":[{\"values\":[1]}]")
    if case .chart? = good?.blocks[1] {} else { expect(false, "16m-5a: la válida sigue siendo gráfica") }
}

// MARK: - Summary and copy

@Test func chartSummaryTests() {
    testTheSummaryCountsAndFindsExtremes()
    testTheSummaryOfASingleValue()
    testCSVQuotesAndGuardsFormulas()
    testCSVGuardsEveryFormulaTrigger()
    testCSVSeesThroughInvisibleCharacters()
    testCSVKeepsEverySeriesAndPoint()
    testASummaryOfRaggedDataDoesNotCrash()
}

private func block(_ kind: ChartBlock.Kind = .bar, title: String? = "Ventas",
                   labels: [String], _ series: [(String?, [Double])]) -> ChartBlock {
    ChartBlock(title: title, kind: kind, labels: labels,
               series: series.map { .init(name: $0.0, values: $0.1) })
}

func testTheSummaryCountsAndFindsExtremes() {
    let summary = ChartSummary(block(labels: ["Jul", "Ago", "Sep"],
                                     [("2025", [4, 9, 2]), ("2026", [5, 3, 12])]))
    expectEq(summary.kind, .bar, "resumen: tipo")
    expectEq(summary.title, "Ventas", "resumen: título")
    expectEq(summary.pointCount, 3, "resumen: puntos por serie")
    expectEq(summary.seriesCount, 2, "resumen: series")
    expectEq(summary.maximum, .init(label: "Sep", series: "2026", value: 12), "resumen: el máximo dice dónde")
    expectEq(summary.minimum, .init(label: "Sep", series: "2025", value: 2), "resumen: el mínimo dice dónde")
}

func testTheSummaryOfASingleValue() {
    let summary = ChartSummary(block(title: nil, labels: ["a"], [(nil, [7])]))
    expectEq(summary.maximum?.value, 7, "resumen: un solo punto es su máximo")
    expectEq(summary.minimum?.value, 7, "resumen: y su mínimo")
    expectEq(summary.maximum?.series, nil, "resumen: sin nombre de serie no se inventa uno")
    expectEq(summary.title, nil, "resumen: sin título")
}

func testCSVQuotesAndGuardsFormulas() {
    let csv = block(labels: ["a,b", "say \"hi\"", "=SUM(A1)", "línea\nnueva", "日本 😀"],
                    [("x", [1, -2.5, 3, 4, 5])]).csv
    let lines = csv.components(separatedBy: "\n")
    expectEq(lines.first, ",x", "CSV: cabecera con el nombre de la serie")
    expect(csv.contains("\"a,b\",1"), "CSV: la coma se entrecomilla")
    expect(csv.contains("\"say \"\"hi\"\"\",-2.5"), "CSV: la comilla se duplica y el negativo queda numérico")
    expect(csv.contains("'=SUM(A1),3"), "CSV: una etiqueta que empieza con = no se ejecuta en la hoja")
    expect(csv.contains("\"línea\nnueva\",4"), "CSV: el salto de línea va entre comillas")
    expect(csv.contains("日本 😀,5"), "CSV: Unicode intacto")
}

func testCSVSeesThroughInvisibleCharacters() {
    for risky in ["\u{200B}=1+1", "\u{FEFF}@x", "\u{E0041}+1"] {
        let cell = block(labels: [risky], [("x", [1])]).csv.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        expect(cell.hasPrefix("'"), "CSV: «\(risky.debugDescription)» se defusa aunque el primer carácter sea invisible — \(cell.debugDescription)")
    }
}

func testCSVGuardsEveryFormulaTrigger() {
    for risky in ["%cmd", "|cmd", "\ncmd", " =1+1", "\u{2003}=1", "\u{00A0}@x", "\t+1", "\r-1", "+1", "-1", "@a"] {
        let csv = block(labels: [risky], [("x", [1])]).csv
        let cell = csv.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
        expect(cell.hasPrefix("'") || cell.hasPrefix("\"'"), "CSV: «\(risky.debugDescription)» se defusa — \(cell.debugDescription)")
    }
    for safe in ["cmd", "1+1", "a=b", "日本"] {
        let csv = block(labels: [safe], [("x", [1])]).csv
        expect(!csv.contains("'"), "CSV: «\(safe)» no se toca")
    }
}

func testCSVKeepsEverySeriesAndPoint() {
    let csv = block(labels: ["a", "b"], [("s1", [1, 2]), (nil, [3, 4.5])]).csv
    expectEq(csv, ",s1,2\na,1,3\nb,2,4.5", "CSV: una columna por serie, sin nombre queda su número")
}

// MARK: - Surfaces that do not paint polar and radar

@Test func radialFallbackTests() {
    testThePDFShowsRadialKindsAsATable()
}

func testThePDFShowsRadialKindsAsATable() {
    for kind in [ChartBlock.Kind.polar, .radar] {
        let block = ChartBlock(title: "t", kind: kind, labels: ["a", "b", "c"], series: [.init(name: "s", values: [1, 3, 2])])
        let html = DocumentHTML.render(DocumentSpec(title: "X", blocks: [.chart(block)]))
        expect(html.contains("<table") && !html.contains("<svg"),
               "16m-5a: \(kind) en el PDF es una tabla, no barras con otro nombre")
    }
    let bar = ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [1])])
    expect(DocumentHTML.render(DocumentSpec(title: "X", blocks: [.chart(bar)])).contains("<svg"),
           "16m-5a: una barra sigue siendo SVG")
    expect(ChartBlock.Kind.polar.isIslandOnly && ChartBlock.Kind.radar.isIslandOnly, "16m-5a: polar y radar son de la isla")
    expect(!ChartBlock.Kind.bar.isIslandOnly, "16m-5a: la barra la pintan todos")
}

func testASummaryOfRaggedDataDoesNotCrash() {
    let ragged = ChartBlock(kind: .bar, labels: ["a", "b"], series: [.init(values: [1, 5, 9]), .init(values: [2])])
    let summary = ChartSummary(ragged)
    expectEq(summary.maximum?.value, 9, "resumen: un ChartBlock con largos distintos no revienta")
    expectEq(summary.maximum?.label, "3", "resumen: y un punto sin etiqueta se numera")
    _ = ragged.csv
}

func testAWholeDocumentIsNotHeldToTheFenceCap() {
    let text = String(repeating: "a", count: 19_000)
    let blocks = (0 ..< 60).map { _ in "{\"type\":\"paragraph\",\"text\":\"\(text)\"}" }.joined(separator: ",")
    let json = "{\"title\":\"T\",\"blocks\":[\(blocks)]}"
    expect(json.utf8.count > 1 << 20, "documento de prueba de más de 1 MiB")
    expectEq(DocumentSpec.parse(json)?.blocks.count, 60, "16m-5a: el documento entero no cae bajo el tope del fence")
}

// MARK: - Byte caps and the invariant that keeps them

@Test func byteCapTests() {
    testADocumentHasItsOwnCap()
    testASheetWriteHasItsOwnCap()
    testNoCodeParsesModelJSONOutsideTheCappedDoors()
}

func testADocumentHasItsOwnCap() {
    let json = "{\"title\":\"T\",\"blocks\":[{\"type\":\"divider\"}]}"
    let pad = { (n: Int) in String(repeating: " ", count: n) }
    expectEq(DocumentSpec.maxDocumentBytes, 4 * 1024 * 1024, "16m-5a: tope de documento con nombre")
    let atCap = json + pad(DocumentSpec.maxDocumentBytes - json.utf8.count)
    expect(DocumentSpec.parse(atCap) != nil, "16m-5a: justo el tope de documento entra")
    expect(DocumentSpec.parse(atCap + " ") == nil, "16m-5a: un byte más, no")
    expect(DocumentSpec.parse(any: atCap + " ") == nil, "16m-5a: la rama String de parse(any:) también topa")
    expect(DocumentSpec.parse(any: atCap) != nil, "16m-5a: y deja pasar lo que cabe")
}

func testASheetWriteHasItsOwnCap() {
    guard let range = SheetRange(a1: "A1") else { return expect(false, "rango") }
    let json = "[[1]]"
    expectEq(SheetValues.maxSheetBytes, 1024 * 1024, "16m-5a: tope de escritura con nombre")
    let atCap = json + String(repeating: " ", count: SheetValues.maxSheetBytes - json.utf8.count)
    if case .success = SheetValues.parse(any: atCap, for: range) {} else { expect(false, "16m-5a: justo el tope de hoja entra") }
    if case .failure = SheetValues.parse(any: atCap + " ", for: range) {} else { expect(false, "16m-5a: un byte más, no") }
}

/// The uncapped parser is for documents (capped in DocumentSpec.parse) only;
/// a new caller of it would reopen the memory door the fence cap closed.
func testNoCodeParsesModelJSONOutsideTheCappedDoors() {
    let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
    guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
        return expect(false, "16m-5a: no se pudo leer Sources")
    }
    var offenders: [String] = []
    let pattern = try? NSRegularExpression(pattern: #"(CompanionBlocks\.jsonObject\(|(?<![A-Za-z.])jsonObject\(body\))"#)
    for case let file as URL in walker where file.pathExtension == "swift" {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
        for (number, line) in text.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard pattern?.firstMatch(in: line, range: range) != nil else { continue }
            let allowed = (file.lastPathComponent == "DocumentSpec.swift" && line.contains("CompanionBlocks.jsonObject(json)"))
                || (file.lastPathComponent == "CompanionBlocks.swift" && line.contains("? jsonObject(body) : nil"))
            if !allowed { offenders.append("\(file.lastPathComponent):\(number + 1)") }
        }
    }
    expectEq(offenders, [], "16m-5a: jsonObject sin tope fuera de sus dos puertas")
}
