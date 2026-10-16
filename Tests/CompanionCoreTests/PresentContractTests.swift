import CompanionCore
import Foundation
import Testing

@Test func theSchemaTeachesEveryFamilyWithItsRule() {
    let description = PresentContract.presentDescription
    for family in PresentFamily.allCases {
        #expect(description.contains("\(family.rawValue) {"), "\(family.rawValue) has a shape line")
        #expect(description.contains(family.whenToUse), "\(family.rawValue) teaches when to use it")
        #expect(description.contains(family.whenNotToUse), "\(family.rawValue) teaches when not to use it")
    }
}

@Test func theSchemaOffersExactlyTheFamiliesTheParserKnows() throws {
    let blocks = try #require(PresentContract.presentParameters["properties"] as? [String: Any])
    let array = try #require(blocks["blocks"] as? [String: Any])
    let items = try #require(array["items"] as? [String: Any])
    let properties = try #require(items["properties"] as? [String: Any])
    let type = try #require(properties["type"] as? [String: Any])
    let offered = try #require(type["enum"] as? [String])
    #expect(offered == PresentFamily.allCases.map(\.rawValue))
}

@Test func theSpecCarriesItsSchemaAsJSON() throws {
    let spec = PresentContract.presentSpec
    #expect(spec.name == "present")
    #expect(spec.required == ["blocks"])
    let raw = try #require(spec.rawParametersJSON)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
    #expect(object["required"] as? [String] == ["blocks"])
}

@Test func findBlockNeedsAQueryAndNothingElse() {
    let spec = PresentContract.findBlockSpec
    #expect(spec.name == "find_block")
    #expect(spec.required == ["query"])
    #expect(spec.properties.map(\.name) == ["query"])
}
