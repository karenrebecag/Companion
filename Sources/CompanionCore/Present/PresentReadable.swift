import Foundation

/// The words a block paints, as plain lines. Language detection and anything
/// else that reads what the reader sees use these, so the JSON a block came
/// from never does. Code bodies are left out: they are not prose.
package enum PresentReadable {
    package static func lines(_ block: PresentBlock) -> [String] {
        switch block {
        case .heading(_, let text), .paragraph(let text): [text]
        case .list(_, let items): items
        case .keyvalue(let pairs): pairs.map { "\($0.key): \($0.value)" }
        case .callout(let note), .notice(let note): optional(note.title) + [note.text]
        case .quote(let text, let source): [text] + optional(source)
        case .divider, .codeOrDiff: []
        case .table(let table): optional(table.title) + table.columns + cells(table.rows)
        case .timeSeries(let series):
            optional(series.title) + series.labels + series.series.map(\.name)
        case .partsOfWhole(let parts): optional(parts.title) + parts.parts.map(\.label)
        case .ranking(let ranking): optional(ranking.title) + ranking.items.map(\.label)
        case .metrics(let metrics):
            optional(metrics.title) + metrics.items.flatMap { [$0.label] + optional($0.delta) }
        case .timeline(let timeline): optional(timeline.title) + events(timeline.events)
        case .events(let schedule): optional(schedule.title) + events(schedule.events)
        case .places(let places):
            optional(places.title) + places.places.flatMap { [$0.name] + optional($0.address) }
        case .files(let files): optional(files.title) + files.items.flatMap(fileNames)
        case .people(let people):
            optional(people.title) + people.people.flatMap { [$0.name] + optional($0.role) }
        case .webSources(let sources): sources.map(\.title)
        case .steps(let steps):
            optional(steps.title) + steps.steps.flatMap { [$0.title] + optional($0.detail) }
        case .comparison(let comparison):
            optional(comparison.title) + comparison.columns + comparison.rows.map(\.label)
                + cells(comparison.rows.map(\.values))
        }
    }

    private static func optional(_ text: String?) -> [String] {
        text.map { [$0] } ?? []
    }

    private static func cells(_ rows: [[PresentCell]]) -> [String] {
        rows.flatMap { $0.map(\.display) }
    }

    private static func events(_ events: [PresentEvent]) -> [String] {
        events.flatMap { [$0.title] + optional($0.when) + optional($0.detail) + optional($0.place) }
    }

    private static func fileNames(_ file: PresentFile) -> [String] {
        [file.name] + (file.children ?? []).flatMap(fileNames)
    }
}
