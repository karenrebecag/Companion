import CompanionCore
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// H-7 P8 PR-3. The channel hands an upload only the shape it asked for.

private let upload = BrowserCommand.setFiles(tab: 12, generation: 3, element: 8, path: "/Users/k/cv.pdf")

private let pageReply = #"{"page":{"tab":12,"origin":"https://crm.example","url":"https://crm.example/","title":"T","text":"","generation":3,"truncated":false,"elements":[]}}"#
private let tabsReply = #"{"tabs":[{"id":12,"title":"Inbox","url":"https://mail.example/","active":true}]}"#
private let openedReply = #"{"tab":{"id":40,"title":"","url":"https://crm.example/","active":false}}"#

@Test func anUploadIsSentAsOneCallAndAcceptsTheDoneReply() async throws {
    let rig = try makeBrowserRig()
    defer { rig.listener.stop() }
    let client = try await browserConnected(rig)
    defer { client.close() }
    let pending = Task { await rig.channel.send(upload, timeout: .seconds(5)) }
    let line = await client.line()
    expect(line?.contains(#""name":"browser_set_files""#) == true, "names the tool: \(line ?? "nil")")
    expect(line?.contains(#""path":"/Users/k/cv.pdf""#) == true, "carries the path")
    let id = try #require(browserCallID(line))
    try client.send(#"{"id":\#(id),"result":{"done":"files-set"}}"#)
    expectEq(await pending.value, .success(.done(id: id, message: "files-set")), "done is the one accepted reply")
}

@Test func anUploadAnsweredWithAnotherShapeIsABadFrame() async throws {
    for (label, result) in [("page", pageReply), ("tabs", tabsReply), ("opened", openedReply)] {
        let rig = try makeBrowserRig()
        defer { rig.listener.stop() }
        let client = try await browserConnected(rig)
        defer { client.close() }
        let pending = Task { await rig.channel.send(upload, timeout: .seconds(5)) }
        let id = try #require(browserCallID(await client.line()))
        try client.send(#"{"id":\#(id),"result":\#(result)}"#)
        expectEq(
            await pending.value,
            .failure(ContractError(code: BridgeCode.badFrame, message: "Unexpected reply for browser_set_files")),
            "\(label) reply to an upload")
    }
}
