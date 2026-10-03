import CompanionCore
import Foundation

/// A refusal is an outcome for the model, not a thrown error, so this is not a `Result`.
enum ReadQuery {
    case query(BrowserQuery)
    case refused(ParentToolOutcome)
}

extension BrowserToolRunner {
    static let findTextLimit = 200
    static let findMaxElements = 500
    static let findMaxChars = 200_000

    /// H-7 P2a: the read's finders, checked here so a typo or an impossible combination comes
    /// back to the model by name instead of as an empty or whole-page read.
    func readQuery(_ arguments: [String: Any], tab: Int) -> ReadQuery {
        let refuse = { (message: String) in ReadQuery.refused(self.fail(.read, BridgeCode.invalidArgs, message)) }
        var query = BrowserQuery()
        for key in ["selector", "text", "role", "name"] {
            guard let raw = arguments[key], !(raw is NSNull) else { continue }
            guard let text = raw as? String else { return refuse("\(key) must be a string") }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty selector was always the whole page; an empty finder is a search for nothing.
            if trimmed.isEmpty {
                if key == "selector" { continue }
                return refuse("\(key) must not be empty")
            }
            if key != "selector", trimmed.count > Self.findTextLimit {
                return refuse("\(key) must be at most \(Self.findTextLimit) characters")
            }
            switch key {
            case "selector": query.selector = trimmed
            case "text": query.text = trimmed
            case "role": query.role = trimmed
            default: query.name = trimmed
            }
        }
        if query.name != nil, query.role == nil { return refuse("name needs a role, as in role button with name Save") }
        if let raw = arguments["exact"], !(raw is NSNull) {
            guard let flag = Self.boolean(raw) else { return refuse("exact must be true or false") }
            query.exact = flag
        }
        for (key, limit) in [("max", Self.findMaxElements), ("max_chars", Self.findMaxChars)] {
            guard let raw = arguments[key], !(raw is NSNull) else { continue }
            guard let count = Self.count(raw), (1...limit).contains(count) else {
                return refuse("\(key) must be a whole number from 1 to \(limit)")
            }
            if key == "max" { query.max = count } else { query.maxChars = count }
        }
        if let raw = arguments["within"], !(raw is NSNull) {
            guard let element = Self.count(raw) else { return refuse("within must be an element number") }
            // The number is the last read's; a read since, or none at all, makes it point nowhere.
            guard let page = cachedPage(tab), page.elements.contains(where: { $0.id == element }) else {
                return refuse("within must be an element number from the last browser_read of this tab")
            }
            query.within = BrowserElementRef(generation: page.generation, element: element)
        }
        return .query(query)
    }

    /// JSON true and false arrive as NSNumber, which also reads as 1 and 0: only a real boolean counts.
    private static func boolean(_ raw: Any) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func count(_ raw: Any) -> Int? {
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return ParentToolRunner.intArgument(raw)
    }
}
