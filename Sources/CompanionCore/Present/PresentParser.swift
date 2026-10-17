import Foundation

/// A block the parser could not draw as its family. The reply still shows
/// something; the issue is what the next turn tells the model.
package struct PresentIssue: Sendable, Equatable {
    /// -1 when the whole call was refused, not one block.
    package var index: Int
    package var type: String
    package var reason: String

    package init(index: Int, type: String, reason: String) {
        self.index = index
        self.type = type
        self.reason = reason
    }
}

package struct PresentOutcome: Sendable, Equatable {
    package var blocks: [PresentBlock]
    package var issues: [PresentIssue]

    package init(blocks: [PresentBlock], issues: [PresentIssue]) {
        self.blocks = blocks
        self.issues = issues
    }
}

/// Turns the arguments of a `present` call into typed blocks. It never fails:
/// a block that does not validate falls back to the nearest family, then to
/// text, and every fallback is reported as an issue. The reply is never lost
/// to one malformed block.
package enum PresentParser {
    /// Near words a model reaches for. A match is parsed as the family it
    /// names; the fields still have to validate for that family.
    static let aliases: [String: PresentFamily] = [
        "title": .heading, "h1": .heading, "h2": .heading, "subtitle": .heading, "header": .heading,
        "text": .paragraph, "p": .paragraph,
        "bullets": .list, "ul": .list, "ol": .list, "checklist": .steps, "todo": .steps,
        "kv": .keyvalue, "keyvalues": .keyvalue, "fields": .keyvalue, "facts": .keyvalue,
        "tip": .callout, "note": .callout, "info": .callout,
        "warning": .notice, "alert": .notice, "error": .notice,
        "hr": .divider, "separator": .divider, "rule": .divider,
        "grid": .table, "rows": .table,
        "chart": .timeSeries, "line": .timeSeries, "series": .timeSeries,
        "pie": .partsOfWhole, "donut": .partsOfWhole, "share": .partsOfWhole,
        "bar": .ranking, "bars": .ranking, "top": .ranking,
        "stats": .metrics, "stat": .metrics, "kpi": .metrics, "figures": .metrics,
        "milestones": .timeline, "map": .places, "location": .places, "locations": .places,
        "tree": .files, "folders": .files, "file": .files,
        "users": .people, "person": .people,
        "meetings": .events, "calendar": .events,
        "code": .codeOrDiff, "diff": .codeOrDiff,
        "sources": .webSources, "links": .webSources, "references": .webSources,
        "compare": .comparison, "versus": .comparison,
    ]

    static let familiesByName: [String: PresentFamily] = Dictionary(
        uniqueKeysWithValues: PresentFamily.allCases.map { ($0.rawValue.lowercased(), $0) })

    package static func parse(arguments: [String: Any]) -> PresentOutcome {
        guard let raw = arguments["blocks"] as? [Any] else {
            return PresentOutcome(blocks: [], issues: [
                PresentIssue(index: -1, type: "", reason: "missing blocks array"),
            ])
        }
        return parse(rawBlocks: raw)
    }

    static func parse(rawBlocks raw: [Any]) -> PresentOutcome {
        var issues: [PresentIssue] = []
        if raw.count > PresentContract.Limits.maxBlocks {
            issues.append(PresentIssue(
                index: -1, type: "",
                reason: "more than \(PresentContract.Limits.maxBlocks) blocks; the rest were dropped"))
        }
        var blocks: [PresentBlock] = []
        for (index, item) in raw.prefix(PresentContract.Limits.maxBlocks).enumerated() {
            let (block, issue) = parseBlock(item, index: index)
            blocks.append(block)
            if let issue { issues.append(issue) }
        }
        return PresentOutcome(blocks: blocks, issues: issues)
    }

    static func parseBlock(_ item: Any, index: Int) -> (PresentBlock, PresentIssue?) {
        guard let dict = item as? [String: Any] else {
            return (textFallback(item), PresentIssue(index: index, type: "", reason: "block is not an object"))
        }
        guard let type = dict["type"] as? String else {
            return (textFallback(dict), PresentIssue(index: index, type: "", reason: "missing type"))
        }
        let key = type.lowercased()
        guard let family = familiesByName[key] ?? aliases[key] else {
            return (textFallback(dict), PresentIssue(index: index, type: type, reason: "unknown type"))
        }
        let issue = PresentIssue(index: index, type: type, reason: "\(family.rawValue) fields did not validate")
        if let block = self.family(family, dict) {
            return (block, nil)
        }
        return (genericTable(family, dict) ?? textFallback(dict), issue)
    }

    /// Text, never an error: a block with prose in it reads as prose; anything
    /// else stays visible as the JSON the model wrote, so nothing vanishes.
    static func textFallback(_ value: Any) -> PresentBlock {
        if let dict = value as? [String: Any], let body = text(dict, "text") {
            return .paragraph(body)
        }
        return .codeOrDiff(PresentCode(title: nil, language: "json", code: jsonText(value)))
    }

    /// The fallback shows the model's own JSON, so it is capped like any text.
    static func jsonText(_ value: Any) -> String {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        } catch {
            return String(describing: value).prefix(PresentContract.Limits.maxTextBytes).description
        }
        let text = String(decoding: data, as: UTF8.self)
        return String(text.prefix(PresentContract.Limits.maxTextBytes))
    }
}
