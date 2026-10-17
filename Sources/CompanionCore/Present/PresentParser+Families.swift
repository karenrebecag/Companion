import Foundation

/// One parser per family. Each returns nil when the block carries nothing it
/// can draw; a partly bad list drops its bad entries and keeps the rest, since
/// one stray row should not cost the whole table.
extension PresentParser {
    typealias Limits = PresentContract.Limits

    static func family(_ family: PresentFamily, _ dict: [String: Any]) -> PresentBlock? {
        switch family {
        case .heading: heading(dict)
        case .paragraph: text(dict, "text").map { .paragraph($0) }
        case .list: list(dict)
        case .keyvalue: keyvalue(dict)
        case .callout: note(dict, default: .info).map { .callout($0) }
        case .quote: quote(dict)
        case .divider: .divider
        case .table: table(dict).map { .table($0) }
        case .timeSeries: timeSeries(dict).map { .timeSeries($0) }
        case .partsOfWhole: parts(dict).map { .partsOfWhole($0) }
        case .ranking: ranking(dict).map { .ranking($0) }
        case .metrics: metrics(dict).map { .metrics($0) }
        case .timeline: timeline(dict).map { .timeline($0) }
        case .places: places(dict).map { .places($0) }
        case .files: files(dict).map { .files($0) }
        case .people: people(dict).map { .people($0) }
        case .events: events(dict).map { .events($0) }
        case .codeOrDiff: code(dict).map { .codeOrDiff($0) }
        case .webSources: sources(dict).map { .webSources($0) }
        case .steps: steps(dict).map { .steps($0) }
        case .comparison: comparison(dict).map { .comparison($0) }
        case .notice: note(dict, default: .warning).map { .notice($0) }
        }
    }

    private static func heading(_ dict: [String: Any]) -> PresentBlock? {
        guard let body = text(dict, "text") else { return nil }
        let level = number(dict["level"]).map { Int($0) } ?? 2
        return .heading(level: min(max(level, 1), 3), text: body)
    }

    private static func list(_ dict: [String: Any]) -> PresentBlock? {
        guard let raw = array(dict, "items") else { return nil }
        let items = bounded(raw.compactMap { ($0 as? String).flatMap(nonEmpty) }, max: Limits.maxItems)
        guard !items.isEmpty else { return nil }
        return .list(ordered: dict["ordered"] as? Bool ?? false, items: items)
    }

    private static func keyvalue(_ dict: [String: Any]) -> PresentBlock? {
        guard let raw = objects(dict, "items") else { return nil }
        let pairs: [PresentKeyValue] = raw.compactMap { item in
            guard let key = text(item, "key"), let value = scalarText(item["value"]) else { return nil }
            return PresentKeyValue(key: key, value: value)
        }
        let kept = bounded(pairs, max: Limits.maxItems)
        return kept.isEmpty ? nil : .keyvalue(kept)
    }

    private static func note(_ dict: [String: Any], default fallback: PresentTone) -> PresentNote? {
        guard let body = text(dict, "text") else { return nil }
        return PresentNote(
            tone: tone(dict, default: fallback),
            title: optionalText(dict, "title"),
            text: body)
    }

    private static func quote(_ dict: [String: Any]) -> PresentBlock? {
        guard let body = text(dict, "text") else { return nil }
        return .quote(text: body, source: optionalText(dict, "source"))
    }

    private static func table(_ dict: [String: Any]) -> PresentTable? {
        guard let columns = headers(dict, "columns"), !columns.isEmpty,
              columns.count <= Limits.maxColumns,
              let rawRows = array(dict, "rows")
        else { return nil }
        let rows: [[PresentCell]] = rawRows.compactMap { row in
            guard let cells = rowCells(row), cells.count == columns.count else { return nil }
            var out: [PresentCell] = []
            for raw in cells {
                guard let typed = cell(raw) else { return nil }
                out.append(typed)
            }
            return out
        }
        let kept = bounded(rows, max: Limits.maxRows)
        guard !kept.isEmpty else { return nil }
        return PresentTable(title: optionalText(dict, "title"), columns: columns, rows: kept)
    }

    private static func timeSeries(_ dict: [String: Any]) -> PresentSeries? {
        guard let labels = strings(dict, "labels"), !labels.isEmpty,
              labels.count <= Limits.maxSeriesPoints,
              let raw = objects(dict, "series")
        else { return nil }
        let lines: [PresentSeries.Line] = raw.compactMap { line in
            guard let name = text(line, "name"), let values = numbers(line["values"]),
                  values.count == labels.count
            else { return nil }
            return PresentSeries.Line(name: name, values: values)
        }
        let kept = bounded(lines, max: Limits.maxSeries)
        guard !kept.isEmpty else { return nil }
        return PresentSeries(
            title: optionalText(dict, "title"),
            unit: optionalText(dict, "unit"),
            labels: labels,
            series: kept,
            stacked: dict["stacked"] as? Bool ?? false)
    }

