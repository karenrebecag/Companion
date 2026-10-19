import Foundation

/// A number the reply states that no source of the turn states is presumed
/// invented: the model read a results page with headlines and no rate, then
/// answered a rate. Deterministic on purpose; a second model judging the first
/// would invent its own figures.
package enum UnsourcedFigures {
    /// Figures the reply states that none of `sources` states, as the reply
    /// spells them.
    package static func find(in reply: String, sources: [String]) -> [String] {
        let sourced = sources.reduce(into: Set<Double>()) { set, source in
            for token in tokens(in: source) { set.formUnion(values(of: token)) }
        }
        var unsourced: [String] = []
        for token in stated(in: reply) where values(of: token).isDisjoint(with: sourced) {
            if !unsourced.contains(token) { unsourced.append(token) }
        }
        return unsourced
    }

    /// The line that says so, when the turn read the web and the reply states a
    /// figure nothing in the turn says. Nil otherwise. Chat and voice both call
    /// it, with the turn's own messages (the rounds since her last words).
    package static func caveat(
        for reply: String, turn: [Turn], userWords: String, language: AppLanguage
    ) -> String? {
        guard turn.flatMap(\.toolCalls).contains(where: { readsWeb(tool: $0.name) }) else { return nil }
        let sources = turn.filter { $0.role == .tool }.map(\.content)
        guard !find(in: reply, sources: sources + [userWords]).isEmpty else { return nil }
        switch language {
        case .en: return "I did not find that figure in the sources."
        case .es: return "No encontré esa cifra en las fuentes."
        }
    }

    /// Tools whose result is page or search content a stranger wrote.
    package static func readsWeb(tool: String) -> Bool {
        if let native = NativeTool(rawValue: tool) {
            return [.webSearch, .readURL, .webFetch].contains(native)
        }
        return BrowserTool(rawValue: tool) != nil
    }

    /// Dates, clock times and years are not figures a reply quotes from a
    /// source; small counts ("tres opciones") are not worth a caveat.
    private static let spans = [
        #"\d{1,4}([/.\-])\d{1,2}\1\d{1,4}"#,
        #"\d{1,2}:\d{2}(?::\d{2})?"#,
        #"\d{1,2}(?:\s+de)?\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre|january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
        #"\b(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre|january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}\b"#,
    ]

    private static func stated(in reply: String) -> [String] {
        var text = reply
        for pattern in spans {
            text = replacing(pattern, in: text, with: " ", options: [.caseInsensitive])
        }
        return tokens(in: text).filter { token in
            guard let value = Int(token.filter(\.isNumber)), !token.contains(where: { $0 == "." || $0 == "," })
            else { return true }
            return !(value <= 10 || (1900 ... 2100).contains(value))
        }
    }

    private static func tokens(in text: String) -> [String] {
        matches(#"\d+(?:[.,]\d+)*"#, in: text)
    }

    /// `18.49` and `18,49` are the same figure; a comma-grouped `1,234` and a
    /// dotted `1.234` are read as thousands and as a decimal, whichever the
    /// source used.
    private static func values(of token: String) -> Set<Double> {
        let parts = token.split(whereSeparator: { $0 == "." || $0 == "," }).map(String.init)
        guard parts.count > 1 else {
            return Double(token).map { [$0] } ?? []
        }
        var out = Set<Double>()
        if let decimal = Double(parts.dropLast().joined() + "." + parts[parts.count - 1]) {
            out.insert(decimal)
        }
        if parts.dropFirst().allSatisfy({ $0.count == 3 }), let grouped = Double(parts.joined()) {
            out.insert(grouped)
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private static func replacing(
        _ pattern: String, in text: String, with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement)
    }
}
