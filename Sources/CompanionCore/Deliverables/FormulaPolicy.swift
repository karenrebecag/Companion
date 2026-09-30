import Foundation

/// Wave 20c D4 (M4): what a cell may compute is an allowlist. A denylist had
/// to name every function that fetches or reads another file (IMAGE,
/// STOCKHISTORY, COPILOT, external references) and lost the race each time
/// Excel added one.
package enum FormulaPolicy {
    /// Pure functions of the sheet's own cells: no network, no other file, no
    /// name that resolves indirectly (INDIRECT, OFFSET), no volatile lookups
    /// of the machine (CELL, INFO).
    static let allowedFunctions: Set<String> = [
        "SUM", "SUMIF", "SUMIFS", "SUMPRODUCT", "PRODUCT", "AVERAGE", "AVERAGEIF", "AVERAGEIFS",
        "COUNT", "COUNTA", "COUNTBLANK", "COUNTIF", "COUNTIFS", "MIN", "MAX", "MINIFS", "MAXIFS",
        "MEDIAN", "MODE", "STDEV", "STDEV.S", "STDEV.P", "VAR", "VAR.S", "VAR.P", "LARGE", "SMALL",
        "RANK", "RANK.EQ", "ROUND", "ROUNDUP", "ROUNDDOWN", "INT", "MOD", "ABS", "SQRT", "POWER",
        "EXP", "LN", "LOG", "LOG10", "CEILING", "FLOOR", "TRUNC", "SIGN",
        "IF", "IFS", "IFERROR", "IFNA", "AND", "OR", "NOT", "XOR", "SWITCH", "CHOOSE", "TRUE", "FALSE",
        "VLOOKUP", "HLOOKUP", "LOOKUP", "XLOOKUP", "INDEX", "MATCH", "XMATCH",
        "ROW", "COLUMN", "ROWS", "COLUMNS",
        "LEFT", "RIGHT", "MID", "LEN", "UPPER", "LOWER", "PROPER", "TRIM", "CONCAT", "CONCATENATE",
        "TEXTJOIN", "TEXT", "VALUE", "SUBSTITUTE", "REPLACE", "FIND", "SEARCH", "REPT", "EXACT",
        "DATE", "TODAY", "NOW", "YEAR", "MONTH", "DAY", "WEEKDAY", "EDATE", "EOMONTH", "DATEDIF", "DAYS",
        "HOUR", "MINUTE", "SECOND", "PMT", "PV", "FV", "NPV", "IRR", "RATE",
        "ISBLANK", "ISNUMBER", "ISTEXT", "ISERROR", "ISNA",
    ]

    /// Characters that only appear in a reference to another workbook or
    /// path, or in DDE; refused wherever they sit, even inside a string.
    private static let forbiddenCharacters = CharacterSet(charactersIn: "[]!'\\|")

    /// A `=` cell is a formula for sure: every word in it must be a function,
    /// a cell reference or a boolean, and it must be well formed.
    static func isAllowed(_ text: String) -> Bool {
        guard !hasInvisibleCharacter(text) else { return false }
        let normalized = normalize(text)
        guard normalized.unicodeScalars.allSatisfy({ !forbiddenCharacters.contains($0) }) else { return false }
        // Literals out first: a word inside quotes is text, and an unbalanced
        // quote leaves one behind and fails below.
        let code = normalized.replacingOccurrences(of: #""(?:[^"]|"")*""#, with: "0", options: .regularExpression)
        guard !code.contains("\""), isWellFormed(code), !hasAdjacentOperands(code) else { return false }
        for match in matches(#"[A-Z][A-Z0-9._]*(?=\()"#, in: code) where !allowedFunctions.contains(match) {
            return false
        }
        // Anchored so `TRUEA1` does not shrink to `TRUE`; replaced by a space so
        // two removed tokens cannot fuse into a word that passes.
        let boundary = #"(?<![A-Z0-9_.$])"#
        let words = code
            .replacingOccurrences(of: #"[A-Z][A-Z0-9._]*(?=\()"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: boundary + #"\$?[A-Z]{1,3}\$?[0-9]+(?![A-Z0-9_.])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: boundary + #"\$?[A-Z]{1,3}:\$?[A-Z]{1,3}(?![A-Z0-9_.])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: boundary + #"[0-9.]+E[+-]?[0-9]+(?![A-Z0-9_.])"#, with: " ", options: .regularExpression)
        guard matches(#"[A-Z_][A-Z0-9_.]*"#, in: words).allSatisfy({ $0 == "TRUE" || $0 == "FALSE" }) else { return false }
        // The word regexes are ASCII-only, so a name made of other letters is
        // invisible to them; allow by character instead of denying by shape.
        return words.unicodeScalars.allSatisfy { safeCharacters.contains($0) }
    }

    /// What is left of a formula once functions, references and numbers are
    /// gone: booleans, operators, separators, array and spill syntax.
    private static let safeCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789$.,:;()+-*/^&=<>%{}#@ ")

    /// Text that starts with `+`, `-` or `@`: Excel's formula setter starts a
    /// formula on any of them. Prose ("- Total (MXN)", "-12 grados") is a
    /// literal cell and the writer stores it as text; whatever is shaped like
    /// a formula gets the same strict check as a `=` cell.
    static func isAllowedSigned(_ text: String) -> Bool {
        // DDE and external references are refused even inside what reads as prose.
        guard !hasInvisibleCharacter(text), text.unicodeScalars.allSatisfy({ !forbiddenCharacters.contains($0) }) else {
            return false
        }
        guard let sign = text.first(where: { !$0.isWhitespace }).flatMap(SheetValues.foldedSign),
              "+-@".contains(sign) else { return isAllowed(text) }
        return isProse(text, sign: sign) || isAllowed(String(text.drop(while: { $0.isWhitespace }).dropFirst()))
    }

    /// Zero-width and other format characters split a function name for the
    /// regexes below while Excel still reads it (U+2060, U+200B, U+00AD, U+FEFF).
    private static func hasInvisibleCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { [.format, .control].contains($0.properties.generalCategory) }
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.uppercased()
        return String(folded.map { $0.isWhitespace ? " " : $0 }).trimmingCharacters(in: .whitespaces)
    }

    /// Whitespace is kept as a separator, not deleted: Excel reads the raw
    /// text, so `TR UE` must not collapse into a word the check accepts, and a
    /// bare word after a call (`SUM(A1) TRUE`) is not an operand of anything.
    private static func hasAdjacentOperands(_ code: String) -> Bool {
        code.range(of: #"[A-Z0-9_.$)]\s+[A-Z0-9_.$(]"#, options: .regularExpression) != nil
    }

    /// Nothing to evaluate, or a shape Excel refuses: reject rather than let
    /// the app decide what half a formula means.
    private static func isWellFormed(_ code: String) -> Bool {
        guard let last = code.last, !"+-*/^&=<>,:".contains(last) else { return false }
        var depth = 0
        for char in code {
            if char == "(" { depth += 1 }
            if char == ")" { depth -= 1 }
            if depth < 0 { return false }
        }
        return depth == 0
    }

    /// A word next to a word, or a word next to a call's parenthesis, is
    /// language; a formula has an operator between them.
    private static func isProse(_ text: String, sign: Character) -> Bool {
        let unquoted = text.replacingOccurrences(of: #""(?:[^"]|"")*""#, with: "0", options: .regularExpression)
        let body = unquoted.drop(while: { $0.isWhitespace }).dropFirst()
        if sign == "@", !body.contains("(") { return true }
        return String(body).range(of: #"[\p{L}\p{N}_)]\s+[\p{L}\p{N}_(]"#, options: .regularExpression) != nil
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        var found: [String] = []
        var search = text.startIndex..<text.endIndex
        while let range = text.range(of: pattern, options: .regularExpression, range: search) {
            found.append(String(text[range]))
            search = range.upperBound..<text.endIndex
        }
        return found
    }
}