    private static func parts(_ dict: [String: Any]) -> PresentParts? {
        let parts = bounded(pairs(dict, "parts").filter { $0.value >= 0 }, max: Limits.maxParts)
        guard parts.contains(where: { $0.value > 0 }) else { return nil }
        return PresentParts(title: optionalText(dict, "title"), parts: parts)
    }

    private static func ranking(_ dict: [String: Any]) -> PresentRanking? {
        let items = bounded(pairs(dict, "items"), max: Limits.maxItems)
        guard !items.isEmpty else { return nil }
        return PresentRanking(
            title: optionalText(dict, "title"),
            unit: optionalText(dict, "unit"),
            items: items)
    }

    private static func pairs(_ dict: [String: Any], _ key: String) -> [PresentPart] {
        (objects(dict, key) ?? []).compactMap { item in
            guard let label = text(item, "label"), let value = number(item["value"]) else { return nil }
            return PresentPart(label: label, value: value)
        }
    }

    private static func metrics(_ dict: [String: Any]) -> PresentMetrics? {
        guard let raw = objects(dict, "items") else { return nil }
        let items: [PresentMetric] = raw.compactMap { item in
            guard let label = text(item, "label"), let value = number(item["value"]) else { return nil }
            return PresentMetric(
                label: label,
                value: value,
                unit: optionalText(item, "unit"),
                delta: optionalText(item, "delta"),
                trend: trend(item["trend"]),
                target: number(item["target"]))
        }
        let kept = bounded(items, max: Limits.maxItems)
        guard !kept.isEmpty else { return nil }
        return PresentMetrics(title: optionalText(dict, "title"), items: kept)
    }

    /// A sparkline needs at least two points; a longer history is cut to the
    /// most recent ones, the part a tile can show.
    private static func trend(_ value: Any?) -> [Double]? {
        guard let values = numbers(value), values.count >= 2 else { return nil }
        return Array(values.suffix(Limits.maxTrend))
    }

    private static func timeline(_ dict: [String: Any]) -> PresentTimeline? {
        let events = events(from: dict, key: "events", dateKey: "when")
        guard !events.isEmpty else { return nil }
        return PresentTimeline(title: optionalText(dict, "title"), events: events)
    }

    private static func events(_ dict: [String: Any]) -> PresentEvents? {
        let events = events(from: dict, key: "events", dateKey: "start")
        guard !events.isEmpty else { return nil }
        return PresentEvents(title: optionalText(dict, "title"), events: events)
    }

    private static func events(from dict: [String: Any], key: String, dateKey: String) -> [PresentEvent] {
        let raw = bounded(objects(dict, key) ?? [], max: Limits.maxItems)
        return raw.compactMap { item in
            guard let title = text(item, "title") else { return nil }
            let when = optionalText(item, dateKey)
            return PresentEvent(
                title: title,
                when: when,
                startsAt: isoDate(when),
                detail: optionalText(item, "detail"),
                place: optionalText(item, "place"),
                tone: tone(item, default: .neutral))
        }
    }

    private static func places(_ dict: [String: Any]) -> PresentPlaces? {
        let raw = objects(dict, "places") ?? []
        let places: [PresentPlace] = raw.compactMap { item in
            guard let name = text(item, "name"), let lat = number(item["lat"]),
                  let lng = number(item["lng"]),
                  (-90...90).contains(lat), (-180...180).contains(lng)
            else { return nil }
            // A place without a safe link still shows; only the link is dropped.
            return PresentPlace(
                name: name,
                address: optionalText(item, "address"),
                lat: lat,
                lng: lng,
                url: httpsURL(optionalText(item, "url")))
        }
        let kept = bounded(places, max: Limits.maxItems)
        guard !kept.isEmpty else { return nil }
        return PresentPlaces(title: optionalText(dict, "title"), places: kept)
    }

    private static func files(_ dict: [String: Any]) -> PresentFiles? {
        guard let raw = objects(dict, "items") else { return nil }
        let items = fileNodes(raw, depth: 1)
        guard !items.isEmpty else { return nil }
        return PresentFiles(title: optionalText(dict, "title"), items: bounded(items, max: Limits.maxItems))
    }

    private static func fileNodes(_ raw: [[String: Any]], depth: Int) -> [PresentFile] {
        raw.compactMap { item in
            guard let name = text(item, "name") else { return nil }
            var children: [PresentFile]?
            if depth < Limits.maxFileDepth, let nested = objects(item, "children") {
                children = fileNodes(nested, depth: depth + 1)
            }
            return PresentFile(
                name: name,
                size: optionalText(item, "size"),
                children: children)
        }
    }

