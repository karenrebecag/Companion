import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func syntaxTests() {
    testEmptySource()
    testUnknownLanguageIsPlain()
    testEmptyLanguageIsPlain()
    testNumberIsOneToken()
    testSwiftKeyword()
    testPythonKeyword()
    testJavaScriptKeyword()
    testJSONKeyword()
    testShellKeyword()
    testMarkdownFamilyExists()
    testUnclosedBlockCommentToEOF()
    testUnclosedStringToEOF()
    testEscapedQuoteDoesNotCloseString()
    testPaletteRoles()
    testHighlighterPreservesText()
}

@MainActor func testEmptySource() {
    expectEq(
        SyntaxTokenizer.tokenize("", language: "swift"),
        [],
        "syntax: empty → no tokens")
}

@MainActor func testUnknownLanguageIsPlain() {
    let tokens = SyntaxTokenizer.tokenize("func foo", language: "cobol")
    expect(tokens.allSatisfy { $0.kind == .text },
           "syntax: unknown language is all text")
    expect(!tokens.contains { $0.kind == .keyword },
           "syntax: unknown language has no keywords")
}

@MainActor func testEmptyLanguageIsPlain() {
    let tokens = SyntaxTokenizer.tokenize("func foo", language: "")
    expect(tokens.allSatisfy { $0.kind == .text },
           "syntax: empty language is all text")
}

@MainActor func testNumberIsOneToken() {
    let tokens = SyntaxTokenizer.tokenize("3.14", language: "swift")
    expectEq(tokens.count, 1, "syntax: 3.14 is one token")
    expectEq(tokens.first?.kind, .number, "syntax: 3.14 is a number")
    expectEq(tokens.first?.text, "3.14", "syntax: 3.14 text intact")
}

@MainActor func testSwiftKeyword() {
    let kinds = SyntaxTokenizer.tokenize("func", language: "swift").map(\.kind)
    expectEq(kinds, [.keyword], "syntax: swift func")
}

@MainActor func testPythonKeyword() {
    let kinds = SyntaxTokenizer.tokenize("def", language: "python").map(\.kind)
    expectEq(kinds, [.keyword], "syntax: python def")
}

@MainActor func testJavaScriptKeyword() {
    let kinds = SyntaxTokenizer.tokenize("const", language: "ts").map(\.kind)
    expectEq(kinds, [.keyword], "syntax: js/ts const")
}

@MainActor func testJSONKeyword() {
    let kinds = SyntaxTokenizer.tokenize("null", language: "json").map(\.kind)
    expectEq(kinds, [.keyword], "syntax: json null")
}

@MainActor func testShellKeyword() {
    let kinds = SyntaxTokenizer.tokenize("then", language: "bash").map(\.kind)
    expectEq(kinds, [.keyword], "syntax: shell then")
}

@MainActor func testMarkdownFamilyExists() {
    let tokens = SyntaxTokenizer.tokenize("`code`", language: "markdown")
    expect(tokens.contains { $0.kind == .string },
           "syntax: markdown backticks are strings")
}

@MainActor func testUnclosedBlockCommentToEOF() {
    let tokens = SyntaxTokenizer.tokenize("/* still open", language: "swift")
    expectEq(tokens.count, 1, "syntax: unclosed comment is one token")
    expectEq(tokens.first?.kind, .comment, "syntax: unclosed comment kind")
    expectEq(tokens.first?.text, "/* still open", "syntax: comment eats the rest")
}

@MainActor func testUnclosedStringToEOF() {
    let tokens = SyntaxTokenizer.tokenize("\"still open", language: "swift")
    expectEq(tokens.count, 1, "syntax: unclosed string is one token")
    expectEq(tokens.first?.kind, .string, "syntax: unclosed string kind")
}

@MainActor func testEscapedQuoteDoesNotCloseString() {
    let tokens = SyntaxTokenizer.tokenize("\"a\\\"b\"", language: "swift")
    expectEq(tokens.count, 1, "syntax: escaped quote stays inside")
    expectEq(tokens.first?.kind, .string, "syntax: whole span is string")
    expectEq(tokens.first?.text, "\"a\\\"b\"", "syntax: text includes both quotes")
}

@MainActor func testPaletteRoles() {
    expectEq(SyntaxPalette.role(for: .text), .foreground, "palette: text")
    expectEq(SyntaxPalette.role(for: .comment), .mutedForeground, "palette: comment")
    expectEq(SyntaxPalette.role(for: .keyword), .purple, "palette: keyword")
    expectEq(SyntaxPalette.role(for: .string), .green, "palette: string")
    expectEq(SyntaxPalette.role(for: .number), .orange, "palette: number")
    expectEq(SyntaxPalette.role(for: .typeName), .blue, "palette: type")
    expectEq(SyntaxPalette.role(for: .attr), .pink, "palette: attr")
}

@MainActor func testHighlighterPreservesText() {
    let attr = SyntaxHighlighter.attributed("func x", language: "swift")
    expectEq(String(attr.characters), "func x", "highlighter: text round-trips")
}
