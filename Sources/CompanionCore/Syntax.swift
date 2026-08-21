import Foundation

public enum SyntaxKind: Sendable, Equatable {
    case text, keyword, string, comment, number, typeName, attr
}

public struct SyntaxToken: Sendable, Equatable {
    public let text: String
    public let kind: SyntaxKind

    public init(text: String, kind: SyntaxKind) {
        self.text = text
        self.kind = kind
    }
}

public enum SyntaxTokenizer: Sendable {
    public static func tokenize(_ source: String, language: String) -> [SyntaxToken] {
        let fam = Family.of(language)
        if fam == .plain {
            return source.isEmpty
                ? []
                : [SyntaxToken(text: source, kind: .text)]
        }
        let chars = Array(source)
        let n = chars.count
        var tokens: [SyntaxToken] = []
        var i = 0
        while i < n {
            if let (len, kind) = match(chars, at: i, n: n, family: fam) {
                tokens.append(SyntaxToken(
                    text: String(chars[i..<(i + len)]), kind: kind))
                i += len
                continue
            }
            tokens.append(SyntaxToken(text: String(chars[i]), kind: .text))
            i += 1
        }
        return tokens
    }

    private static func match(
        _ c: [Character], at i: Int, n: Int, family: Family
    ) -> (Int, SyntaxKind)? {
        let ch = c[i]
        if family.lineComment != nil || family.blockComment != nil
            || family.hashComment {
            if let hit = comment(c, at: i, n: n, family: family) { return hit }
        }
        if let hit = string(c, at: i, n: n, family: family) { return hit }
        if ch.isNumber, let hit = number(c, at: i, n: n) { return hit }

        if ch == "@" && i + 1 < n && (c[i + 1].isLetter || c[i + 1] == "_") {
            let end = identEnd(c, from: i + 1, n: n)
            return (end - i, .attr)
        }
        if ch == "#" && family == .swift && i + 1 < n && c[i + 1].isLetter {
            let end = identEnd(c, from: i + 1, n: n)
            return (end - i, .attr)
        }
        if ch.isLetter || ch == "_" {
            let end = identEnd(c, from: i, n: n)
            let word = String(c[i..<end])
            if family.keywords.contains(word) { return (end - i, .keyword) }
            if family.capitalTypes, word.first?.isUppercase == true {
                return (end - i, .typeName)
            }
            return (end - i, .text)
        }
        return nil
    }

    private static func identEnd(_ c: [Character], from i: Int, n: Int) -> Int {
        var j = i + 1
        while j < n && (c[j].isLetter || c[j].isNumber || c[j] == "_") { j += 1 }
        return j
    }

    private static func comment(
        _ c: [Character], at i: Int, n: Int, family: Family
    ) -> (Int, SyntaxKind)? {
        if let mark = family.lineComment, starts(c, at: i, n: n, with: mark) {
            var j = i + mark.count
            while j < n && c[j] != "\n" { j += 1 }
            return (j - i, .comment)
        }
        if family.hashComment, c[i] == "#" {
            var j = i + 1
            while j < n && c[j] != "\n" { j += 1 }
            return (j - i, .comment)
        }
        if let (open, close) = family.blockComment,
           starts(c, at: i, n: n, with: open) {
            var j = i + open.count
            while j < n, !starts(c, at: j, n: n, with: close) { j += 1 }
            if j < n { j += close.count }
            return (j - i, .comment)
        }
        return nil
    }

    private static func string(
        _ c: [Character], at i: Int, n: Int, family: Family
    ) -> (Int, SyntaxKind)? {
        if family.tripleQuotes, i + 2 < n,
           (c[i] == "\"" || c[i] == "'"),
           c[i + 1] == c[i], c[i + 2] == c[i] {
            let q = c[i]
            var j = i + 3
            while j + 2 < n, !(c[j] == q && c[j + 1] == q && c[j + 2] == q) {
                j += 1
            }
            if j + 2 < n { j += 3 } else { j = n }
            return (j - i, .string)
        }
        if c[i] == "\"" || (family.singleQuotes && c[i] == "'")
            || (family.backticks && c[i] == "`") {
            let q = c[i]
            var j = i + 1
            while j < n && c[j] != q {
                if c[j] == "\\" && j + 1 < n { j += 2; continue }
                j += 1
            }
            if j < n && c[j] == q { j += 1 }
            return (j - i, .string)
        }
        return nil
    }

    private static func number(
        _ c: [Character], at i: Int, n: Int
    ) -> (Int, SyntaxKind)? {
        var j = i
        if i + 1 < n, c[i] == "0",
           c[i + 1] == "x" || c[i + 1] == "X"
            || c[i + 1] == "b" || c[i + 1] == "B"
            || c[i + 1] == "o" || c[i + 1] == "O" {
            j += 2
            while j < n && (c[j].isHexDigit || c[j] == "_") { j += 1 }
            return (j - i, .number)
        }
        while j < n && (c[j].isNumber || c[j] == "_") { j += 1 }
        if j < n, c[j] == ".", j + 1 < n, c[j + 1].isNumber {
            j += 1
            while j < n && (c[j].isNumber || c[j] == "_") { j += 1 }
        }
        if j < n, c[j] == "e" || c[j] == "E" {
            var k = j + 1
            if k < n, c[k] == "+" || c[k] == "-" { k += 1 }
            guard k < n, c[k].isNumber else {
                return (j - i, .number)
            }
            j = k + 1
            while j < n && c[j].isNumber { j += 1 }
        }
        return (j - i, .number)
    }

    private static func starts(
        _ c: [Character], at i: Int, n: Int, with s: String
    ) -> Bool {
        let needle = Array(s)
        guard i + needle.count <= n else { return false }
        for k in needle.indices where c[i + k] != needle[k] { return false }
        return true
    }
}