    private static func people(_ dict: [String: Any]) -> PresentPeople? {
        let raw = objects(dict, "people") ?? []
        let people: [PresentPerson] = raw.compactMap { item in
            guard let name = text(item, "name") else { return nil }
            return PresentPerson(
                name: name,
                role: optionalText(item, "role"),
                status: optionalText(item, "status"))
        }
        let kept = bounded(people, max: Limits.maxItems)
        guard !kept.isEmpty else { return nil }
        return PresentPeople(title: optionalText(dict, "title"), people: kept)
    }

    /// Code needs either the text or both sides of a change: a lone "after"
    /// has nothing to be compared with.
    private static func code(_ dict: [String: Any]) -> PresentCode? {
        let body = optionalText(dict, "code")
        let before = optionalText(dict, "before")
        let after = optionalText(dict, "after")
        let isDiff = before != nil && after != nil
        guard body != nil || isDiff else { return nil }
        return PresentCode(
            title: optionalText(dict, "title"),
            language: optionalText(dict, "language"),
            code: isDiff ? nil : body,
            before: isDiff ? before : nil,
            after: isDiff ? after : nil)
    }

    private static func sources(_ dict: [String: Any]) -> [PresentSource]? {
        let raw = objects(dict, "sources") ?? []
        let sources: [PresentSource] = raw.compactMap { item in
            guard let url = httpsURL(optionalText(item, "url")) else { return nil }
            return PresentSource(title: optionalText(item, "title") ?? url, url: url)
        }
        let kept = bounded(sources, max: Limits.maxItems)
        return kept.isEmpty ? nil : kept
    }

    private static func steps(_ dict: [String: Any]) -> PresentSteps? {
        let raw = objects(dict, "steps") ?? []
        let steps: [PresentStep] = raw.compactMap { item in
            guard let title = text(item, "title") else { return nil }
            let state = (item["state"] as? String).flatMap { PresentStepState(rawValue: $0) } ?? .todo
            return PresentStep(title: title, detail: optionalText(item, "detail"), state: state)
        }
        let kept = bounded(steps, max: Limits.maxItems)
        guard !kept.isEmpty else { return nil }
        return PresentSteps(title: optionalText(dict, "title"), steps: kept)
    }

    /// Two options are the most a reader can weigh side by side; the parser
    /// keeps more, the resolver decides how they draw.
    /// The model often adds a header for the label column ("Criterio" over
    /// the row labels), so one more column than values is that label column,
    /// not an option.
    private static func comparison(_ dict: [String: Any]) -> PresentComparison? {
        guard let declared = headers(dict, "columns"), declared.count >= 2,
              declared.count <= Limits.maxColumns + 1,
              let raw = objects(dict, "rows")
        else { return nil }
        let (labelHeader, columns) = splitLabelHeader(declared, rows: raw)
        guard columns.count >= 2 else { return nil }
        let rows: [PresentComparisonRow] = raw.compactMap { item in
            guard let label = text(item, "label"), let values = item["values"] as? [Any],
                  values.count == columns.count
            else { return nil }
            var cells: [PresentCell] = []
            for value in values {
                guard let typed = cell(value) else { return nil }
                cells.append(typed)
            }
            return PresentComparisonRow(label: label, values: cells)
        }
        let kept = bounded(rows, max: Limits.maxRows)
        guard !kept.isEmpty else { return nil }
        return PresentComparison(
            title: optionalText(dict, "title"), labelHeader: labelHeader, columns: columns, rows: kept)
    }

    /// Takes the label-column header off when the rows carry one value fewer
    /// than the header has names; what is left are the options.
    static func splitLabelHeader(_ declared: [String], rows: [[String: Any]]) -> (label: String?, options: [String]) {
        guard let width = rows.first.flatMap({ array($0, "values")?.count }),
              declared.count == width + 1
        else { return (nil, declared) }
        return (declared[0], Array(declared.dropFirst()))
    }

    /// A row as a list of cells: an array as written, or the `{label, values}`
    /// object the comparison uses, its label first.
    static func rowCells(_ row: Any) -> [Any]? {
        if let cells = row as? [Any] { return cells }
        guard let object = row as? [String: Any], let label = text(object, "label"),
              let values = object["values"] as? [Any]
        else { return nil }
        return [label] + values
    }

    /// Column headers in order. A blank header is kept: it is the label column
    /// the model left unnamed, and dropping it would shift every value.
    static func headers(_ dict: [String: Any], _ key: String) -> [String]? {
        guard let raw = array(dict, key) else { return nil }
        return raw.map { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }

    /// Strings in an array, dropping blanks; nil when the key is not an array.
    static func strings(_ dict: [String: Any], _ key: String) -> [String]? {
        guard let raw = array(dict, key) else { return nil }
        return raw.compactMap { ($0 as? String).flatMap(nonEmpty) }
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
