import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Audit M7 / H5 (Companion side): a reply over the 64 KB line is refused by
// the shim, and an agent cannot tell a cut result from a whole one.

private func result(_ output: String, target: String = "Notes") -> BridgeCallResult {
    BridgeCallResult(ParentToolOutcome(ok: true, output: output, target: target, tool: "see"))
}

@Test func aShortOutputIsUnchanged() {
    expectEq(result("window \"Inbox\"").output, "window \"Inbox\"", "nothing to cut")
}

@Test func aLongOutputIsCutAndSaysSo() {
    let cut = result(String(repeating: "a", count: 100_000)).output
    expect(cut.hasSuffix(BridgeCallResult.truncationNote), "ends with the note: \(cut.suffix(120))")
    let kept = cut.dropLast(BridgeCallResult.truncationNote.count)
    expectEq(kept.utf8.count, BridgeCallResult.maxOutputBytes, "kept up to the cap")
    expect(BridgeCallResult.truncationNote.contains("result is partial"), "says the result is partial")
}

@Test func theCutCountsBytesAndKeepsWholeCharacters() {
    let cut = result(String(repeating: "€", count: 20_000)).output
    let kept = cut.dropLast(BridgeCallResult.truncationNote.count)
    expect(kept.utf8.count <= BridgeCallResult.maxOutputBytes, "bytes, not characters: \(kept.utf8.count)")
    expect(kept.allSatisfy { $0 == "€" }, "no character cut in half")
}

@Test func theWorstCaseOutputStillFitsOneLine() {
    // Quotes, backslashes, slashes and newlines each escape to two bytes.
    let output = String(repeating: "\"\\/\n", count: 50_000)
    let line = BridgeCodec.encode(.call(id: 1, result(output, target: String(repeating: "/", count: 50_000))))
    expect(line.utf8.count <= BridgeCodec.maxLineBytes, "encoded: \(line.utf8.count) bytes")
}

@Test func aLongTargetIsCutToo() {
    expect(result("ok", target: String(repeating: "t", count: 50_000)).target.utf8.count
           <= BridgeCallResult.maxTargetBytes, "target capped")
}

@Test func theCapIsExactAtItsBoundary() {
    let atCap = String(repeating: "a", count: BridgeCallResult.maxOutputBytes)
    expectEq(result(atCap).output, atCap, "exactly at the cap: untouched, no note")
    let over = result(atCap + "b").output
    expect(over.hasSuffix(BridgeCallResult.truncationNote), "one byte over: the note")
    expectEq(over.dropLast(BridgeCallResult.truncationNote.count).utf8.count, BridgeCallResult.maxOutputBytes,
             "one byte over: kept to the cap")
}

@Test func aCutLandingInsideACharacterStopsJustBeforeIt() {
    // One leading byte shifts 4-byte emoji so the cap falls inside one.
    let cut = result("a" + String(repeating: "😀", count: 10_000)).output
    let kept = cut.dropLast(BridgeCallResult.truncationNote.count)
    expect(kept.utf8.count <= BridgeCallResult.maxOutputBytes && kept.utf8.count > BridgeCallResult.maxOutputBytes - 4,
           "within one character of the cap: \(kept.utf8.count)")
    expect(kept.dropFirst().allSatisfy { $0 == "😀" }, "whole emoji only")
    let target = result("ok", target: "a" + String(repeating: "€", count: 1_000)).target
    expect(target.utf8.count <= BridgeCallResult.maxTargetBytes && target.dropFirst().allSatisfy { $0 == "€" },
           "the target cut keeps whole characters")
}

@Test func aFailedOutcomeIsCappedAndKeepsItsShape() {
    let failed = BridgeCallResult(ParentToolOutcome(ok: false, output: String(repeating: "x", count: 100_000)))
    expect(!failed.ok, "ok stays false")
    expect(failed.output.hasSuffix(BridgeCallResult.truncationNote), "a refusal is capped too")
    expect(failed.tool == nil, "a missing tool stays missing")
}

@Test func oneGiantCharacterStillLeavesSomethingToRead() {
    // One base letter carrying 30k combining marks is a single grapheme over the cap.
    let zalgo = "a" + String(repeating: "\u{0301}", count: 30_000) + " tail"
    let kept = result(zalgo).output.dropLast(BridgeCallResult.truncationNote.count)
    expect(!kept.isEmpty, "not an empty result plus the note")
    expect(kept.utf8.count <= BridgeCallResult.maxOutputBytes, "still within the cap: \(kept.utf8.count)")
}
