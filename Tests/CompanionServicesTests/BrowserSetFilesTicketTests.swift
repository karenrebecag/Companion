@testable import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionTestKit
import Darwin
import Foundation
import Testing

// H-7 P8 PR-3. What a yes for browser_set_files is bound to: the file's whole
// identity, the page it was read from, one use, and a minute.

private func approve(_ rig: BrowserToolRig, _ arguments: String) throws -> ApprovalRequest {
    let request = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    rig.runner.granted(request)
    return request
}

private func uploads(_ rig: BrowserToolRig) -> [BrowserCommand] {
    rig.channel.writes.filter { if case .setFiles = $0 { return true }; return false }
}

// MARK: - the whole File identity is in the ticket

@Test func aRewriteThatRestoresMtimeCannotSpendTheOldApproval() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let bound = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    let moved = try rewriteKeepingMtime(bound.path)
    expect(moved.ctime != bound.ctime, "ctime moved")
    expectEq(moved.mtime, bound.mtime, "mtime restored")
    expectEq(moved.size, bound.size, "same size")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "refused: \(out.output)")
    expect(uploads(rig).isEmpty, "the rewritten file is not sent")
}

@Test func anIdenticalSecondCallAfterARewriteCannotLetTheFirstTicketSendTheNewBytes() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let bound = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    try rewriteKeepingMtime(bound.path)
    // The second sheet is raised and not answered yet.
    let second = try #require(rig.runner.approval(for: rig.call(uploadTool, arguments), said: ""))
    let refused = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!refused.ok && refused.output.contains("approval_required"), "the first yes is for the old file: \(refused.output)")
    expect(uploads(rig).isEmpty, "nothing is sent while the second sheet waits")

    rig.runner.granted(second)
    let sent = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(sent.ok, "the second yes names the file as it is now: \(sent.output)")
    expectEq(uploads(rig).count, 1, "one upload")
}

@Test func aFileReplacedByAnotherInodeAtTheSamePathAndSizeIsRefused() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let bound = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    let sibling = file.directory.appendingPathComponent("swap.tmp")
    try Data("x".utf8).write(to: sibling)
    let restored = timespec(tv_sec: Int(bound.mtime / 1_000_000_000), tv_nsec: Int(bound.mtime % 1_000_000_000))
    var times = [restored, restored]
    try #require(utimensat(AT_FDCWD, sibling.path, &times, 0) == 0)
    try #require(rename(sibling.path, file.url.path) == 0)
    let after = try BrowserFilePolicy.judge(file.tilde, home: file.home)
    expect(after.inode != bound.inode, "the fixture has a new inode")
    expectEq(after.size, bound.size, "same size")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "refused: \(out.output)")
    expect(uploads(rig).isEmpty, "the replacement is not sent")
}

@Test func aFileThatChangedSizeIsRefused() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let handle = try FileHandle(forWritingTo: file.url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("more".utf8))
    try handle.close()
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "refused: \(out.output)")
    expect(uploads(rig).isEmpty, "the longer file is not sent")
}

@Test func theTicketItemCarriesEveryFieldOfTheIdentity() throws {
    let page = uploadPage()
    let element = try #require(page.elements.first)
    let base = BrowserFilePolicy.File(path: "/Users/k/cv.pdf", device: 1, inode: 2, size: 3, mtime: 4, ctime: 5)
    func item(_ file: BrowserFilePolicy.File) -> String {
        BrowserToolRunner.fileTicket("{}", tab: 12, element: element, page: page, file: file).item
    }
    var variants: [String: BrowserFilePolicy.File] = [:]
    var changed = base
    changed.device = 9
    variants["device"] = changed
    changed = base
    changed.ctime = 9
    variants["ctime"] = changed
    changed = base
    changed.mtime = 9
    variants["mtime"] = changed
    changed = base
    changed.inode = 9
    variants["inode"] = changed
    changed = base
    changed.size = 9
    variants["size"] = changed
    changed = base
    changed.path = "/Users/k/other.pdf"
    variants["path"] = changed
    for (name, file) in variants { expect(item(file) != item(base), "\(name) is part of the ticket") }
}

@Test func theTicketItemCannotBeForgedByMovingTheSeparatorBetweenFields() throws {
    let file = BrowserFilePolicy.File(path: "/Users/k/cv.pdf", device: 1, inode: 2, size: 3, mtime: 4, ctime: 5)
    func ticket(label: String, origin: String) -> ApprovalTickets.Ticket {
        let page = uploadPage(origin: origin, element: webElement(8, "input", label, inputType: "file"))
        let element = page.elements[0]
        return BrowserToolRunner.fileTicket("{}", tab: 12, element: element, page: page, file: file)
    }
    let sep = "\u{241F}"
    let one = ticket(label: "L", origin: "https://a.example\(sep)https://b.example")
    let two = ticket(label: "L\(sep)https://a.example", origin: "https://b.example")
    expect(one != two, "two different (label, origin) pairs never share an item")
}

// MARK: - one use, and only for what was approved

@Test func anApprovalIsSpentByTheFirstUpload() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let first = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(first.ok, "the first call uploads: \(first.output)")
    let second = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!second.ok && second.output.contains("approval_required"), "the same yes is not reusable: \(second.output)")
    expectEq(uploads(rig).count, 1, "one upload")
}

