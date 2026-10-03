import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import SwiftUI
import Testing

// The donut ring ported from Arc's free donut-chart (uiarc.dev): grouping,
// arcs per key, the sweep, the morph between datasets, the counting total
// and the spoken parts are decided in pure code and pinned here before the
// ring paints them.

private func donut(_ labels: [String], _ values: [Double], unit: String? = nil) -> ChartBlock {
    ChartBlock(title: "Canal", kind: .donut, unit: unit, labels: labels, series: [.init(values: values)])
}

/// A real label's key: keys are namespaced so no label can be the Other key.
@MainActor private func k(_ label: String) -> String { DonutLayout.key(label) }

/// What a test reads off a segment: its label, or OTHER for the grouped one.
@MainActor private func names<S: Sequence>(_ slices: S) -> [String] where S.Element == DonutLayout.Slice { slices.map { $0.isOther ? "OTHER" : $0.label } }

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

// MARK: - Metrics

@Test @MainActor func islandDonutMetricsTests() {
    expectEq(IslandVisualMetrics.donutSize, 208, "arc: diámetro 208")
    expectEq(IslandVisualMetrics.donutThickness, 24, "arc: grosor 24")
    expectEq(IslandVisualMetrics.donutMargin, 7, "arc: margen 7 alrededor del anillo")
    expectEq(IslandVisualMetrics.donutGap, 3, "arc: separación 3 entre segmentos")
    expectEq(IslandVisualMetrics.donutCorner, 4, "arc: esquinas de 4")
    expectEq(IslandVisualMetrics.donutGroupBelow, 0.04, "arc: groupBelow 0.04")
    expectEq(IslandVisualMetrics.donutMaxSegments, 6, "arc: maxSegments 6, contando Otros")
    expectEq(IslandVisualMetrics.donutSweepLead, 0.04, "arc: el primer borde sale 40 ms tarde")
    expectEq(IslandVisualMetrics.donutSweepStep, 0.035, "arc: stagger.item 0.035")
    // Arc writes its springs as visualDuration + bounce; SwiftUI's response is
    // visualDuration * 1.2 and the damping fraction is 1 - bounce.
    expectEq(IslandVisualMetrics.donutReveal, MotionSpring(response: 0.864, damping: 1), "arc: reveal 0.72 s sin rebote")
    expectEq(IslandVisualMetrics.donutSettle, MotionSpring(response: 0.6, damping: 1), "arc: settle 0.5 s sin rebote")
    expectEq(IslandVisualMetrics.donutCount, MotionSpring(response: 0.48, damping: 1), "arc: el conteo 0.4 s sin rebote")
    for spring in [IslandVisualMetrics.donutReveal, IslandVisualMetrics.donutSettle, IslandVisualMetrics.donutCount] {
        expectEq(spring.overshoot, 0, "M4: los resortes del anillo no rebotan")
    }
}

// MARK: - Grouping and arcs

@Test @MainActor func islandDonutLayoutTests() {
    testSmallPartsJoinOtherOnlyWhenTwoQualify()
    testOtherCapsTheSegmentCount()
    testSlicesComeFromTheBlock()
    testArcsTileTheRingClockwiseFromTheTop()
    testALeavingSegmentClosesWhereItSat()
    testColoursFollowTheKeyAcrossDatasets()
    testSharesReadLikeArc()
    testTheReadoutCountsInTheTargetsSteps()
    testTheSectorStaysInsideTheRing()
    testALabelNamedLikeOtherStaysItsOwnSegment()
    testVisibleSegmentsNeverShareAColour()
    testTheTrackWaitsForTheArcsToClose()
    testATinyCanvasNeverInvertsTheRing()
    testGroupingRows()
    testReadoutRows()
    testWhenTheRingMoves()
}

@MainActor func testSmallPartsJoinOtherOnlyWhenTwoQualify() {
    let grouped = DonutLayout.slices(labels: ["a", "b", "c", "d", "e"], values: [50, 40, 4, 3, 3])
    expectEq(names(grouped), ["a", "b", "c", "OTHER"], "arc: d y e (<4 %) se juntan en Otros")
    expectEq(grouped.last?.value, 6, "arc: Otros suma sus partes")
    expectEq(grouped.last?.members.map(\.label), ["d", "e"], "arc: Otros recuerda quién lo forma")
    let single = DonutLayout.slices(labels: ["a", "b", "c"], values: [60, 38, 2])
    expectEq(names(single), ["a", "b", "c"], "arc: agrupar una sola parte la esconde por nada")
    let dropped = DonutLayout.slices(labels: ["a", "b", "c"], values: [5, 0, -2])
    expectEq(names(dropped), ["a"], "arc: ceros y negativos no dibujan")
    expect(DonutLayout.slices(labels: ["a"], values: [0]).isEmpty, "arc: sin total no hay segmentos")
    let broken = DonutLayout.slices(labels: ["a", "b"], values: [.nan, 3])
    expectEq(names(broken), ["b"], "un valor no finito no entra al anillo")
}

