import CompanionCore
import Foundation
import Testing

/// The component each block resolves to, by name. A table test reads better
/// as "parts(2) -> splitBar" than as a pile of associated values.
private func kind(_ render: PresentRender) -> String {
    switch render {
    case .prose: "prose"
    case .notice: "notice"
    case .sortableTable: "sortableTable"
    case .filterableTable: "filterableTable"
    case .slope: "slope"
    case .donut: "donut"
    case .splitBar: "splitBar"
    case .treemap: "treemap"
    case .line: "line"
    case .brush: "brush"
    case .streamgraph: "streamgraph"
    case .bar: "bar"
    case .metrics: "metrics"
    case .timeline: "timeline"
    case .countdown: "countdown"
    case .places: "places"
    case .treeView: "treeView"
    case .chips: "chips"
    case .code: "code"
    case .sources: "sources"
    }
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func parts(_ count: Int) -> PresentBlock {
    .partsOfWhole(PresentParts(
        title: nil,
        parts: (0..<count).map { PresentPart(label: "p\($0)", value: 1) }))
}

private func series(labels: Int, lines: Int = 1, stacked: Bool = false) -> PresentBlock {
    .timeSeries(PresentSeries(
        title: nil, unit: nil,
        labels: (0..<labels).map { "l\($0)" },
        series: (0..<lines).map { PresentSeries.Line(name: "s\($0)", values: Array(repeating: 1, count: labels)) },
        stacked: stacked))
}

private func table(rows: Int) -> PresentTable {
    PresentTable(title: nil, columns: ["a"], rows: Array(repeating: [.text("x")], count: rows))
}

private func metric(trend: [Double]? = nil, target: Double? = nil) -> PresentBlock {
    .metrics(PresentMetrics(title: nil, items: [
        PresentMetric(label: "m", value: 3, trend: trend, target: target),
    ]))
}

@Test func partsOfWholeResolvesByCount() {
    let expected: [(Int, String)] = [
        (1, "donut"), (2, "splitBar"), (3, "donut"), (6, "donut"), (7, "treemap"), (20, "treemap"),
    ]
    for (count, component) in expected {
        #expect(kind(BlockResolver.resolve(parts(count), now: now)) == component, "parts(\(count))")
    }
}

@Test func timeSeriesResolvesByShapeAndStacking() {
    let cases: [(PresentBlock, String)] = [
        (series(labels: 12), "line"),
        (series(labels: 90), "line"),
        (series(labels: 91), "brush"),
        (series(labels: 12, lines: 3, stacked: true), "streamgraph"),
        // Stacking one series is a line: there is nothing to stack against.
        (series(labels: 12, lines: 1, stacked: true), "line"),
        // Stacked but long still goes to the stream graph, which takes the series.
        (series(labels: 120, lines: 2, stacked: true), "streamgraph"),
    ]
    for (block, component) in cases {
        #expect(kind(BlockResolver.resolve(block, now: now)) == component)
    }
}

@Test func rankingIsABarUntilItIsAList() {
    func ranking(_ count: Int) -> PresentBlock {
        .ranking(PresentRanking(
            title: nil, unit: "ms",
            items: (0..<count).map { PresentPart(label: "i\($0)", value: 1) }))
    }
    #expect(kind(BlockResolver.resolve(ranking(20), now: now)) == "bar")
    // Past the bar limit the ranking is a table, and a table of 21 rows filters.
    #expect(kind(BlockResolver.resolve(ranking(21), now: now)) == "filterableTable")
}

@Test func metricVisualFollowsTheStrongestSignal() {
    func visual(_ block: PresentBlock) -> PresentTile.Visual? {
        guard case .metrics(_, let tiles) = BlockResolver.resolve(block, now: now) else { return nil }
        return tiles.first?.visual
    }
    #expect(visual(metric(trend: [1, 2, 3])) == .sparkline)
    #expect(visual(metric(target: 10)) == .gauge)
    // A history and a goal together: the trend is what the tile can show best.
    #expect(visual(metric(trend: [1, 2], target: 10)) == .sparkline)
    #expect(visual(metric()) == .counter)
}

@Test func tablesFilterPastTwelveRows() {
    #expect(kind(BlockResolver.resolve(.table(table(rows: 12)), now: now)) == "sortableTable")
    #expect(kind(BlockResolver.resolve(.table(table(rows: 13)), now: now)) == "filterableTable")
}

@Test func filesAreATreeOnlyWhenSomeFolderIsExpanded() {
    let flat = PresentFiles(title: nil, items: [PresentFile(name: "a.txt"), PresentFile(name: "b.txt")])
    let nested = PresentFiles(title: nil, items: [
        PresentFile(name: "src", children: [PresentFile(name: "main.swift")]),
    ])
    #expect(kind(BlockResolver.resolve(.files(flat), now: now)) == "chips")
    #expect(kind(BlockResolver.resolve(.files(nested), now: now)) == "treeView")
}

@Test func oneUpcomingEventIsACountdownOtherwiseATimeline() {
    let future = PresentEvent(title: "launch", startsAt: now.addingTimeInterval(3_600))
    let past = PresentEvent(title: "old", startsAt: now.addingTimeInterval(-3_600))
    let undated = PresentEvent(title: "someday")

    #expect(kind(BlockResolver.resolve(
        .events(PresentEvents(title: nil, events: [future])), now: now)) == "countdown")
    #expect(kind(BlockResolver.resolve(
        .events(PresentEvents(title: nil, events: [past])), now: now)) == "timeline")
    #expect(kind(BlockResolver.resolve(
        .events(PresentEvents(title: nil, events: [future, undated])), now: now)) == "timeline")
    #expect(kind(BlockResolver.resolve(
        .events(PresentEvents(title: nil, events: [undated])), now: now)) == "timeline")
}