@Test func anApprovalDoesNotCoverAnotherPath() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let other = try UploadFile.make(named: "other.pdf", bytes: Data("x".utf8))
    defer { other.remove() }
    _ = try approve(rig, arguments)
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: try uploadArguments(path: other.tilde))
    expect(!out.ok && out.output.contains("approval_required"), "another file: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

@Test func anApprovalDoesNotCoverAnotherFileInputOnThePage() async throws {
    let two = [webElement(8, "input", "CV", inputType: "file"), webElement(9, "input", "Letter", inputType: "file")]
    let (rig, file, arguments) = try await prepared(page: uploadPage(elements: two))
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: try uploadArguments(path: file.tilde, element: 9))
    expect(!out.ok && out.output.contains("approval_required"), "the other field: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

@Test func anApprovalDoesNotCoverAnotherTab() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let page = BrowserPage(
        tab: 13, origin: crm, url: crm + "/form", title: "Form", text: "", generation: 3,
        elements: [webElement(8, "input", "CV", inputType: "file")], truncated: false)
    rig.channel.setPage(page)
    rig.channel.setTabs([
        BrowserTab(id: 12, title: "A", url: crm + "/form", active: false),
        BrowserTab(id: 13, title: "B", url: crm + "/form", active: false),
    ])
    rig.runner.leases.acquire(tab: 13, caller: "chat")
    _ = await rig.runner.execute(name: "browser_read", argumentsJSON: #"{"tab":13}"#)
    _ = try approve(rig, arguments)
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: try uploadArguments(path: file.tilde, tab: 13))
    expect(!out.ok && out.output.contains("approval_required"), "the other tab: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

@Test func anApprovalDoesNotSurviveARereadAtTheSameGenerationFromAnotherOrigin() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    let elsewhere = "https://evil.example"
    rig.channel.setPage(uploadPage(origin: elsewhere, generation: 3))
    rig.channel.setTabs([BrowserTab(id: 12, title: "Evil", url: elsewhere + "/form", active: false)])
    await rig.read()
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "another origin: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent to the other site")
}

@Test func anApprovalExpiresAfterAMinuteEvenWithAFreshRead() async throws {
    let clock = SetFilesClock(Date(timeIntervalSince1970: 1_700_000_000))
    let (rig, file, arguments) = try await prepared(now: { clock.now() })
    defer { file.remove() }
    _ = try approve(rig, arguments)
    clock.advance(61)
    await rig.read()
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "the yes is older than a minute: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

// MARK: - the sheet itself

@Test func aDeniedSheetSendsNothingAndLeavesNoTicket() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let approvals = ScriptedApprovals(answer: false)
    let guardian = ParentToolGuard(approvals: approvals)
    let denial = await guardian.check(rig.call(uploadTool, arguments), said: "yes", language: .en, tools: rig.runner)
    expect(denial?.output.contains("denied_by_user") == true, "denied_by_user: \(denial?.output ?? "nil")")
    expectEq(approvals.requests.count, 1, "the sheet was shown")
    expect(uploads(rig).isEmpty, "nothing sent")
    let stray = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(stray.output.contains("approval_required"), "a denied yes left no ticket: \(stray.output)")
    expect(uploads(rig).isEmpty, "still nothing sent")
}

@Test func anApprovedSheetThroughTheGuardUploadsOnce() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    let guardian = ParentToolGuard(approvals: ScriptedApprovals(answer: true))
    let denial = await guardian.check(rig.call(uploadTool, arguments), said: "", language: .en, tools: rig.runner)
    expect(denial == nil, "the sheet was approved")
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(out.ok, "uploaded: \(out.output)")
    expectEq(uploads(rig).count, 1, "one upload")
}

// MARK: - the live tab and the lease

@Test func aTabListingThatFailsStopsTheUploadAsStale() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    rig.channel.failTabs(with: ContractError(code: BridgeCode.timeout, message: "slow"))
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "unknown origin is not the same origin: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

@Test func aTabThatIsAbsentFromTheListingStopsTheUploadAsStale() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    _ = try approve(rig, arguments)
    rig.channel.setTabs([BrowserTab(id: 99, title: "Other", url: crm + "/form", active: false)])
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "a missing tab is not the tab that was read: \(out.output)")
    expect(uploads(rig).isEmpty, "nothing sent")
}

@Test func aTabAnotherCallerControlsRaisesNoSheetAndIsBusy() async throws {
    let (rig, file, arguments) = try await prepared()
    defer { file.remove() }
    rig.runner.leases.release(tab: 12)
    rig.runner.leases.acquire(tab: 12, caller: "bridge")
    expect(rig.runner.approval(for: rig.call(uploadTool, arguments), said: "") == nil, "no sheet for a tab that is not ours")
    let mark = rig.channel.sent.count
    let out = await rig.runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.busy), "busy: \(out.output)")
    expect(sentSince(rig, mark).isEmpty, "the extension hears nothing")
}

@Test func aBridgeCallerNeverGetsAnUploadSheetOrAnUpload() async throws {
    let file = try UploadFile.make(bytes: Data("x".utf8))
    defer { file.remove() }
    let presence = BrowserPresence()
    presence.set(.comet)
    let channel = FakeBrowserChannel(
        pages: [uploadPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/form", active: false)])
    let leases = BrowserLeases(epoch: presence.epoch)
    leases.acquire(tab: 12, caller: "bridge")
    let runner = BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "bridge")
    _ = await runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    let arguments = try uploadArguments(path: file.tilde)
    let call = ToolCallRef(id: "c", name: uploadTool, arguments: arguments)
    expect(runner.approval(for: call, said: "") == nil, "no sheet for a bridge session")
    let mark = channel.sent.count
    let out = await runner.execute(name: uploadTool, argumentsJSON: arguments)
    expect(!out.ok && out.output.contains(BridgeCode.unknownTool), "refused as the bridge refuses it: \(out.output)")
    expect(channel.writes.isEmpty && channel.sent.count == mark, "the extension hears nothing")
}