@MainActor func testOtherCapsTheSegmentCount() {
    let labels = (1 ... 9).map { "p\($0)" }
    let slices = DonutLayout.slices(labels: labels, values: [20, 19, 18, 17, 16, 5, 5, 5, 5])
    expectEq(slices.count, 6, "arc: seis segmentos como máximo, contando Otros")
    expectEq(names(slices), ["p1", "p2", "p3", "p4", "p5", "OTHER"],
             "arc: se quedan los cinco mayores en su orden de datos")
    let ties = DonutLayout.slices(labels: (1 ... 8).map { "t\($0)" }, values: Array(repeating: 10, count: 8))
    expectEq(names(ties.prefix(5)), ["t1", "t2", "t3", "t4", "t5"], "un empate se resuelve por orden de datos")
}

@MainActor func testSlicesComeFromTheBlock() {
    let slices = DonutLayout.slices(donut(["Web", "Web", ""], [1, 2, 3]))
    expectEq(names(slices), ["Web", "Web (2)", "3"], "la clave es la etiqueta única que ya oye VoiceOver")
    let ragged = DonutLayout.slices(donut(["a", "b"], [1]))
    expectEq(names(ragged), ["a"], "un largo desigual no revienta")
    expect(DonutLayout.slices(ChartBlock(kind: .donut, labels: ["a"], series: [])).isEmpty, "sin serie no hay anillo")
}

@MainActor func testArcsTileTheRingClockwiseFromTheTop() {
    let arcs = DonutLayout.arcs(DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 25, 25]))
    expectEq(arcs[k("a")], .init(start: 0, end: 0.5), "arc: el primero sale de las 12")
    expectEq(arcs[k("b")], .init(start: 0.5, end: 0.75), "arc: el siguiente sigue donde acaba el anterior")
    expectEq(arcs[k("c")], .init(start: 0.75, end: 1), "arc: el último cierra la vuelta")
    expect(DonutLayout.arcs([]).isEmpty, "vacío no divide por cero")
}

@MainActor func testALeavingSegmentClosesWhereItSat() {
    let before = DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 25, 25])
    let after = DonutLayout.slices(labels: ["a", "c", "d"], values: [50, 25, 25])
    let drawn = DonutLayout.drawn(previous: before, next: after)
    expectEq(names(drawn), ["a", "b", "c", "d"], "arc: b sigue dibujado tras a mientras se cierra")
    expectEq(drawn[1].value, 0, "arc: el que se va vale cero")
    let targets = DonutLayout.targets(drawn: drawn, next: after)
    expectEq(targets[k("b")], .init(start: 0.5, end: 0.5), "arc: b se cierra a un punto donde estaba")
    expectEq(targets[k("c")], .init(start: 0.5, end: 0.75), "arc: el resto se redistribuye")
    let headless = DonutLayout.drawn(previous: before, next: DonutLayout.slices(labels: ["c"], values: [1]))
    expectEq(names(headless), ["a", "b", "c"], "sin vecino previo que sobreviva, se queda al principio")
    expectEq(DonutLayout.targets(drawn: headless, next: [])[k("a")], .init(start: 0, end: 0),
             "un anillo que se vacía cierra todo hacia las 12")
}

@MainActor func testColoursFollowTheKeyAcrossDatasets() {
    let first = DonutLayout.palette([:], keys: ["a", "b", "c"])
    expectEq(first, ["a": 0, "b": 1, "c": 2], "arc: en el primer dataset, el color sigue el orden")
    let second = DonutLayout.palette(first, keys: ["c", "d", "a", DonutLayout.otherKey])
    expectEq(second["c"], 2, "arc: c conserva su color")
    expectEq(second["a"], 0, "arc: a conserva su color")
    expectEq(second["d"], 1, "una clave nueva toma el color libre más bajo entre los que se ven")
    expect(second[DonutLayout.otherKey] == nil, "Otros no gasta un color de serie")
    let other = DonutLayout.colorIndex(DonutLayout.otherKey, palette: second)
    expectEq(other, IslandChartInk.series.count - 1, "arc: Otros es el neutro más quieto de la paleta")
    expectEq(IslandChartInk.series[other].hex, Neutral.n400.hex, "Otros es el gris de la paleta")
    let far = DonutLayout.colorIndex("x", palette: ["x": IslandChartInk.series.count - 1])
    expect(far != other, "una serie nunca toma el gris de Otros")
    expectEq(DonutLayout.colorIndex("nadie", palette: [:]), 0, "una clave sin asignar no revienta")
}

@MainActor func testSharesReadLikeArc() {
    expectEq(DonutLayout.shareText(0.42), "42%", "arc: porcentaje entero")
    expectEq(DonutLayout.shareText(0.004), "<1%", "arc: lo diminuto no dice 0 %")
    expectEq(DonutLayout.shareText(0), "0%", "cero es cero")
    expectEq(DonutLayout.shareText(1), "100%", "el todo")
}

