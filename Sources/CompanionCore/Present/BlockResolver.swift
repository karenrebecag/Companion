import Foundation

/// What the chat should paint for one block: the component chosen, with the
/// data it takes. Names mirror the components of CompanionUIPro so the view
/// layer maps one to one and never decides anything itself.
package enum PresentRender: Sendable, Equatable {
    /// Prose families: heading, paragraph, list, keyvalue, callout, quote, divider.
    case prose(PresentBlock)
    case notice(PresentNote)
    case sortableTable(PresentTable)
    case filterableTable(PresentTable)
    case slope(PresentSlope)
    case donut(PresentParts)
    case splitBar(PresentParts)
    case treemap(PresentParts)
    case line(PresentSeries)
    case brush(PresentSeries)
    case streamgraph(PresentSeries)
    case bar(PresentRanking)
    case metrics(title: String?, [PresentTile])
    case timeline(PresentTimeline)
    case countdown(PresentEvent)
    case places(PresentPlaces)
    case treeView(PresentFiles)
    case chips(PresentFiles)
    case code(PresentCode)
    case sources([PresentSource])
}

/// One metric tile and the visual it carries: the same figure reads as a
/// trend, a progress against a goal, or a bare number, by what the model gave.
package struct PresentTile: Sendable, Equatable {
    package enum Visual: Sendable, Equatable {
        case sparkline, gauge, counter
    }

    package var metric: PresentMetric
    package var visual: Visual

    package init(metric: PresentMetric, visual: Visual) {
        self.metric = metric
        self.visual = visual
    }
}

/// One item of a before/after chart: the same label measured twice.
package struct PresentSlope: Sendable, Equatable {
    package struct Point: Sendable, Equatable {
        package var label: String
        package var before: Double
        package var after: Double

        package init(label: String, before: Double, after: Double) {
            self.label = label
            self.before = before
            self.after = after
        }
    }

    package var title: String?
    package var points: [Point]

    package init(title: String?, points: [Point]) {
        self.title = title
        self.points = points
    }
}

