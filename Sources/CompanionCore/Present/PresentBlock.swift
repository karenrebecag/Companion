import Foundation

/// One validated block of a `present` call. Every value here already passed
/// the parser: a block that could not be validated never becomes one of these
/// (it falls back to text, see PresentParser).
package enum PresentBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [String])
    case keyvalue([PresentKeyValue])
    case callout(PresentNote)
    case quote(text: String, source: String?)
    case divider
    case table(PresentTable)
    case timeSeries(PresentSeries)
    case partsOfWhole(PresentParts)
    case ranking(PresentRanking)
    case metrics(PresentMetrics)
    case timeline(PresentTimeline)
    case places(PresentPlaces)
    case files(PresentFiles)
    case people(PresentPeople)
    case events(PresentEvents)
    case codeOrDiff(PresentCode)
    case webSources([PresentSource])
    case steps(PresentSteps)
    case comparison(PresentComparison)
    case notice(PresentNote)
}

package enum PresentTone: String, Sendable, Equatable, CaseIterable {
    case neutral, info, success, warning, danger
}

package struct PresentNote: Sendable, Equatable {
    package var tone: PresentTone
    package var title: String?
    package var text: String

    package init(tone: PresentTone, title: String?, text: String) {
        self.tone = tone
        self.title = title
        self.text = text
    }
}