@MainActor func testTheReadoutCountsInTheTargetsSteps() {
    expectEq(DonutLayout.readout(41.6, target: 100), "42", "arc: un total entero cuenta en pasos enteros")
    expectEq(DonutLayout.readout(12.345, target: 46.5), "12.3", "con los decimales del destino")
    expectEq(DonutLayout.readout(46.5, target: 46.5), "46.5", "en reposo dice el destino exacto")
    expectEq(DonutLayout.readout(0.123456, target: 0.25), "0.12", "nunca más de dos decimales")
}

@MainActor func testTheSectorStaysInsideTheRing() {
    let center = CGPoint(x: 104, y: 104)
    let half = DonutLayout.sector(center: center, outer: 97, inner: 73, start: 0, end: 0.5, gap: 3, corner: 4)
    let box = half.boundingRect
    expect(box.minX >= 104 - 0.5 && box.maxX <= 104 + 97 + 0.5, "media vuelta a la derecha, dentro del anillo — \(box)")
    expect(box.minY >= 104 - 97 - 0.5 && box.maxY <= 104 + 97 + 0.5, "de las 12 a las 6 — \(box)")
    expect(DonutLayout.sector(center: center, outer: 97, inner: 73, start: 0.3, end: 0.3, gap: 3, corner: 4).isEmpty,
           "arc: un segmento cerrado no dibuja")
    let whole = DonutLayout.sector(center: center, outer: 97, inner: 73, start: 0, end: 1, gap: 3, corner: 4)
    expect(abs(whole.boundingRect.width - 194) < 0.5, "arc: la vuelta entera es un anillo sin hueco")
    expect(!whole.contains(center, eoFill: true), "el centro del anillo queda vacío")
    let sliver = DonutLayout.sector(center: center, outer: 97, inner: 73, start: 0, end: 0.004, gap: 3, corner: 4)
    expect(sliver.boundingRect.isNull || sliver.boundingRect.width.isFinite, "un segmento finísimo no rompe")
    expectEq(DonutLayout.fade(outer: 97, start: 0, end: 0.5, gap: 3), 1, "arc: un segmento ancho se ve entero")
    expectEq(DonutLayout.fade(outer: 97, start: 0, end: 0.001, gap: 3), 0, "arc: uno de un pelo se desvanece en vez de dibujar una raya")
    expectEq(DonutLayout.fade(outer: 97, start: 0, end: 1, gap: 3), 1, "la vuelta entera se ve")
}

// MARK: - Motion

@Test @MainActor func islandDonutMotionTests() {
    testTheSpringStartsWhereItIsAndLandsOnTarget()
    testARetargetKeepsTheVelocity()
    testTheFirstSweepLeavesTheTopTogether()
    testNewDataMorphsFromWhereTheArcsAre()
    testReducedMotionJumpsToTheEnd()
    testTheTotalCountsToTheNewValue()
    testDatasetChangesKeepTheRingWhole()
    testTheSettleClockIsHonest()
    testTheSweepStaggersEachTrailingEdge()
}

@MainActor func testTheSpringStartsWhereItIsAndLandsOnTarget() {
    let channel = DonutSpring.resting(0).retargeted(to: 1, at: 10, spring: IslandVisualMetrics.donutSettle)
    expect(near(channel.value(at: 10), 0), "arranca donde estaba")
    let mid = channel.value(at: 10.2)
    expect(mid > 0 && mid < 1, "a medio camino — \(mid)")
    expectEq(channel.value(at: 13), 1, "en reposo dice el destino exacto")
    expect(channel.isSettled(at: 13), "y se declara en reposo")
    expect(!channel.isSettled(at: 10.1), "no antes")
    let delayed = DonutSpring.resting(0).retargeted(to: 1, at: 0, spring: IslandVisualMetrics.donutSettle, delay: 0.5)
    expectEq(delayed.value(at: 0.4), 0, "arc: con retraso espera quieto")
    expect(delayed.value(at: 0.7) > 0, "y después arranca")
    expect(channel.settleTime > 10 && channel.settleTime < 13, "sabe cuándo termina — \(channel.settleTime)")
}

@MainActor func testARetargetKeepsTheVelocity() {
    let spring = IslandVisualMetrics.donutSettle
    let first = DonutSpring.resting(0).retargeted(to: 1, at: 0, spring: spring)
    let then = 0.12
    let second = first.retargeted(to: 0.3, at: then, spring: spring)
    expect(near(second.value(at: then), first.value(at: then)), "arc: el nuevo destino sale desde donde está")
    expect(near(second.velocity(at: then), first.velocity(at: then), 1e-3),
           "arc: y con la velocidad que llevaba — \(second.velocity(at: then)) vs \(first.velocity(at: then))")
    expect(first.velocity(at: then) > 0, "iba en movimiento")
}