/// The deterministic step from a validated block to a component. No I/O, no
/// clock except the `now` it is handed, so every rule is a table test.
///
/// Thresholds are where a chart stops being readable, not taste: six slices
/// is what a donut can tell apart, 90 points is what a line can show before
/// the eye needs a brush, twelve rows is where a table needs a filter.
package enum BlockResolver {
    package enum Threshold {
        /// Parts of a whole: exactly two is a split bar, up to this many a donut.
        package static let donutMaxParts = 6
        /// Series past this many labels get a brush to scroll the time axis.
        package static let brushMinLabels = 90
        /// Ranking up to this many items is a bar chart; more is a table.
        package static let barMaxItems = 20
        /// Tables past this many rows gain a filter bar.
        package static let filterMinRows = 12
    }

    package static func resolve(_ block: PresentBlock, now: Date) -> PresentRender {
        switch block {
        case .heading, .paragraph, .list, .keyvalue, .quote, .divider, .callout:
            return .prose(block)
        case .notice(let note):
            return .notice(note)
        case .table(let value):
            return table(value)
        case .timeSeries(let series):
            return timeSeries(series)
        case .partsOfWhole(let parts):
            return partsOfWhole(parts)
        case .ranking(let ranking):
            return ranking.items.count <= Threshold.barMaxItems
                ? .bar(ranking) : table(rankingTable(ranking))
        case .metrics(let metrics):
            return .metrics(title: metrics.title, metrics.items.map(tile))
        case .timeline(let timeline):
            return .timeline(timeline)
        case .steps(let steps):
            return .timeline(PresentTimeline(title: steps.title, events: steps.steps.map(event)))
        case .events(let schedule):
            return events(schedule, now: now)
        case .places(let places):
            return .places(places)
        case .files(let files):
            return files.items.contains(where: hasChildren) ? .treeView(files) : .chips(files)
        case .people(let people):
            return table(peopleTable(people))
        case .codeOrDiff(let code):
            return .code(code)
        case .webSources(let sources):
            return .sources(sources)
        case .comparison(let comparison):
            return comparisonRender(comparison)
        }
    }

    package static func resolveAll(_ blocks: [PresentBlock], now: Date) -> [PresentRender] {
        blocks.map { resolve($0, now: now) }
    }

    /// A table past the filter threshold gains a filter bar; below it, a
    /// sortable table alone.
    private static func table(_ table: PresentTable) -> PresentRender {
        table.rows.count > Threshold.filterMinRows
            ? .filterableTable(table) : .sortableTable(table)
    }

    /// Stacked series that add up are a stream graph; a shared axis of many
    /// labels is a brush; everything else is a plain line.
    private static func timeSeries(_ series: PresentSeries) -> PresentRender {
        if series.stacked && series.series.count >= 2 { return .streamgraph(series) }
        if series.labels.count > Threshold.brushMinLabels { return .brush(series) }
        return .line(series)
    }

    private static func partsOfWhole(_ parts: PresentParts) -> PresentRender {
        switch parts.parts.count {
        case 2: .splitBar(parts)
        case 0...Threshold.donutMaxParts: .donut(parts)
        default: .treemap(parts)
        }
    }

    /// A tile's visual follows the strongest signal the model gave: a history
    /// draws as a sparkline before a goal draws as a gauge.
    private static func tile(_ metric: PresentMetric) -> PresentTile {
        let visual: PresentTile.Visual
        if metric.trend != nil {
            visual = .sparkline
        } else if metric.target != nil {
            visual = .gauge
        } else {
            visual = .counter
        }
        return PresentTile(metric: metric, visual: visual)
    }

    /// The deadline of one upcoming event is a countdown; a schedule of
    /// several, or a single event already past, reads as a timeline.
    private static func events(_ schedule: PresentEvents, now: Date) -> PresentRender {
        if schedule.events.count == 1,
           let only = schedule.events.first,
           let start = only.startsAt, start > now {
            return .countdown(only)
        }
        return .timeline(PresentTimeline(title: schedule.title, events: schedule.events))
    }

    private static func event(_ step: PresentStep) -> PresentEvent {
        let tone: PresentTone = switch step.state {
        case .done: .success
        case .current: .info
        case .todo: .neutral
        }
        return PresentEvent(title: step.title, detail: step.detail, tone: tone)
    }

    private static func hasChildren(_ file: PresentFile) -> Bool {
        file.children != nil
    }

    private static func rankingTable(_ ranking: PresentRanking) -> PresentTable {
        PresentTable(
            title: ranking.title,
            columns: ["", ranking.unit ?? ""],
            rows: ranking.items.map { [.text($0.label), .number($0.value)] })
    }

    private static func peopleTable(_ people: PresentPeople) -> PresentTable {
        PresentTable(
            title: people.title,
            columns: ["name", "role", "status"],
            rows: people.people.map {
                [.text($0.name), .text($0.role ?? ""), .text($0.status ?? "")]
            })
    }

    /// Two options measured on two numeric columns read as a slope; any other
    /// comparison is a table with the options as columns.
    private static func comparisonRender(_ comparison: PresentComparison) -> PresentRender {
        if comparison.columns.count == 2, let points = slopePoints(comparison) {
            return .slope(PresentSlope(title: comparison.title, points: points))
        }
        return table(PresentTable(
            title: comparison.title,
            columns: [""] + comparison.columns,
            rows: comparison.rows.map { [.text($0.label)] + $0.values }))
    }

    private static func slopePoints(_ comparison: PresentComparison) -> [PresentSlope.Point]? {
        var points: [PresentSlope.Point] = []
        for row in comparison.rows {
            guard case .number(let before) = row.values[0],
                  case .number(let after) = row.values[1]
            else { return nil }
            points.append(PresentSlope.Point(label: row.label, before: before, after: after))
        }
        return points
    }
}
