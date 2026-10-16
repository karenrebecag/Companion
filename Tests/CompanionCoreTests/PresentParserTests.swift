import CompanionCore
import Foundation
import Testing

private func parse(_ json: String) -> PresentOutcome {
    let object = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
    return PresentParser.parse(arguments: object)
}

@Test func aValidTableParsesWithItsNumbersAsNumbers() {
    let outcome = parse("""
    {"blocks":[{"type":"table","columns":["name","n"],"rows":[["a",12],["b",9]]}]}
    """)
    #expect(outcome.issues.isEmpty)
    #expect(outcome.blocks == [.table(PresentTable(
        title: nil, columns: ["name", "n"],
        rows: [[.text("a"), .number(12)], [.text("b"), .number(9)]]))])
}

@Test func aRowOfTheWrongWidthIsDroppedAndTheRestKept() {
    let outcome = parse("""
    {"blocks":[{"type":"table","columns":["a","b"],"rows":[["1","2"],["only one"]]}]}
    """)
    guard case .table(let table) = outcome.blocks.first else {
        Issue.record("the table did not survive")
        return
    }
    #expect(table.rows.count == 1)
}

@Test func anUnknownTypeFallsBackToItsTextNotAnError() {
    let outcome = parse("""
    {"blocks":[{"type":"hologram","text":"aquí va el texto"}]}
    """)
    #expect(outcome.blocks == [.paragraph("aquí va el texto")])
    #expect(outcome.issues.count == 1)
    #expect(outcome.issues.first?.type == "hologram")
}

@Test func aNearWordFamilyIsParsedAsTheFamilyItNames() {
    let outcome = parse("""
    {"blocks":[{"type":"pie","parts":[{"label":"a","value":2},{"label":"b","value":1}]}]}
    """)
    #expect(outcome.issues.isEmpty)
    guard case .partsOfWhole(let parts) = outcome.blocks.first else {
        Issue.record("pie did not parse as partsOfWhole")
        return
    }
    #expect(parts.parts.count == 2)
}

@Test func aBlockWithBrokenFieldsWithoutTextBecomesVisibleJSON() {
    let outcome = parse("""
    {"blocks":[{"type":"partsOfWhole","parts":[{"label":"a","value":-4}]}]}
    """)
    guard case .codeOrDiff(let code) = outcome.blocks.first else {
        Issue.record("an unreadable block must stay visible as code")
        return
    }
    #expect(code.language == "json")
    #expect(outcome.issues.first?.reason == "partsOfWhole fields did not validate")
}

@Test func negativeValuesNeverReachAChart() {
    let outcome = parse("""
    {"blocks":[{"type":"partsOfWhole","parts":[{"label":"a","value":-1},{"label":"b","value":3}]}]}
    """)
    #expect(outcome.blocks == [.partsOfWhole(PresentParts(
        title: nil, parts: [PresentPart(label: "b", value: 3)]))])
}

@Test func aBooleanIsNotANumber() {
    let outcome = parse("""
    {"blocks":[{"type":"metrics","items":[{"label":"ok","value":true}]}]}
    """)
    guard case .codeOrDiff = outcome.blocks.first else {
        Issue.record("a boolean metric must fall back to visible code")
        return
    }
}

@Test func unsafeLinksAndCoordinatesAreDroppedFromPlaces() {
    let outcome = parse("""
    {"blocks":[{"type":"places","places":[
      {"name":"ok","lat":19.4,"lng":-99.1,"url":"javascript:alert(1)"},
      {"name":"far","lat":120,"lng":0},
      {"name":"web","lat":1,"lng":2,"url":"http://insecure.example"}
    ]}]}
    """)
    guard case .places(let places) = outcome.blocks.first else {
        Issue.record("places did not parse")
        return
    }
    #expect(places.places.map(\.name) == ["ok", "web"])
    #expect(places.places.allSatisfy { $0.url == nil })
}

@Test func anIsoDateBecomesACountableStartAndProseDoesNot() {
    let outcome = parse("""
    {"blocks":[{"type":"events","events":[{"title":"demo","start":"2030-01-02T10:00:00Z"}]},
               {"type":"timeline","events":[{"title":"x","when":"mañana"}]}]}
    """)
    guard case .events(let events) = outcome.blocks[0], case .timeline(let timeline) = outcome.blocks[1] else {
        Issue.record("families did not parse")
        return
    }
    #expect(events.events.first?.startsAt != nil)
    #expect(timeline.events.first?.startsAt == nil)
}

@Test func aBlockPastTheLimitIsTruncatedWithAnIssue() {
    let blocks = Array(repeating: #"{"type":"divider"}"#, count: PresentContract.Limits.maxBlocks + 2)
    let outcome = parse(#"{"blocks":[\#(blocks.joined(separator: ","))]}"#)
    #expect(outcome.blocks.count == PresentContract.Limits.maxBlocks)
    #expect(outcome.issues.contains { $0.index == -1 })
}

@Test func aCallWithoutBlocksIsRefusedWithoutCrashing() {
    let outcome = PresentParser.parse(arguments: [:])
    #expect(outcome.blocks.isEmpty)
    #expect(outcome.issues.map(\.reason) == ["missing blocks array"])
}

@Test func aSafeHTTPSSourceKeepsItsTitleAndAnUnsafeOneIsDropped() {
    let outcome = parse("""
    {"blocks":[{"type":"webSources","sources":[
      {"title":"doc","url":"https://example.com/a"},
      {"title":"bad","url":"http://example.com/b"}
    ]}]}
    """)
    #expect(outcome.blocks == [.webSources([PresentSource(title: "doc", url: "https://example.com/a")])])
}