@MainActor func testTheFirstSweepLeavesTheTopTogether() {
    let slices = DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 25, 25])
    let motion = DonutMotion(slices: slices).sweeping(at: 0)
    let start = motion.arcs(at: 0)
    expect(start.allSatisfy { $0.arc.start == 0 && $0.arc.end == 0 }, "arc: todos salen de las 12")
    let early = motion.arcs(at: 0.05)
    expect(early[0].arc.end > 0 && early[1].arc.end == 0, "arc: cada borde va un tiempo detrás del anterior")
    expectEq(early[1].arc.width, 0, "un borde que todavía no sale no dibuja")
    expectEq(DonutLayout.sweepDelay(index: 0), 0.04, "arc: el primer borde sale a los 40 ms")
    expect(near(DonutLayout.sweepDelay(index: 2), 0.04 + 2 * 0.035), "arc: cada uno 35 ms detrás")
    let end = motion.arcs(at: 5)
    expectEq(end.map(\.arc), [.init(start: 0, end: 0.5), .init(start: 0.5, end: 0.75), .init(start: 0.75, end: 1)],
             "arc: y terminan en su sitio")
    expect(motion.isSettled(at: 5) && !motion.isSettled(at: 0.1), "el barrido termina")
}

@MainActor func testNewDataMorphsFromWhereTheArcsAre() {
    let a = DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 25, 25])
    let b = DonutLayout.slices(labels: ["a", "c", "d"], values: [25, 25, 50])
    let rest = DonutMotion(slices: a)
    let moving = rest.updated(to: b, at: 100, reduced: false)
    let now = moving.arcs(at: 100)
    expectEq(now.map(\.slice.label), ["a", "b", "c", "d"], "arc: el orden se conserva, nadie se remonta")
    expectEq(now.first { $0.slice.label == "a" }?.arc, .init(start: 0, end: 0.5), "arc: sale desde donde está en pantalla")
    let d = now.first { $0.slice.label == "d" }?.arc
    expectEq(d?.start, d?.end, "arc: el nuevo abre desde el borde del anterior")
    expectEq(d?.start, 1, "arc: el borde de c, ahora mismo")
    let settled = moving.arcs(at: 105)
    expectEq(settled.first { $0.slice.label == "b" }?.arc.width, 0, "arc: b se cerró")
    expectEq(settled.first { $0.slice.label == "d" }?.arc, .init(start: 0.5, end: 1), "arc: d ocupa su parte")
    let next = moving.updated(to: b, at: 106, reduced: false)
    expectEq(next.arcs(at: 106).map(\.slice.label), ["a", "c", "d"], "arc: el que ya se cerró sale de la lista")
    let interrupted = moving.updated(to: a, at: 100.1, reduced: false)
    let aArc = interrupted.arcs(at: 100.1).first { $0.slice.label == "a" }?.arc
    let movingArc = moving.arcs(at: 100.1).first { $0.slice.label == "a" }?.arc
    expectEq(aArc, movingArc, "arc: un cambio interrumpido sigue desde donde iba")
}

@MainActor func testReducedMotionJumpsToTheEnd() {
    let a = DonutLayout.slices(labels: ["a", "b"], values: [50, 50])
    let b = DonutLayout.slices(labels: ["a"], values: [1])
    let jumped = DonutMotion(slices: a).updated(to: b, at: 0, reduced: true)
    expectEq(jumped.arcs(at: 0).map(\.slice.label), ["a"], "reduce motion: el que se va desaparece ya")
    expectEq(jumped.arcs(at: 0).first?.arc, .init(start: 0, end: 1), "reduce motion: los arcos saltan a su final")
    expect(jumped.isSettled(at: 0), "reduce motion: nada queda moviéndose")
    expectEq(jumped.total(at: 0), 1, "reduce motion: el total salta")
}

@MainActor func testTheTotalCountsToTheNewValue() {
    let a = DonutLayout.slices(labels: ["a"], values: [100])
    let b = DonutLayout.slices(labels: ["a"], values: [200])
    let motion = DonutMotion(slices: a)
    expectEq(motion.total(at: 0), 100, "arc: el total arranca en su valor, sin contar")
    let counting = motion.updated(to: b, at: 0, reduced: false)
    let mid = counting.total(at: 0.15)
    expect(mid > 100 && mid < 200, "arc: el total cuenta hacia el nuevo — \(mid)")
    expectEq(counting.total(at: 5), 200, "y llega")
}

// MARK: - Legend and words

@Test @MainActor func islandDonutWordsTests() async {
    await pinLanguage(.en) { testTheDonutLegendMatchesTheSegments() }
    await pinLanguage(.en) { testTheSummaryListsEveryPartInEnglish() }
    await pinLanguage(.es) { testTheSummaryListsEveryPartInSpanish() }
    await pinLanguage(.en) { testTheDonutRendersWithoutCrashing() }
    await pinLanguage(.en) { testAStillRenderShowsTheFinishedRing() }
    await pinLanguage(.en) { testTheSummaryRowsInEnglish() }
    await pinLanguage(.es) { testTheSummaryRowsInSpanish() }
}

