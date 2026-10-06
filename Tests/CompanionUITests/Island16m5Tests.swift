import AppKit
import Accessibility
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// Wave 16m-5a: the `visual` container and the chart painters. Measures come
// from docs/research/incredible-isla-componentes.md (fila gráfica, fila
// visual); geometry, palette contrast, spoken summary and copy are decided
// in pure code and pinned here before any view paints them.

@Test @MainActor func islandVisualMetricsTests() {
    testTheVisualContainerMeasures()
    testTheCanvasFollowsTheKind()
    testTheSeriesPaletteReadsOnTheIslandSurface()
}

@MainActor func testTheVisualContainerMeasures() {
    expectEq(IslandVisualMetrics.paddingTop, 14, "16m-5a: padding superior 14")
    expectEq(IslandVisualMetrics.paddingX, 16, "16m-5a: padding lateral 16")
    expectEq(IslandVisualMetrics.paddingBottom, 12, "16m-5a: padding inferior 12")
    expectEq(IslandVisualMetrics.fill, 0.05, "16m-5a: relleno 5 %")
    expectEq(IslandVisualMetrics.border, 0.07, "16m-5a: borde 7 %")
    expectEq(IslandVisualMetrics.radius, 12, "16m-5a: radio 12")
    expectEq(IslandVisualMetrics.canvas, 240, "16m-5a: lienzo 240")
    expectEq(IslandVisualMetrics.radialCanvas, 264, "16m-5a: lienzo radial 264")
}

@MainActor func testTheCanvasFollowsTheKind() {
    for kind in ChartBlock.Kind.allCases {
        let radial: Set<ChartBlock.Kind> = [.pie, .donut, .polar, .radar]
        expectEq(IslandVisualMetrics.canvasHeight(for: kind),
                 radial.contains(kind) ? 264 : 240, "16m-5a: lienzo de \(kind)")
    }
}

@MainActor func testTheSeriesPaletteReadsOnTheIslandSurface() {
    expectEq(IslandChartInk.series.count, ChartBlock.maxSeries,
             "16m-5a: un color por serie posible, ninguno repetido")
    expectEq(Set(IslandChartInk.series.map(\.hex)).count, ChartBlock.maxSeries, "16m-5a: colores distintos")
    let surface = surfaceHex()
    expectEq(surface, "0E0E10", "16m-5a: la superficie derivada del token es la de ovx")
    for swatch in IslandChartInk.series {
        expect(Contrast.ratio(hex: swatch.hex, hex: surface) >= IslandVisualMetrics.minSeriesContrast,
               "16m-5a: \(swatch.hex) contrasta con la isla")
    }
    expectEq(IslandVisualMetrics.minSeriesContrast, 3, "16m-5a: 3:1 para gráficos (WCAG 1.4.11)")
    expect(IslandChartInk.series.contains { $0.hex == Accent.teal.hex }, "16m-5a: el teal vive en los tokens")
    expectEq(IslandVisualMetrics.sectorGap, 1, "16m-5a: separación entre rebanadas con nombre")
    expectEq(IslandChartInk.series[0].hex, "55ADFF", "la primera serie es la azul de Arc en oscuro")
    // Past the palette the colours cycle, they never crash.
    expectEq(IslandChartInk.color(at: 8), IslandChartInk.color(at: 0), "16m-5a: la paleta cicla")
    expectEq(IslandChartInk.color(at: -1), IslandChartInk.color(at: 7), "16m-5a: un índice negativo no rompe")
}

