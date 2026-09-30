import Foundation

/// `misprint_repair` (spec 24 §5), layer 2 of Wave 10c 3A.4: what arrives
/// malformed from a provider without `strict` is repaired before dispatch,
/// with exactly the list json_repair documents and nothing more. A JSON that
/// already parses is never touched; text that is "super broken" is `nil`,
/// never an invented object — the runner tells the model what it sent.
package enum ToolArguments: Sendable {
    package static func parse(_ raw: String) -> [String: Any]? {
        if let object = object(raw) { return object }
        return repair(raw)
    }

    static func repair(_ raw: String) -> [String: Any]? {
        var text = unfenced(raw)
        guard let open = text.firstIndex(of: "{") else { return nil }
        text = String(text[open...])
        // The object ends at the brace that matches the first one, counted
        // outside strings: a `}` inside a value is content, not the end.
        text = String(text[..<matchingClose(text)])
        // Single quotes are the string delimiter only when there are no
        // double ones at all — decided before any repair adds some.
        let singleQuoted = !text.contains("\"")
        text = pythonLiterals(text)
        text = unquotedKeys(text)
        if singleQuoted { text = text.replacingOccurrences(of: "'", with: "\"") }
        text = missingCommas(text)
        text = trailingCommas(text)
        text = closed(text)
        return object(text)
    }

    // MARK: - the list

    private static func object(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Code fences, comments and prose around the object.
    private static func unfenced(_ text: String) -> String {
        text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `True` / `False` / `None` and upper-case literals, outside strings.
    private static func pythonLiterals(_ text: String) -> String {
        rewriteOutsideStrings(text) { chunk in
            var out = chunk
            for (bad, good) in [("True", "true"), ("TRUE", "true"), ("False", "false"),
                                ("FALSE", "false"), ("None", "null"), ("NULL", "null"),
                                ("Null", "null")] {
                out = out.replacingOccurrences(
                    of: "\\b\(bad)\\b", with: good, options: .regularExpression)
            }
            return out
        }
    }

    /// `{path: "a"}` → `{"path": "a"}`, outside strings.
    private static func unquotedKeys(_ text: String) -> String {
        rewriteOutsideStrings(text) { chunk in
            chunk.replacingOccurrences(
                of: "([{,]\\s*)([A-Za-z_][A-Za-z0-9_]*)(\\s*:)",
                with: "$1\"$2\"$3", options: .regularExpression)
        }
    }

    /// Where the object opened by the first character closes, scanning
    /// outside strings; the end of the text when it never does.
    private static func matchingClose(_ text: String) -> String.Index {
        var depth = 0
        var inString = false
        var escaped = false
        for index in text.indices {
            let ch = text[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 { return text.index(after: index) }
            default: break
            }
        }
        return text.endIndex
    }

    /// A value that ends and a string that starts with nothing between:
    /// `"a": "x"\n "b": 1`. Scanned, not regexed: a `"key":` shape inside a
    /// value must not grow a comma.
    private static func missingCommas(_ text: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        var valueEnded = false
        for ch in text {
            if inString {
                out.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false; valueEnded = true }
                continue
            }
            if ch == "\"" {
                if valueEnded { out.append(",") }
                inString = true
                valueEnded = false
                out.append(ch)
                continue
            }
            if ch.isWhitespace {
                out.append(ch)
                continue
            }
            valueEnded = !(ch == ":" || ch == "," || ch == "{" || ch == "[")
            out.append(ch)
        }
        return out
    }

    private static func trailingCommas(_ text: String) -> String {
        rewriteOutsideStrings(text) { chunk in
            chunk.replacingOccurrences(
                of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
        }
    }

    /// An open string is closed, then every open bracket, innermost first.
    private static func closed(_ text: String) -> String {
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for ch in text {
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{": stack.append("}")
            case "[": stack.append("]")
            case "}", "]": if stack.last == ch { stack.removeLast() }
            default: break
            }
        }
        var out = text
        if inString { out += "\"" }
        out = trailingCommas(out)
        while let closer = stack.popLast() { out.append(closer) }
        return out
    }

    /// Applies `rewrite` to the parts of `text` that are not inside a JSON
    /// string, so a literal inside a value is never rewritten.
    private static func rewriteOutsideStrings(
        _ text: String, _ rewrite: (String) -> String
    ) -> String {
        var out = ""
        var chunk = ""
        var inString = false
        var escaped = false
        for ch in text {
            if inString {
                out.append(ch)
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" {
                out += rewrite(chunk)
                chunk = ""
                inString = true
                out.append(ch)
            } else {
                chunk.append(ch)
            }
        }
        out += rewrite(chunk)
        return out
    }
}