/// The 16m-5a gallery caught it: a still render runs onAppear, so it drew
/// the first instant of the sweep, an empty ring.
@MainActor func testAStillRenderShowsTheFinishedRing() {
    func alphaOnTheBand(sweeps: Bool) -> CGFloat {
        let ring = IslandDonutRing(block: donut(["a"], [1]), palette: [:])
            .environment(\.islandChartSweeps, sweeps)
            .frame(width: IslandVisualMetrics.donutSize, height: IslandVisualMetrics.donutSize)
        let renderer = ImageRenderer(content: ring)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return -1 }
        let rep = NSBitmapImageRep(cgImage: image)
        let band = Int(IslandVisualMetrics.donutMargin + IslandVisualMetrics.donutThickness / 2)
        return rep.colorAt(x: Int(IslandVisualMetrics.donutSize / 2), y: band)?.alphaComponent ?? -1
    }
    expect(alphaOnTheBand(sweeps: false) > 0.9, "una foto fija pinta el anillo terminado")
    expect(alphaOnTheBand(sweeps: true) < 0.1, "en vivo arranca vacío: el barrido sale de las 12")
}

@MainActor func testTheDonutLegendMatchesTheSegments() {
    let block = donut(["Web", "Ads", "Mail", "Fax", "Pager"], [50, 40, 4, 3, 3])
    let legend = IslandChartData.legend(block)
    expectEq(legend.map(\.name), ["Web", "Ads", "Mail", "Other"], "la leyenda dice los segmentos que se ven")
    expectEq(legend.map(\.colorIndex), [0, 1, 2, IslandChartInk.series.count - 1], "cada punto del color de su segmento")
    let kept = IslandChartData.legend(block, palette: [k("Ads"): 4, k("Web"): 0, k("Mail"): 5])
    expectEq(kept.map(\.colorIndex).prefix(3), [0, 4, 5], "arc: la leyenda sigue el color estable de cada clave")
    let pie = ChartBlock(kind: .pie, labels: ["a", "b", "c"], series: [.init(values: [90, 5, 5])])
    expectEq(IslandChartData.legend(pie).map(\.name), ["a", "b", "c"], "el pastel no agrupa: no cambió")
}

@MainActor func testTheSummaryListsEveryPartInEnglish() {
    let text = IslandChartSpeech.summary(donut(["Web", "Ads", "Mail", "Fax", "Pager"], [50, 40, 4, 3, 3], unit: "leads"))
    for part in ["Donut chart", "Total 100 leads", "Web, 50 leads, 50%", "Ads, 40 leads, 40%",
                 "Other, 6 leads, 6%", "includes Fax and Pager"] {
        expect(text.contains(part), "arc: el resumen dice «\(part)» — \(text)")
    }
}

@MainActor func testTheSummaryListsEveryPartInSpanish() {
    let text = IslandChartSpeech.summary(donut(["a", "b", "c", "d"], [91, 3, 3, 3]))
    for part in ["Gráfica de dona", "Total 100", "a, 91, 91%", "Otros, 9, 9%", "incluye b, c y d"] {
        expect(text.contains(part), "arc: el resumen en español dice «\(part)» — \(text)")
    }
    let pie = IslandChartSpeech.summary(ChartBlock(kind: .pie, labels: ["a", "b"], series: [.init(values: [1, 2])]))
    expect(!pie.contains("Total"), "el pastel conserva su resumen — \(pie)")
}

@MainActor func testTheDonutRendersWithoutCrashing() {
    for block in [donut(["a", "b", "c"], [3, 2, 1]), donut(["a"], [0]), donut(["a", "b"], [1])] {
        let renderer = ImageRenderer(content: IslandChartVisual(block: block).frame(width: 548))
        expect(renderer.nsImage != nil, "la dona rinde sin crash — \(block.labels)")
    }
}

// MARK: - Review fixes

/// Security + code review: a model could label a part "__other" and get the
/// grouping key, merging two segments into one colour and one arc.
@MainActor func testALabelNamedLikeOtherStaysItsOwnSegment() {
    let block = donut(["__other", "other", "b", "c", "d"], [50, 40, 3, 3, 4])
    let slices = DonutLayout.slices(block)
    expectEq(slices.count, 4, "una etiqueta «__other» y Otros son dos segmentos — \(names(slices))")
    expectEq(Set(slices.map(\.key)).count, slices.count, "claves distintas")
    expectEq(slices.filter(\.isOther).count, 1, "solo el agrupado es Otros")
    let arcs = DonutLayout.arcs(slices)
    expectEq(arcs.count, slices.count, "un arco por segmento")
    let palette = DonutLayout.palette([:], keys: slices.map(\.key))
    let colours = slices.map { DonutLayout.colorIndex($0.key, palette: palette) }
    expectEq(Set(colours).count, colours.count, "cada segmento su color — \(colours)")
    let legend = IslandChartData.legend(block)
    expectEq(legend.map(\.colorIndex), colours, "la leyenda dice los colores del anillo")
    expectEq(legend.map(\.name).prefix(2), ["__other", "other"], "y sus nombres")
}

