import Foundation

/// A number the reply states that no source of the turn states is presumed
/// invented: the model read a results page with headlines and no rate, then
/// answered a rate. Deterministic on purpose; a second model judging the first
/// would invent its own figures.
package enum UnsourcedFigures {
    /// Figures the reply states that none of `sources` states, as the reply
    /// spells them.
    package static func find(in reply: String, sources: [String]) -> [String] {
        let sourced = sources.flatMap { tokens(in: $0) }.flatMap { readings(of: $0).map(\.value) }
        var unsourced: [String] = []
        for token in stated(in: reply)
        where !readings(of: token).contains(where: { isSourced($0, by: sourced) }) {
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

    /// A figure as a token spells it, with the decimal places that spelling
    /// implies: the places a rounding must keep to compare like with like.
    private struct Reading {
        let value: Decimal
        let scale: Int
    }

    /// `18.49` and `18,49` are the same figure. `1,234` and `1.234` can be a
    /// thousand or a decimal, so both readings are kept and either may match:
    /// a figure we cannot tell apart from a sourced one is not presumed
    /// invented, because a false caveat costs more than a missed one.
    /// Decimal rather than Double so that rounding a source to two places is
    /// exact and a figure at a half-way point does not flip on float error.
    private static func readings(of token: String) -> [Reading] {
        let parts = token.split(whereSeparator: { $0 == "." || $0 == "," }).map(String.init)
        guard parts.count > 1 else {
            return Decimal(string: token).map { [Reading(value: $0, scale: 0)] } ?? []
        }
        var out: [Reading] = []
        let fraction = parts[parts.count - 1]
        if let decimal = Decimal(string: parts.dropLast().joined() + "." + fraction) {
            out.append(Reading(value: decimal, scale: fraction.count))
        }
        if parts.dropFirst().allSatisfy({ $0.count == 3 }), let grouped = Decimal(string: parts.joined()) {
            out.append(Reading(value: grouped, scale: 0))
        }
        return out
    }

    /// Rounding and truncation both count. Writers round (18.4239 is 18.42),
    /// and some cut (18.46 is 18.4). Accepting both means a harmless cut never
    /// earns a caveat; the price is that a truncated figure passes even where a
    /// stricter rule would not, which is the side this guard should err on.
    private static func isSourced(_ figure: Reading, by sourced: [Decimal]) -> Bool {
        sourced.contains { number in
            quantized(number, scale: figure.scale, mode: .plain) == figure.value
                || quantized(number, scale: figure.scale, mode: .down) == figure.value
        }
    }

    private static func quantized(
        _ number: Decimal, scale: Int, mode: NSDecimalNumber.RoundingMode
    ) -> Decimal {
        var input = number
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, mode)
        return output
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        let regex = ConstantPattern.compile(pattern)
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range) }
    }

    private static func replacing(
        _ pattern: String, in text: String, with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        let regex = ConstantPattern.compile(pattern, options: options)
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement)
    }
}