/// The hex of the island surface token, read back from the colour itself.
@MainActor func surfaceHex() -> String {
    let color = NSColor(AnswerInk.surface).usingColorSpace(.sRGB) ?? .black
    func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
    return String(format: "%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent), byte(color.blueComponent))
}

@Test @MainActor func radialGeometryTests() {
    testRadarVerticesStartAtTheTopAndScale()
    testRadialGeometryNeverProducesNonFinitePoints()
    testPolarRadiiAndRings()
}

@MainActor func testRadarVerticesStartAtTheTopAndScale() {
    let center = CGPoint(x: 100, y: 100)
    let points = RadialGeometry.radarVertices(values: [10, 5, 10, 0], maximum: 10, center: center, radius: 80)
    expectEq(points.count, 4, "16m-5a: un vértice por eje")
    expect(abs(points[0].x - 100) < 0.001 && abs(points[0].y - 20) < 0.001, "16m-5a: el primer eje apunta arriba")
    expect(abs(points[1].x - 140) < 0.001 && abs(points[1].y - 100) < 0.001, "16m-5a: 5/10 a la derecha a media escala")
    expect(abs(points[2].x - 100) < 0.001 && abs(points[2].y - 180) < 0.001, "16m-5a: el tercero abajo")
    expect(abs(points[3].x - 100) < 0.001 && abs(points[3].y - 100) < 0.001, "16m-5a: un cero cae en el centro")
    expectEq(RadialGeometry.angle(index: 0, count: 4), -Double.pi / 2, "16m-5a: arranca en las 12")
    expect(abs(RadialGeometry.angle(index: 1, count: 4) - 0) < 1e-9, "16m-5a: el siguiente eje a las 3")
}

@MainActor func testRadialGeometryNeverProducesNonFinitePoints() {
    let center = CGPoint(x: 10, y: 10)
    let zero = RadialGeometry.radarVertices(values: [0, 0, 0], maximum: 0, center: center, radius: 50)
    expect(zero.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "16m-5a: máximo 0 no divide por cero")
    expect(RadialGeometry.radarVertices(values: [], maximum: 1, center: center, radius: 50).isEmpty,
           "16m-5a: sin valores no hay vértices")
    expectEq(RadialGeometry.angle(index: 0, count: 0), -Double.pi / 2, "16m-5a: count 0 no divide por cero")
    let tiny = RadialGeometry.polarRadii(values: [1, 2], maximum: -5, radius: 40)
    expect(tiny.allSatisfy { $0.isFinite && $0 >= 0 }, "16m-5a: un máximo negativo no da radios negativos")
    let over = RadialGeometry.polarRadii(values: [30], maximum: 10, radius: 40)
    expectEq(over, [40], "16m-5a: un valor sobre el máximo no se sale del lienzo")
}

@MainActor func testPolarRadiiAndRings() {
    expectEq(RadialGeometry.polarRadii(values: [0, 5, 10], maximum: 10, radius: 100), [0, 50, 100],
             "16m-5a: el radio es proporcional al valor")
    expectEq(RadialGeometry.ringRadii(count: 4, radius: 100), [25, 50, 75, 100], "16m-5a: cuatro anillos")
    expectEq(IslandVisualMetrics.radarRings, 4, "16m-5a: cuatro anillos")
    expect(RadialGeometry.ringRadii(count: 0, radius: 100).isEmpty, "16m-5a: cero anillos es vacío")
}

// MARK: - Spoken summary

@Test @MainActor func chartSpeechTests() async {
    await pinLanguage(.en) { testTheSummaryIsSpokenInEnglish() }
    await pinLanguage(.es) { testTheSummaryIsSpokenInSpanish() }
    await pinLanguage(.en) { testTheSummaryOmitsWhatItDoesNotHave() }
}

@MainActor private func speechBlock(_ kind: ChartBlock.Kind = .bar, title: String? = "Ventas") -> ChartBlock {
    ChartBlock(title: title, kind: kind, labels: ["Jul", "Ago", "Sep"],
               series: [.init(name: "QMs", values: [38, 44, 46.5])])
}

@MainActor func testTheSummaryIsSpokenInEnglish() {
    let text = IslandChartSpeech.summary(speechBlock())
    for part in ["Bar chart", "Ventas", "3 points", "highest", "Sep", "46.5", "lowest", "Jul", "38"] {
        expect(text.contains(part), "16m-5a: el resumen en inglés dice «\(part)» — \(text)")
    }
}

@MainActor func testTheSummaryIsSpokenInSpanish() {
    let text = IslandChartSpeech.summary(speechBlock(.radar))
    for part in ["Gráfica de radar", "Ventas", "3 puntos", "máximo", "Sep", "mínimo", "Jul"] {
        expect(text.contains(part), "16m-5a: el resumen en español dice «\(part)» — \(text)")
    }
}

@MainActor func testTheSummaryOmitsWhatItDoesNotHave() {
    let text = IslandChartSpeech.summary(speechBlock(.donut, title: nil))
    expect(text.contains("Donut chart"), "16m-5a: dice el tipo aunque no haya título — \(text)")
    expect(!text.contains("nil") && !text.contains("Optional"), "16m-5a: sin título no se cuela nil — \(text)")
    let one = IslandChartSpeech.summary(ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [7])]))
    expect(one.contains("1 point") && !one.contains("1 points"), "16m-5a: singular — \(one)")
}