/// Code review: past seven keys seen, two visible segments shared a colour.
@MainActor func testVisibleSegmentsNeverShareAColour() {
    var palette: [String: Int] = [:]
    let datasets = (0 ..< 6).map { start in (0 ..< 5).map { "k\(start * 3 + $0)" } }
    for keys in datasets {
        palette = DonutLayout.palette(palette, keys: keys)
        let shown = keys.map { DonutLayout.colorIndex($0, palette: palette) }
        expectEq(Set(shown).count, keys.count, "sin colores repetidos en \(keys) — \(shown)")
        expect(shown.allSatisfy { $0 < IslandChartInk.series.count - 1 }, "ninguna serie toma el gris de Otros")
    }
    let first = DonutLayout.palette([:], keys: ["a", "b", "c"])
    let without = DonutLayout.palette(first, keys: ["a", "c"])
    let back = DonutLayout.palette(without, keys: ["a", "b", "c"])
    expectEq(back["b"], first["b"], "una clave que vuelve conserva su color si sigue libre")
    let taken = DonutLayout.palette(DonutLayout.palette(without, keys: ["a", "c", "d"]), keys: ["a", "b", "c", "d"])
    let shown = ["a", "b", "c", "d"].map { DonutLayout.colorIndex($0, palette: taken) }
    expectEq(Set(shown).count, 4, "si su color ya lo usa otra, toma uno libre — \(shown)")
    expectEq(taken["a"], 0, "las que se quedan no cambian")
}

/// Code review: keyed on the final total, the empty track appeared while the
/// last arcs were still closing.
@MainActor func testTheTrackWaitsForTheArcsToClose() {
    let open = [DonutLayout.Arc(start: 0, end: 0.2)]
    let closed = [DonutLayout.Arc(start: 0.3, end: 0.3)]
    expect(!DonutLayout.showsTrack(open, finalTotal: 0), "mientras un arco se cierra no hay pista")
    expect(DonutLayout.showsTrack(closed, finalTotal: 0), "cerrados todos, la pista dice que el todo es cero")
    expect(DonutLayout.showsTrack([], finalTotal: 0), "sin arcos, pista")
    expect(!DonutLayout.showsTrack(closed, finalTotal: 10), "el primer instante del barrido no destella la pista")
    let a = DonutLayout.slices(labels: ["a"], values: [1])
    let emptying = DonutMotion(slices: a).updated(to: [], at: 0, reduced: false)
    expect(!DonutLayout.showsTrack(emptying.arcs(at: 0.05).map(\.arc), finalTotal: emptying.finalTotal),
           "datos en cero: el arco se cierra antes de la pista")
    expect(DonutLayout.showsTrack(emptying.arcs(at: 5).map(\.arc), finalTotal: emptying.finalTotal), "y luego sí")
}

/// Code review: a canvas smaller than the ring's thickness put the hole outside the ring.
@MainActor func testATinyCanvasNeverInvertsTheRing() {
    for diameter: CGFloat in [0, 4, 10, 20, 30, 208, 400] {
        let radii = DonutLayout.radii(diameter: diameter)
        expect(radii.inner <= radii.outer && radii.inner >= 0, "lienzo \(diameter): \(radii)")
    }
    expectEq(DonutLayout.radii(diameter: 208).outer, 97, "arc: 208/2 - 7")
    expectEq(DonutLayout.radii(diameter: 208).inner, 73, "arc: 97 - 24")
    expectEq(DonutLayout.radii(diameter: 400).outer, 97, "nunca más grande que 208")
    let inverted = DonutLayout.sector(center: .zero, outer: 5, inner: 8, start: 0, end: 0.5, gap: 3, corner: 4)
    expect(inverted.isEmpty, "un anillo invertido no dibuja")
}

@MainActor func testGroupingRows() {
    expectEq(names(DonutLayout.slices(labels: ["a", "b", "c"], values: [.infinity, -.infinity, 2])), ["c"],
             "±inf no entra al anillo")
    expect(DonutLayout.slices(labels: ["a", "b"], values: [-1, -2]).isEmpty, "todo negativo es vacío")
    let six = DonutLayout.slices(labels: (1 ... 6).map { "s\($0)" }, values: [30, 20, 20, 10, 10, 10])
    expectEq(names(six), (1 ... 6).map { "s\($0)" }, "arc: seis partes sobre el 4 % son seis segmentos, sin Otros")
    let seven = DonutLayout.slices(labels: (1 ... 7).map { "s\($0)" }, values: [30, 20, 20, 10, 10, 5, 5])
    expectEq(names(seven), ["s1", "s2", "s3", "s4", "s5", "OTHER"], "arc: siete son cinco y Otros")
    let edge = DonutLayout.slices(labels: ["a", "b", "c", "d"], values: [8_802, 399, 399, 400])
    expectEq(names(edge), ["a", "d", "OTHER"], "3,99 % se agrupa, 4,00 % no")
    let one = DonutLayout.slices(labels: ["solo"], values: [7])
    expectEq(DonutLayout.arcs(one)[k("solo")], .init(start: 0, end: 1), "un solo segmento es la vuelta entera")
}

