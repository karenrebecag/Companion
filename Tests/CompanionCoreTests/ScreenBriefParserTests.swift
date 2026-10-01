import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func screenBriefParserTests() {
    testParsesSummaryAndSnippets()
    testGarbageIsEmpty()
}

@MainActor func testParsesSummaryAndSnippets() {
    let raw = """
    SUMMARY: Safari shows a news headline about markets.
    SNIPPETS:
    [Safari] "Markets rally"
    [Mail] inbox zero
    """
    let brief = ScreenBriefParser.parse(raw)
    expectEq(brief.summary, "Safari shows a news headline about markets.", "parser: SUMMARY")
    expectEq(brief.snippets.count, 2, "parser: dos snippets")
    expectEq(brief.snippets[0].app, "Safari", "parser: app del primero")
    expectEq(brief.snippets[0].text, "Markets rally", "parser: texto quoted")
    expectEq(brief.snippets[1].app, "Mail", "parser: app del segundo")
    expectEq(brief.snippets[1].text, "inbox zero", "parser: texto sin comillas")
    expect(!brief.pending, "parser: no pending")
}

@MainActor func testGarbageIsEmpty() {
    let empty = ScreenBriefParser.parse("")
    expect(empty.summary == nil && empty.snippets.isEmpty, "parser: vacío")
    let junk = ScreenBriefParser.parse("I cannot follow the format sorry")
    expect(junk.summary == nil && junk.snippets.isEmpty, "parser: basura no inventa")
}