// MARK: - Tools

@Test @MainActor func islandVisualToolsTests() {
    testCopyPutsTheFullCSVOnTheBoard()
    testCopyDoesNotTouchTheBoardWithNothingToSay()
}

@MainActor func testCopyPutsTheFullCSVOnTheBoard() {
    let board = NSPasteboard(name: NSPasteboard.Name("companion.test.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    let block = ChartBlock(title: "t", kind: .line, labels: ["a", "b"], series: [.init(name: "s", values: [1, 2])])
    IslandVisualTools.copy(block, to: board)
    expectEq(board.string(forType: .string), block.csv, "16m-5a: copiar lleva los datos completos como CSV")
    // A second copy replaces, never appends.
    IslandVisualTools.copy(ChartBlock(kind: .bar, labels: ["z"], series: [.init(values: [9])]), to: board)
    expectEq(board.string(forType: .string), ",1\nz,9", "16m-5a: copiar reemplaza el portapapeles")
}

@MainActor func testCopyDoesNotTouchTheBoardWithNothingToSay() {
    let board = NSPasteboard(name: NSPasteboard.Name("companion.test.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("antes", forType: .string)
    IslandVisualTools.copy(ChartBlock(kind: .bar, labels: [], series: []), to: board)
    expectEq(board.string(forType: .string), "antes", "16m-5a: sin datos no se pisa lo que ya había copiado")
}

// MARK: - What the painters read

@Test @MainActor func islandChartDataTests() {
    testSeriesNamesAreAlwaysDistinct()
    testEveryPointHasItsOwnPositionWhateverItsLabel()
    testDuplicateAndEmptyLabelsPaintEveryPoint()
    testRaggedAndHugeChartsRenderWithoutCrashing()
    testTheLegendNamesWhatTheColoursMean()
    testAPieLegendNeverShowsABlankName()
    testTheTableFallbackBoundsItsRows()
    testTheAxisShowsAnEvenSampleOfALongLabelList()
}

@MainActor func testSeriesNamesAreAlwaysDistinct() {
    let block = ChartBlock(kind: .bar, labels: ["a"], series: [
        .init(name: "x", values: [1]), .init(name: "x", values: [2]), .init(values: [3]), .init(name: "", values: [4]),
    ])
    let names = IslandChartData.seriesNames(block)
    expectEq(names, ["x", "x (2)", "3", "4"], "16m-5a: nombres de serie únicos y sin vacíos")
}

@MainActor func testAPieLegendNeverShowsABlankName() {
    let pie = ChartBlock(kind: .pie, labels: ["", "a", "a"], series: [.init(values: [1, 2, 3])])
    expectEq(IslandChartData.legend(pie).map(\.name), ["1", "a", "a (3)"], "16m-5a: la leyenda usa etiquetas únicas y no vacías")
}

@MainActor func testTheTableFallbackBoundsItsRows() {
    let rows = (0 ..< 500).map { ["r\($0)"] }
    let big = TableBlock(columns: ["c"], rows: rows)
    expectEq(TableCard.visibleRows(big).count, TableBlock.maxRows, "16m-5a: la tabla de respaldo no pinta más de \(TableBlock.maxRows) filas")
    expect(TableCard.isCut(big), "16m-5a: y lo dice")
    let small = TableBlock(columns: ["c"], rows: Array(rows.prefix(3)))
    expectEq(TableCard.visibleRows(small).count, 3, "16m-5a: una tabla corta se pinta entera")
    expect(!TableCard.isCut(small), "16m-5a: sin aviso")
    expect(TableCard.isCut(TableBlock(columns: ["c"], rows: [["x"]], truncated: true)), "16m-5a: el aviso de origen se respeta")
}

@MainActor func testTheLegendNamesWhatTheColoursMean() {
    let labels = (0 ..< 20).map { "l\($0)" }
    let pie = ChartBlock(kind: .pie, labels: labels, series: [.init(values: Array(repeating: 1, count: 20))])
    expectEq(IslandChartData.legend(pie).count, IslandChartData.maxLegend, "16m-5a: la leyenda de un pastel tiene tope")
    expectEq(IslandChartData.legend(pie).first, .init(name: "l0", colorIndex: 0), "16m-5a: cada rebanada su color")
    let single = ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [1])])
    expect(IslandChartData.legend(single).isEmpty, "16m-5a: una serie no necesita leyenda")
    let two = ChartBlock(kind: .radar, labels: ["a", "b", "c"],
                         series: [.init(name: "p", values: [1, 2, 3]), .init(name: "q", values: [3, 2, 1])])
    expectEq(IslandChartData.legend(two).map(\.name), ["p", "q"], "16m-5a: un radar de dos series lleva leyenda")
    let polar = ChartBlock(kind: .polar, labels: ["a", "b"], series: [.init(values: [1, 2])])
    expect(IslandChartData.legend(polar).isEmpty, "16m-5a: la polar rotula sus cuñas, sin leyenda")
}

@MainActor func testTheAxisShowsAnEvenSampleOfALongLabelList() {
    expectEq(IslandChartData.axisKeys(count: 3), ["0", "1", "2"], "16m-5a: pocas etiquetas se muestran todas")
    let shown = IslandChartData.axisKeys(count: 500)
    expect(shown.count <= IslandChartData.maxAxisLabels, "16m-5a: tope de etiquetas en el eje — \(shown.count)")
    expectEq(shown.first, "0", "16m-5a: la primera siempre entra")
    expectEq(IslandChartData.axisKeys(count: 0), [], "16m-5a: vacío no rompe")
    expectEq(IslandChartData.maximum(ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [-4])])), 0,
             "16m-5a: el máximo nunca es negativo")
}