@MainActor func testReadoutRows() {
    expectEq(DonutLayout.readout(1_234_567, target: 1_234_567), "1234567", "en reposo, como lo dice ChartBlock")
    expectEq(DonutLayout.readout(1_234_566.6, target: 1_234_567), "1234567", "contando, en pasos enteros")
    expectEq(DonutLayout.readout(1e9, target: 1e9), "1000000000", "mil millones sin notación científica")
    expectEq(DonutLayout.readout(0.3, target: 0), "0", "hacia cero cuenta en enteros")
    expectEq(DonutLayout.readout(999.5, target: 1000), "1000", "999,5 redondea hacia arriba")
    expectEq(DonutLayout.readout(46.50, target: 46.50), "46.5", "sin ceros de cola")
    expectEq(DonutLayout.readout(0, target: 2.75), "0.00", "de cero a un decimal, con sus decimales")
    expectEq(DonutLayout.readout(1.234, target: 2.75), "1.23", "a medio camino")
}

@MainActor func testWhenTheRingMoves() {
    let still = DonutLayout.motionPlan(reduceMotion: false, sweeps: false)
    expect(!still.sweep && still.animate, "foto fija: sin barrido, pero un cambio de datos se mueve")
    let live = DonutLayout.motionPlan(reduceMotion: false, sweeps: true)
    expect(live.sweep && live.animate, "en vivo: barrido y movimiento")
    for sweeps in [true, false] {
        let reduced = DonutLayout.motionPlan(reduceMotion: true, sweeps: sweeps)
        expect(!reduced.sweep && !reduced.animate, "reducir movimiento: todo salta (sweeps \(sweeps))")
    }
}

/// Every sampled instant of a change: no inverted or duplicated segment,
/// neighbours never overlap unless the order itself changed, and it lands
/// exactly on the new layout.
@MainActor private func checkMorph(_ motion: DonutMotion, from: Double, to next: [DonutLayout.Slice],
                                   ordered: Bool, _ name: String) {
    var t = from
    while t <= from + 3 {
        let frames = motion.arcs(at: t)
        expectEq(Set(frames.map(\.slice.key)).count, frames.count, "\(name): sin claves repetidas a t=\(t)")
        for frame in frames {
            expect(frame.arc.start <= frame.arc.end + 1e-9, "\(name): \(frame.slice.label) invertido a t=\(t)")
        }
        if ordered {
            for (prev, next) in zip(frames, frames.dropFirst()) {
                expect(next.arc.start >= prev.arc.end - 1e-9, "\(name): \(prev.slice.label) pisa a \(next.slice.label) a t=\(t)")
            }
        }
        t += 1.0 / 60
    }
    let goal = DonutLayout.arcs(next)
    let final = motion.arcs(at: from + 10).filter { $0.arc.width > 0 || goal[$0.slice.key] != nil }
    expectEq(Dictionary(uniqueKeysWithValues: final.map { ($0.slice.key, $0.arc) }), goal, "\(name): termina en el layout nuevo")
}

@MainActor func testDatasetChangesKeepTheRingWhole() {
    let abc = DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 30, 20])
    let cba = DonutLayout.slices(labels: ["c", "b", "a"], values: [20, 30, 50])
    let ac = DonutLayout.slices(labels: ["a", "c"], values: [50, 20])
    // Arc's own rule: the ring follows the data's order, so a reorder crosses; only inversion is checked.
    checkMorph(DonutMotion(slices: abc).updated(to: cba, at: 0, reduced: false), from: 0, to: cba, ordered: false, "reordenar")
    let closing = DonutMotion(slices: abc).updated(to: ac, at: 0, reduced: false)
    let reopened = closing.updated(to: abc, at: 0.1, reduced: false)
    expectEq(reopened.arcs(at: 0.1).filter { $0.slice.label == "b" }.count, 1, "b vuelve sin duplicarse")
    checkMorph(reopened, from: 0.1, to: abc, ordered: true, "quitar y volver a poner")
    let emptied = DonutMotion(slices: abc).updated(to: [], at: 0, reduced: false)
    checkMorph(emptied, from: 0, to: [], ordered: true, "vaciar")
    let refilled = emptied.updated(to: abc, at: 5, reduced: false)
    checkMorph(refilled, from: 5, to: abc, ordered: true, "y volver a llenar")
    let during = DonutMotion(slices: abc).sweeping(at: 0).updated(to: ac, at: 0.02, reduced: false)
    let goal = DonutLayout.arcs(ac)
    let landed = during.arcs(at: 10).filter { goal[$0.slice.key] != nil }
    expectEq(Dictionary(uniqueKeysWithValues: landed.map { ($0.slice.key, $0.arc) }), goal,
             "un cambio durante el retraso del barrido termina en su sitio")
    expectEq(Set(during.arcs(at: 0.05).map(\.slice.key)).count, during.arcs(at: 0.05).count, "sin duplicados durante el barrido")
}

