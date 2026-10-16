import CompanionCore
import Foundation
import Testing

@Test func aPresentCallSurvivesTheFenceAndRendersTheSameWayTwice() throws {
    let call = #"{"blocks":[{"type":"ranking","items":[{"label":"a","value":2}]}]}"#
    let body = try #require(PresentFence.body(argumentsJSON: call))
    // The saved text is canonical, so the same call always stores the same text.
    #expect(PresentFence.body(argumentsJSON: call) == body)
    let first = try #require(PresentFence.renders(body: body))
    let second = try #require(PresentFence.renders(body: body))
    #expect(first == second)
    guard case .bar = first.first else {
        Issue.record("a ranking must render as a bar")
        return
    }
}

@Test func aCallWithoutBlocksIsNotStored() {
    #expect(PresentFence.body(argumentsJSON: #"{"items":[]}"#) == nil)
    #expect(PresentFence.body(argumentsJSON: "not json") == nil)
}

@Test func aBodyThatNoLongerParsesRendersNothing() {
    #expect(PresentFence.renders(body: "{\"blocks\":") == nil)
    #expect(PresentFence.renders(body: #"{"blocks":[]}"#) == nil)
}

@Test func onlyASettledPresentFenceBecomesAPresentedAnswerBlock() throws {
    let body = try #require(PresentFence.body(argumentsJSON: #"{"blocks":[{"type":"divider"}]}"#))
    let settled = "```\(PresentFence.language)\n\(body)\n```"
    let blocks = AnswerBlocks.blocks(from: settled)
    #expect(blocks.contains { if case .presented = $0 { true } else { false } })
    // A fence the text ends inside is still arriving: it stays code, never a card.
    let cut = AnswerBlocks.blocks(from: "```\(PresentFence.language)\n\(body)")
    #expect(!cut.contains { if case .presented = $0 { true } else { false } })
}

@Test func findBlockAnswersWithTheShapeToEmit() {
    let reply = BlockCatalog.reply(for: BlockCatalog.find("heatmap"))
    #expect(reply.hasPrefix("activity-heatmap:"))
    #expect(reply.contains("days[{date"))
    #expect(BlockCatalog.reply(for: []).contains("present family"))
}