@MainActor func testEveryPointHasItsOwnPositionWhateverItsLabel() {
    // The x position is the index; the label is only what the axis prints.
    expectEq(IslandChartData.xKeys(count: 3), ["0", "1", "2"], "16m-5a: una clave por punto")
    expectEq(Set(IslandChartData.xKeys(count: 500)).count, 500, "16m-5a: claves únicas")
    expectEq(IslandChartData.uniqueLabels(["Lun", "Lun", "", "Mar", "Mar"]),
             ["Lun", "Lun (2)", "3", "Mar", "Mar (5)"], "16m-5a: etiquetas únicas para VoiceOver")
    expectEq(IslandChartData.axisText(["a", "b"], key: "1"), "b", "16m-5a: el eje imprime la etiqueta del índice")
    expectEq(IslandChartData.axisText(["", "b"], key: "0"), "", "16m-5a: una etiqueta vacía se imprime vacía, no se pierde el punto")
    expectEq(IslandChartData.axisText(["a"], key: "9"), "", "16m-5a: un índice fuera de rango no revienta")
    expectEq(IslandChartData.axisText(["a"], key: "x"), "", "16m-5a: una clave que no es índice no revienta")
}

@MainActor func testDuplicateAndEmptyLabelsPaintEveryPoint() {
    let block = ChartBlock(kind: .bar, labels: ["Lun", "Lun", ""], series: [.init(values: [1, 2, 3])])
    let points = IslandChartData.points(block)
    expectEq(points.map(\.key), ["0", "1", "2"], "16m-5a: tres puntos distintos aunque repitan etiqueta")
    expectEq(points.map(\.value), [1, 2, 3], "16m-5a: cada uno con su valor")
    let ragged = ChartBlock(kind: .bar, labels: ["a", "b"], series: [.init(values: [1])])
    expectEq(IslandChartData.points(ragged).count, 1, "16m-5a: un largo desigual no revienta, solo pinta lo que hay")
}