@Test func codeAndSourcesResolveToTheirComponents() {
    let diff = PresentCode(title: nil, language: "swift", code: nil, before: "a", after: "b")
    #expect(kind(BlockResolver.resolve(.codeOrDiff(diff), now: now)) == "code")
    let sources = PresentSource(title: "t", url: "https://example.com")
    #expect(kind(BlockResolver.resolve(.webSources([sources]), now: now)) == "sources")
}

@Test func stepsBecomeATimelineWhereDoneIsSuccess() {
    let steps = PresentSteps(title: nil, steps: [
        PresentStep(title: "a", detail: nil, state: .done),
        PresentStep(title: "b", detail: nil, state: .current),
        PresentStep(title: "c", detail: nil, state: .todo),
    ])
    guard case .timeline(let timeline) = BlockResolver.resolve(.steps(steps), now: now) else {
        Issue.record("steps did not resolve to a timeline")
        return
    }
    #expect(timeline.events.map(\.tone) == [.success, .info, .neutral])
}

@Test func twoNumericOptionsReadAsASlopeOtherwiseATable() {
    let numeric = PresentComparison(title: nil, columns: ["a", "b"], rows: [
        PresentComparisonRow(label: "x", values: [.number(1), .number(2)]),
    ])
    let mixed = PresentComparison(title: nil, columns: ["a", "b"], rows: [
        PresentComparisonRow(label: "x", values: [.text("fast"), .number(2)]),
    ])
    let three = PresentComparison(title: nil, columns: ["a", "b", "c"], rows: [
        PresentComparisonRow(label: "x", values: [.number(1), .number(2), .number(3)]),
    ])
    #expect(kind(BlockResolver.resolve(.comparison(numeric), now: now)) == "slope")
    #expect(kind(BlockResolver.resolve(.comparison(mixed), now: now)) == "sortableTable")
    #expect(kind(BlockResolver.resolve(.comparison(three), now: now)) == "sortableTable")
}

@Test func proseAndNoticeKeepTheirOwnComponent() {
    #expect(kind(BlockResolver.resolve(.paragraph("hola"), now: now)) == "prose")
    #expect(kind(BlockResolver.resolve(.divider, now: now)) == "prose")
    let note = PresentNote(tone: .danger, title: nil, text: "falló")
    #expect(kind(BlockResolver.resolve(.notice(note), now: now)) == "notice")
}
