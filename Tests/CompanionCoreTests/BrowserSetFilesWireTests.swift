import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// H-7 P8 PR-3. The upload on the wire: what the extension is sent, and what
// it may answer.

@Test func setFilesIsEncodedWithTabGenerationElementAndPathOnly() {
    let line = BrowserCodec.encode(.call(
        id: 5, .setFiles(tab: 12, generation: 3, element: 8, path: "/Users/k/Docs/cv \"final\".pdf")))
    expectEq(
        line,
        #"{"id":5,"method":"call","params":{"arguments":{"element":8,"generation":3,"path":"/Users/k/Docs/cv \"final\".pdf","tab":12},"name":"browser_set_files"}}"#,
        "exact frame: no bytes, no label, no origin")
}

@Test func setFilesPathKeepsSlashesAndUnicodeUntouched() {
    let line = BrowserCodec.encode(.call(id: 1, .setFiles(tab: 1, generation: 0, element: 0, path: "/Users/k/\u{E9}/a.pdf")))
    expect(line.contains(#""path":"/Users/k/\#u{E9}/a.pdf""#), "sin escapar la barra: \(line)")
}

@Test func theFilesSetReplyDecodesAsDone() {
    expectEq(
        BrowserCodec.decode(line: #"{"id":9,"result":{"done":"files-set"}}"#),
        .success(.done(id: 9, message: "files-set")), "files-set es un done")
}
