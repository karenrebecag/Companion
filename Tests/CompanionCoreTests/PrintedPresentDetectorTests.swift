import CompanionCore
import Foundation
import Testing

@Test func aPrintedCallIsFoundAndItsProseKept() throws {
    let reply = """
    Aquí va el resumen.
    {"blocks":[{"type":"ranking","items":[{"label":"a","value":3}]}]}
    Eso es todo.
    """
    let hit = try #require(PrintedPresentDetector.detect(in: reply))
    #expect(hit.prose == "Aquí va el resumen.\n\nEso es todo.")
    #expect(hit.outcome.blocks.count == 1)
}

@Test func aFencedCallLeavesNoEmptyFenceBehind() throws {
    let reply = "Resumen.\n```json\n{\"blocks\":[{\"type\":\"divider\"}]}\n```"
    let hit = try #require(PrintedPresentDetector.detect(in: reply))
    #expect(hit.prose == "Resumen.")
}

@Test func braceInsideAStringDoesNotCloseTheObject() throws {
    let reply = #"{"blocks":[{"type":"paragraph","text":"usa } y { aquí"}]}"#
    let hit = try #require(PrintedPresentDetector.detect(in: reply))
    #expect(hit.outcome.blocks == [.paragraph("usa } y { aquí")])
}

@Test func anOrdinaryJSONExampleIsLeftAlone() {
    let reply = "Así se ve la config:\n```json\n{\"blocks\": \"no es una lista\", \"name\": \"x\"}\n```"
    #expect(PrintedPresentDetector.detect(in: reply) == nil)
}

@Test func aReplyCutMidJSONIsNotACall() {
    #expect(PrintedPresentDetector.detect(in: "{\"blocks\":[{\"type\":\"divider\"}") == nil)
}

@Test func theCorrectionNamesThePresentTool() {
    #expect(PrintedPresentDetector.correction.contains("present tool"))
}