@MainActor func testTheSettleClockIsHonest() {
    let a = DonutLayout.slices(labels: ["a", "b"], values: [50, 50])
    let b = DonutLayout.slices(labels: ["a", "b", "c"], values: [20, 30, 50])
    let moving = DonutMotion(slices: a).updated(to: b, at: 0, reduced: false)
    expect(moving.isSettled(at: moving.settleTime + 0.01), "en reposo justo después de settleTime")
    expect(!moving.isSettled(at: moving.settleTime - 0.05), "y no antes")
    let goal = DonutLayout.arcs(b)
    expectEq(Dictionary(uniqueKeysWithValues: moving.arcs(at: moving.settleTime).map { ($0.slice.key, $0.arc) }), goal,
             "en settleTime los arcos son el destino")
    let sweep = DonutMotion(slices: b).sweeping(at: 0)
    expect(sweep.settleTime >= DonutLayout.sweepDelay(index: b.count - 1) + IslandVisualMetrics.donutReveal.response,
           "el barrido no termina antes del último borde — \(sweep.settleTime)")
    let nudged = DonutSpring(origin: 0, initialVelocity: 1, target: 0, startedAt: 0, delay: 0,
                             spring: IslandVisualMetrics.donutSettle)
    expect(!nudged.isSettled(at: 0), "en su destino pero moviéndose no está en reposo")
    expect(nudged.isSettled(at: nudged.settleTime) && nudged.settleTime < 10, "y se asienta — \(nudged.settleTime)")
}

@MainActor func testTheSweepStaggersEachTrailingEdge() {
    let slices = DonutLayout.slices(labels: ["a", "b", "c"], values: [50, 25, 25])
    let motion = DonutMotion(slices: slices).sweeping(at: 0)
    for index in 0 ..< 3 {
        let delay = DonutLayout.sweepDelay(index: index)
        let before = motion.arcs(at: delay - 0.001)[index].arc
        let after = motion.arcs(at: delay + 0.01)[index].arc
        expectEq(before.end, 0, "arc: el borde \(index) espera su retraso")
        expect(after.end > 0, "arc: y sale después de él")
    }
    expectEq(motion.arcs(at: 0.03)[0].arc.start, 0, "el borde delantero del primero se queda en las 12")
    expect(motion.arcs(at: 0.03)[1].arc.start > 0, "los delanteros de los demás salen juntos sin esperar")
}

@MainActor func testTheSummaryRowsInEnglish() {
    let two = IslandChartSpeech.summary(donut(["a", "b", "c"], [94, 3, 3]))
    expect(two.contains("Other, 6, 6%, includes b and c"), "dos miembros — \(two)")
    let three = IslandChartSpeech.summary(donut(["a", "b", "c", "d"], [91, 3, 3, 3]))
    expect(three.contains("includes b, c and d"), "tres miembros — \(three)")
    let tiny = IslandChartSpeech.summary(donut(["a", "b"], [99.5, 0.5]))
    expect(tiny.contains("b, 0.5, <1%"), "un pelo se dice <1% — \(tiny)")
    let decimals = IslandChartSpeech.summary(donut(["a", "b"], [1.5, 2.25]))
    expect(decimals.contains("Total 3.75"), "total con decimales — \(decimals)")
    let single = IslandChartSpeech.summary(donut(["solo"], [5]))
    expect(single.contains("solo, 5, 100%"), "un solo segmento — \(single)")
    let empty = IslandChartSpeech.summary(donut(["a"], [0]))
    expect(!empty.contains("Total") && empty.contains("Donut chart"), "vacía: el tipo, sin total — \(empty)")
    let dup = IslandChartSpeech.summary(donut(["Web", "Web"], [1, 1]))
    expect(dup.contains("Web, 1, 50%") && dup.contains("Web (2), 1, 50%"), "etiquetas repetidas — \(dup)")
}

@MainActor func testTheSummaryRowsInSpanish() {
    let two = IslandChartSpeech.summary(donut(["a", "b", "c"], [94, 3, 3], unit: "leads"))
    expect(two.contains("Otros, 6 leads, 6%, incluye b y c"), "dos miembros con unidad — \(two)")
    expect(two.contains("Total 100 leads"), "unidad en español — \(two)")
}