@MainActor func testRaggedAndHugeChartsRenderWithoutCrashing() {
    let ragged = ChartBlock(kind: .bar, labels: ["a", "b", "c"], series: [.init(values: [1])])
    let pie = ChartBlock(kind: .pie, labels: ["a", "b"], series: [.init(values: [1])])
    for block in [ragged, pie] {
        let renderer = ImageRenderer(content: IslandChartVisual(block: block).frame(width: 548))
        expect(renderer.nsImage != nil, "16m-5a: \(block.kind) con largos distintos rinde sin crash")
    }
}

// MARK: - VoiceOver descriptor

@Test @MainActor func chartDescriptorTests() async {
    await pinLanguage(.en) { testTheDescriptorCarriesTheSamePoints() }
}

@MainActor func testTheDescriptorCarriesTheSamePoints() {
    let block = ChartBlock(title: "Ventas", kind: .line, unit: "USD", labels: ["Jul", "Ago"],
                           series: [.init(name: "a", values: [1, 2.5]), .init(name: "b", values: [3, 4])])
    let descriptor = IslandChartDescriptor(block: block).makeChartDescriptor()
    expectEq(descriptor.title, "Ventas", "16m-5a: el descriptor lleva el título")
    expectEq(descriptor.series.count, 2, "16m-5a: una serie por serie")
    expectEq(descriptor.series[0].dataPoints.count, 2, "16m-5a: un punto por etiqueta")
    expectEq(descriptor.series[1].name, "b", "16m-5a: el nombre de la serie")
    expect(descriptor.series[0].isContinuous, "16m-5a: una línea es continua")
    expect(descriptor.summary?.contains("2 points") == true, "16m-5a: el resumen es el hablado")
    let bar = ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [5])])
    expect(!IslandChartDescriptor(block: bar).makeChartDescriptor().series[0].isContinuous, "16m-5a: una barra no es continua")
    expectEq(descriptor.xAxis.title, "Ventas", "16m-5a: el eje X lleva el título de la gráfica")
    let untitled = IslandChartDescriptor(block: ChartBlock(kind: .bar, labels: ["a"], series: [.init(values: [5])])).makeChartDescriptor()
    expectEq(untitled.xAxis.title, "Categories", "16m-5a: sin título, «categorías»")
    let dup = ChartBlock(kind: .bar, labels: ["Lun", "Lun", ""], series: [.init(values: [1, 2, 3])])
    let dupDescriptor = IslandChartDescriptor(block: dup).makeChartDescriptor()
    let order = (dupDescriptor.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder ?? []
    expectEq(Set(order).count, 3, "16m-5a: categoryOrder sin duplicados — \(order)")
    expectEq(dupDescriptor.series[0].dataPoints.count, 3, "16m-5a: el descriptor conserva los tres puntos")
    let flat = ChartBlock(kind: .line, labels: ["a", "b"], series: [.init(values: [3, 3])])
    expectEq(IslandChartDescriptor(block: flat).makeChartDescriptor().series.count, 1, "16m-5a: una serie plana no rompe el rango")
}
