import CompanionCore
import Foundation

@MainActor func codecRobustnessTests() {
    testDeeplyNestedJSON()
    testLargePayloads()
    testUnexpectedTypes()
    testInvalidUTF8()
}

@MainActor func testDeeplyNestedJSON() {
    // 200+ levels of nesting should not crash the parser.
    var nested = "1"
    for _ in 0..<200 {
        nested = "[" + nested + "]"
    }
    let event = AgentStreamCodec.parse(nested)
    expect(event == AgentStreamEvent.ignored,
           "deep nesting: 200+ levels ignored gracefully")

    // Deeply nested object should also degrade safely.
    var nestedObj = "{\"a\":1}"
    for _ in 0..<50 {
        nestedObj = "{\"x\":" + nestedObj + "}"
    }
    let event2 = AgentStreamCodec.parse(nestedObj)
    expect(event2 == AgentStreamEvent.ignored,
           "deep object nesting: degrades safely")
}

@MainActor func testLargePayloads() {
    // Several MB of JSON should not crash.
    let largeString = String(repeating: "a", count: 1_000_000)
    let payload = #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(largeString)"}]}}"#
    let event = AgentStreamCodec.parse(payload)
    expect(event == AgentStreamEvent.ignored,
           "large payload: 1MB handled without crash")

    // Large gallery with many images.
    var images = ""
    for i in 0..<1000 {
        images += #"{"url":"https://example.com/img\#(i).jpg"},"#
    }
    images = String(images.dropLast()) // Remove trailing comma
    let galleryJSON = #"{"images":[\#(images)]}"#
    let gallery = CompanionBlocks.gallery(galleryJSON)
    expect(gallery != nil || gallery == nil, // Just verify no crash
           "large gallery: 1000 images handled without crash")
}

@MainActor func testUnexpectedTypes() {
    // control_request with string instead of object for "request".
    let badRequest = #"{"type":"control_request","request_id":"r-1","request":"not an object"}"#
    let event1 = AgentStreamCodec.parse(badRequest)
    expect(event1 == AgentStreamEvent.ignored,
           "unexpected type: request as string ignored")

    // control_request with number for request_id.
    let badID = #"{"type":"control_request","request_id":123,"request":{"subtype":"can_use_tool"}}"#
    let event2 = AgentStreamCodec.parse(badID)
    expect(event2 == AgentStreamEvent.ignored,
           "unexpected type: request_id as number ignored")

    // Assistant message with null content.
    let nullContent = #"{"type":"assistant","message":{"content":null}}"#
    let event3 = AgentStreamCodec.parse(nullContent)
    expect(event3 == AgentStreamEvent.ignored,
           "unexpected type: content null ignored")

    // Locations with string instead of number for lat.
    let badLat = #"{"locations":[{"name":"x","lat":"51.5","lng":0}]}"#
    let locs = CompanionBlocks.locations(badLat)
    expect(locs == nil,
           "unexpected type: lat as string rejected")

    // Gallery item with null path and null url.
    let nullImage = #"{"images":[{"path":null,"url":null}]}"#
    let gallery = CompanionBlocks.gallery(nullImage)
    expect(gallery == nil,
           "unexpected type: both path and url null rejected")
}

@MainActor func testInvalidUTF8() {
    // Truncated UTF-8 sequences embedded in JSON should not crash.
    // A malformed UTF-8 byte sequence: 0xFF is invalid.
    let invalidUTF8: [UInt8] = [
        0x7B, 0x22, 0x74, 0x79, 0x70, 0x65, 0x22, 0x3A, 0x22, 0x75, 0x73, 0x65, 0x72, 0x22, 0x7D, 0xFF
    ]
    guard let str = String(bytes: invalidUTF8, encoding: .utf8) else {
        expect(true, "invalid UTF-8: correctly rejected at encoding stage")
        return
    }
    let event = AgentStreamCodec.parse(str)
    expect(event == AgentStreamEvent.ignored,
           "invalid UTF-8: degraded safely after encoding")

    // Truncated multi-byte UTF-8 sequence (incomplete emoji).
    let truncated: [UInt8] = [
        0x7B, 0x22, 0x78, 0x22, 0x3A, 0xF0, 0x9F // Incomplete UTF-8 emoji
    ]
    if let str = String(bytes: truncated, encoding: .utf8) {
        let event2 = AgentStreamCodec.parse(str)
        expect(event2 == AgentStreamEvent.ignored,
               "truncated UTF-8: handled gracefully")
    } else {
        expect(true, "truncated UTF-8: correctly rejected at encoding")
    }
}
