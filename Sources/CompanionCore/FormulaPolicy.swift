import Foundation

/// Wave 20c D4 (M4): what a cell may compute is an allowlist. A denylist had
/// to name every function that fetches or reads another file (IMAGE,
/// STOCKHISTORY, COPILOT, external references) and lost the race each time
/// Excel added one.
public enum FormulaPolicy {
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

    /// `strictNames`: a leading `=` is a formula for sure, so every word in it
    /// must be a function, a cell reference or a boolean. A leading `+`, `-` or
    /// `@` may just be text ("-12 grados"): only calls and reference syntax count.
    static func isAllowed(_ text: String, strictNames: Bool) -> Bool {
        let normalized = String(text.precomposedStringWithCompatibilityMapping.uppercased()
            .filter { !$0.isWhitespace })
        guard normalized.unicodeScalars.allSatisfy({ !forbiddenCharacters.contains($0) }) else { return false }
        // Literals out first: a word inside quotes is text, and an unbalanced
        // quote leaves one behind and fails below.
        let code = normalized.replacingOccurrences(of: #""(?:[^"]|"")*""#, with: "0", options: .regularExpression)
        guard !code.contains("\"") else { return false }
        for match in matches(#"[A-Z][A-Z0-9._]*(?=\()"#, in: code) where !allowedFunctions.contains(match) {
            return false
        }
        guard strictNames else { return true }
        let words = code
            .replacingOccurrences(of: #"[A-Z][A-Z0-9._]*(?=\()"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\$?[A-Z]{1,3}\$?[0-9]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\$?[A-Z]{1,3}:\$?[A-Z]{1,3}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[0-9.]+E[+-]?[0-9]+"#, with: "", options: .regularExpression)
        return matches(#"[A-Z_][A-Z0-9_.]*"#, in: words).allSatisfy { $0 == "TRUE" || $0 == "FALSE" }
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
