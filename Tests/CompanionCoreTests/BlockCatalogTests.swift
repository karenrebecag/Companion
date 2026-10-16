import CompanionCore
import Testing

@Test func aQueryFindsTheBlockByItsKeywords() {
    #expect(BlockCatalog.find("live stock prices").first?.id == "market-terminal")
    #expect(BlockCatalog.find("API response").first?.id == "json-viewer")
}

@Test func anEmptyOrUnmatchedQueryFindsNothing() {
    #expect(BlockCatalog.find("").isEmpty)
    #expect(BlockCatalog.find("zzzz qqqq").isEmpty)
}

@Test func entriesRankByMatchedWordsAndTheLimitHolds() {
    // slope-chart matches two words ("change", "rank"), waffle-chart one ("share").
    let matches = BlockCatalog.find("change share rank", limit: 2)
    #expect(matches.count == 2)
    #expect(matches.map(\.id) == ["slope-chart", "waffle-chart"])
}

@Test func everyEntryHasAShapeAndAUse() {
    for entry in BlockCatalog.entries {
        #expect(!entry.whenToUse.isEmpty, "\(entry.id) says when to use it")
        #expect(!entry.shape.isEmpty, "\(entry.id) says what data it takes")
    }
}