package struct PresentKeyValue: Sendable, Equatable {
    package var key: String
    package var value: String

    package init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// A table cell keeps its number as a number: a sortable column sorts by
/// value, and a column of "12" and "9" would otherwise sort as text.
package enum PresentCell: Sendable, Equatable {
    case text(String)
    case number(Double)

    package var display: String {
        switch self {
        case .text(let text): text
        case .number(let value): value.formatted(.number.precision(.fractionLength(0...2)))
        }
    }
}

package struct PresentTable: Sendable, Equatable {
    package var title: String?
    package var columns: [String]
    /// Every row has exactly `columns.count` cells.
    package var rows: [[PresentCell]]

    package init(title: String?, columns: [String], rows: [[PresentCell]]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}

package struct PresentSeries: Sendable, Equatable {
    package struct Line: Sendable, Equatable {
        package var name: String
        /// One value per label.
        package var values: [Double]

        package init(name: String, values: [Double]) {
            self.name = name
            self.values = values
        }
    }

    package var title: String?
    package var unit: String?
    package var labels: [String]
    package var series: [Line]
    /// The model says the series add up to a total; that is what a stream
    /// graph is for, and the only signal that separates it from a line chart.
    package var stacked: Bool

    package init(title: String?, unit: String?, labels: [String], series: [Line], stacked: Bool) {
        self.title = title
        self.unit = unit
        self.labels = labels
        self.series = series
        self.stacked = stacked
    }
}

package struct PresentPart: Sendable, Equatable {
    package var label: String
    package var value: Double

    package init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

package struct PresentParts: Sendable, Equatable {
    package var title: String?
    package var parts: [PresentPart]

    package init(title: String?, parts: [PresentPart]) {
        self.title = title
        self.parts = parts
    }
}

package struct PresentRanking: Sendable, Equatable {
    package var title: String?
    package var unit: String?
    package var items: [PresentPart]

    package init(title: String?, unit: String?, items: [PresentPart]) {
        self.title = title
        self.unit = unit
        self.items = items
    }
}

package struct PresentMetric: Sendable, Equatable {
    package var label: String
    package var value: Double
    package var unit: String?
    /// "+8 %", "−3": shown as written, never computed.
    package var delta: String?
    /// At least two finite numbers, or nil.
    package var trend: [Double]?
    package var target: Double?

    package init(
        label: String, value: Double, unit: String? = nil, delta: String? = nil,
        trend: [Double]? = nil, target: Double? = nil
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.trend = trend
        self.target = target
    }
}

package struct PresentMetrics: Sendable, Equatable {
    package var title: String?
    package var items: [PresentMetric]

    package init(title: String?, items: [PresentMetric]) {
        self.title = title
        self.items = items
    }
}

package struct PresentEvent: Sendable, Equatable {
    package var title: String
    /// The text the model wrote ("2026-10-16", "mañana 9:00"); shown as is.
    package var when: String?
    /// Parsed only from ISO 8601, so a deadline can be counted down.
    package var startsAt: Date?
    package var detail: String?
    package var place: String?
    package var tone: PresentTone

    package init(
        title: String, when: String? = nil, startsAt: Date? = nil,
        detail: String? = nil, place: String? = nil, tone: PresentTone = .neutral
    ) {
        self.title = title
        self.when = when
        self.startsAt = startsAt
        self.detail = detail
        self.place = place
        self.tone = tone
    }
}

package struct PresentTimeline: Sendable, Equatable {
    package var title: String?
    package var events: [PresentEvent]

    package init(title: String?, events: [PresentEvent]) {
        self.title = title
        self.events = events
    }
}

package struct PresentEvents: Sendable, Equatable {
    package var title: String?
    package var events: [PresentEvent]

    package init(title: String?, events: [PresentEvent]) {
        self.title = title
        self.events = events
    }
}

package struct PresentPlace: Sendable, Equatable {
    package var name: String
    package var address: String?
    package var lat: Double
    package var lng: Double
    package var url: String?

    package init(name: String, address: String?, lat: Double, lng: Double, url: String?) {
        self.name = name
        self.address = address
        self.lat = lat
        self.lng = lng
        self.url = url
    }
}

package struct PresentPlaces: Sendable, Equatable {
    package var title: String?
    package var places: [PresentPlace]

    package init(title: String?, places: [PresentPlace]) {
        self.title = title
        self.places = places
    }
}

/// A file or folder. `children` is nil for a file; a folder that was
/// expanded carries its entries, which is what makes the tree worth drawing.
package struct PresentFile: Sendable, Equatable {
    package var name: String
    package var size: String?
    package var children: [PresentFile]?

    package init(name: String, size: String? = nil, children: [PresentFile]? = nil) {
        self.name = name
        self.size = size
        self.children = children
    }
}

package struct PresentFiles: Sendable, Equatable {
    package var title: String?
    package var items: [PresentFile]

    package init(title: String?, items: [PresentFile]) {
        self.title = title
        self.items = items
    }
}

package struct PresentPerson: Sendable, Equatable {
    package var name: String
    package var role: String?
    package var status: String?

    package init(name: String, role: String?, status: String?) {
        self.name = name
        self.role = role
        self.status = status
    }
}

package struct PresentPeople: Sendable, Equatable {
    package var title: String?
    package var people: [PresentPerson]

    package init(title: String?, people: [PresentPerson]) {
        self.title = title
        self.people = people
    }
}

package struct PresentCode: Sendable, Equatable {
    package var title: String?
    package var language: String?
    /// Set without before/after: a plain code block.
    package var code: String?
    /// Set with `after`: a diff between the two.
    package var before: String?
    package var after: String?

    package init(
        title: String?, language: String?, code: String?, before: String? = nil, after: String? = nil
    ) {
        self.title = title
        self.language = language
        self.code = code
        self.before = before
        self.after = after
    }

    package var isDiff: Bool { before != nil && after != nil }
}

package struct PresentSource: Sendable, Equatable {
    package var title: String
    package var url: String

    package init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

package enum PresentStepState: String, Sendable, Equatable, CaseIterable {
    case done, current, todo
}

package struct PresentStep: Sendable, Equatable {
    package var title: String
    package var detail: String?
    package var state: PresentStepState

    package init(title: String, detail: String?, state: PresentStepState) {
        self.title = title
        self.detail = detail
        self.state = state
    }
}

package struct PresentSteps: Sendable, Equatable {
    package var title: String?
    package var steps: [PresentStep]

    package init(title: String?, steps: [PresentStep]) {
        self.title = title
        self.steps = steps
    }
}

package struct PresentComparisonRow: Sendable, Equatable {
    package var label: String
    package var values: [PresentCell]

    package init(label: String, values: [PresentCell]) {
        self.label = label
        self.values = values
    }
}

package struct PresentComparison: Sendable, Equatable {
    package var title: String?
    /// The compared options, one column each.
    package var columns: [String]
    /// Every row has exactly `columns.count` values.
    package var rows: [PresentComparisonRow]

    package init(title: String?, columns: [String], rows: [PresentComparisonRow]) {
        self.title = title
        self.columns = columns
        self.rows = rows
    }
}
