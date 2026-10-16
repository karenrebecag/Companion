import Foundation

/// The vocabulary of the `present` tool. The model names what a piece of
/// content IS (a series, a share, a set of files); the resolver decides which
/// component paints it. Keeping the model on meaning and the renderer on
/// shape is what stops the same data from looking different every turn.
///
/// Each case carries the one-line rule the schema teaches: when to reach for
/// it and when the neighbouring family is the right one. Two families that
/// overlap (table vs comparison, timeline vs steps) only stay distinct if the
/// schema says where the line is.
package enum PresentFamily: String, CaseIterable, Sendable {
    // Prose: plain text the chat already knows how to paint.
    case heading, paragraph, list, keyvalue, callout, quote, divider
    // Data families: each resolves to one component through BlockResolver.
    case table, timeSeries, partsOfWhole, ranking, metrics, timeline, places
    case files, people, events, codeOrDiff, webSources, steps, comparison, notice

    package var isProse: Bool {
        switch self {
        case .heading, .paragraph, .list, .keyvalue, .callout, .quote, .divider: true
        default: false
        }
    }

    package var whenToUse: String {
        switch self {
        case .heading: "a section title"
        case .paragraph: "running prose"
        case .list: "items of text with no values attached"
        case .keyvalue: "a few label-value facts about one thing"
        case .callout: "a highlighted note or tip"
        case .quote: "a quoted passage with its source"
        case .divider: "a break between sections"
        case .table: "rows of values the reader will compare, sort or scan"
        case .timeSeries: "values over time, in order"
        case .partsOfWhole: "shares that add up to one whole"
        case .ranking: "named items compared by one number"
        case .metrics: "a few headline figures, optionally with a trend or target"
        case .timeline: "dated milestones in order"
        case .places: "physical places whose coordinates you looked up"
        case .files: "files or folders, flat or nested"
        case .people: "named people with roles"
        case .events: "scheduled meetings or deadlines"
        case .codeOrDiff: "code, a command, or a before/after change"
        case .webSources: "the links you based the answer on"
        case .steps: "ordered steps, each done, current or to do"
        case .comparison: "several options compared on the same attributes"
        case .notice: "a status the user must notice: failure, limit, or warning"
        }
    }

    package var whenNotToUse: String {
        switch self {
        case .heading: "a sentence (paragraph)"
        case .paragraph: "anything with a fixed shape"
        case .list: "items that carry numbers (ranking, table)"
        case .keyvalue: "many rows (table)"
        case .callout: "a failure the user must act on (notice)"
        case .quote: "your own words"
        case .divider: "inside a section"
        case .table: "a few facts about one thing (keyvalue)"
        case .timeSeries: "unordered categories (ranking) or one figure (metrics)"
        case .partsOfWhole: "independent values with no total"
        case .ranking: "values over time (timeSeries)"
        case .metrics: "a whole dataset (table)"
        case .timeline: "steps still to take (steps)"
        case .places: "a place without coordinates (paragraph)"
        case .files: "the contents of a file (codeOrDiff)"
        case .people: "things that are not people (list)"
        case .events: "milestones with no schedule (timeline)"
        case .codeOrDiff: "prose that mentions code inline"
        case .webSources: "any link inside prose"
        case .steps: "dated milestones (timeline)"
        case .comparison: "one item's facts (keyvalue)"
        case .notice: "a normal explanation (paragraph)"
        }
    }

    /// The shape of the block's data, as the schema teaches it. Kept next to
    /// the family so the schema and the parser cannot name different fields.
    package var shape: String {
        switch self {
        case .heading: "text, level 1-3"
        case .paragraph: "text"
        case .list: "items[string], ordered"
        case .keyvalue: "items[{key,value}]"
        case .callout: "tone, title, text"
        case .quote: "text, source"
        case .divider: "no fields"
        case .table: "title, columns[string], rows[[cell]] (cell: string or number)"
        case .timeSeries: "title, unit, labels[string], series[{name,values[number]}], stacked"
        case .partsOfWhole: "title, parts[{label,value>=0}]"
        case .ranking: "title, unit, items[{label,value}]"
        case .metrics: "title, items[{label,value,unit,delta,trend[number],target}]"
        case .timeline: "title, events[{when,title,detail,tone}]"
        case .places: "title, places[{name,address,lat,lng,url}]"
        case .files: "title, items[{name,size,children[...]}]"
        case .people: "title, people[{name,role,status}]"
        case .events: "title, events[{title,start,end,place,detail}]"
        case .codeOrDiff: "title, language, code | before+after"
        case .webSources: "sources[{title,url}]"
        case .steps: "title, steps[{title,detail,state: done|current|todo}]"
        case .comparison: "title, columns[string], rows[{label,values[string|number]}]"
        case .notice: "tone, title, text"
        }
    }
}
