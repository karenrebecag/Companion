import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test func screenCaptureTests() async {
    await testCaptureSkipsWhenUntrusted()
    testVisionJSONReadsContent()
}

func testCaptureSkipsWhenUntrusted() async {
    let box = GrabBox()
    let capture = ScreenCapture(
        bundleID: "test",
        trusted: { false },
        grab: {
            box.hit = true
            return Data([1])
        })
    let data = await capture.jpeg()
    expect(data == nil, "captura: sin permiso no hay JPEG")
    expect(!box.hit, "captura: ni siquiera intenta")
}

func testVisionJSONReadsContent() {
    let json = """
    {"choices":[{"message":{"content":"SUMMARY: a window\\nSNIPPETS:\\n[Safari] \\"Hi\\""}}]}
    """
    let text = ScreenVision.content(from: Data(json.utf8))
    expect(text?.contains("SUMMARY:") == true, "visión: lee el content")
    let brief = ScreenBriefParser.parse(text ?? "")
    expectEq(brief.summary, "a window", "visión: el parser sigue")
    expectEq(brief.snippets.first?.app, "Safari", "visión: snippet")
}

private final class GrabBox: @unchecked Sendable {
    var hit = false
}
