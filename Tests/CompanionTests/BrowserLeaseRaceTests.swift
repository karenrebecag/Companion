import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 18b review follow-ups: a listing that was asked for before a tab was
// acquired must not prune it, a delayed give-back must not undo a newer take,
// a spawned child is judged by the gate on the first write, and the Settings
// "remove" leaves nothing controlled.

private struct Rig {
    let chat: BrowserToolRunner
    let bridge: BrowserToolRunner
    let channel: FakeBrowserChannel
    let presence: BrowserPresence
    let clock: LeaseClock
    let leases: BrowserLeases

    func count(_ match: (BrowserCommand) -> Bool) -> Int { channel.sent.map(\.command).filter(match).count }
    var releases: Int { count { if case .release = $0 { return true }; return false } }
}

private func rig(tabs: [BrowserTab]? = nil, pages: [BrowserPage] = [crmPage()]) -> Rig {
    let presence = BrowserPresence()
    presence.set(.comet)
    let clock = LeaseClock()
    let channel = FakeBrowserChannel(
        pages: pages, tabs: tabs ?? [BrowserTab(id: 12, title: "Gmail", url: crm + "/a", active: false)])
    let leases = BrowserLeases(epoch: presence.epoch, now: { clock.now })
    return Rig(
        chat: BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "chat"),
        bridge: BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "bridge"),
        channel: channel, presence: presence, clock: clock, leases: leases)
}

private let tab12 = #"{"tab":12}"#

private func call(_ name: String, _ arguments: String) -> ToolCallRef {
    ToolCallRef(id: "c", name: name, arguments: arguments)
}

private func isTabs(_ command: BrowserCommand) -> Bool {
    if case .tabs = command { return true }
    return false
}

private func isRelease(_ command: BrowserCommand) -> Bool {
    if case .release = command { return true }
    return false
}

// MARK: - M1: a stale listing

@Test func aListingAskedForBeforeATabWasOpenedDoesNotPruneIt() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    let gate = r.channel.hold(isTabs)
    let listing = Task { await r.chat.execute(name: "browser_tabs", argumentsJSON: "{}") }
    let inFlight = await gate.waitUntilReached()
    expect(inFlight, "the listing is in flight")
    let address = crm + "/fresh"
    if let sheet = r.chat.approval(for: call("browser_open", #"{"url":"\#(address)"}"#), said: address) {
        r.chat.granted(sheet)
    }
    let again = await r.chat.execute(name: "browser_open", argumentsJSON: #"{"url":"\#(address)"}"#)
    expect(again.ok, "the tab opened while the listing was in flight")
    gate.open()
    _ = await listing.value
    expectEq(r.leases.owner(of: 41), "chat", "the older listing does not know tab 41, and must not drop it")
    expectEq(r.leases.owner(of: 12), "chat", "12 is in the listing and stays")
}

@Test func aTabTheListingNeverShowedAndWasAcquiredEarlierIsStillPruned() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs([])
    _ = await r.chat.execute(name: "browser_tabs", argumentsJSON: "{}")
    expectEq(r.leases.owner(of: 12), nil, "acquired before the listing was asked: gone tabs are still dropped")
}

// MARK: - M2: a delayed give-back

private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}

private func makeHost(
    channel: FakeBrowserChannel, sweepEvery: Duration = .seconds(30), now: @escaping @Sendable () -> Date = { Date() }
) -> BrowserHost {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("r18b-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let host = BrowserHost(
        directory: root.appendingPathComponent("b", isDirectory: true),
        installer: NativeHostInstaller(home: root, executable: root),
        language: { .en }, commanding: channel, sweepEvery: sweepEvery, now: now)
    host.presence.set(.chrome)
    return host
}

@Test func aDelayedGiveBackDoesNotUndoATabTakenAgainMeanwhile() async {
    let channel = FakeBrowserChannel(
        pages: [crmPage(), BrowserPage(
            tab: 13, origin: crm, url: crm + "/b", title: "B", text: "b", generation: 1, elements: [], truncated: false)],
        tabs: [
            BrowserTab(id: 12, title: "A", url: crm + "/a", active: false),
            BrowserTab(id: 13, title: "B", url: crm + "/b", active: false)])
    let host = makeHost(channel: channel)
    let bridge = host.bridgeTools(parent: NoTools())
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    for tab in [12, 13] {
        let take = call("browser_take", #"{"tab":\#(tab)}"#)
        if let sheet = bridge.approval(for: take, said: "") { bridge.granted(sheet) }
        _ = await bridge.execute(name: "browser_take", argumentsJSON: take.arguments)
    }
    let gate = channel.hold(isRelease)
    let giveBack = host.bridgeSessionChanged()
    let inFlight = await gate.waitUntilReached()
    expect(inFlight, "the first release is in flight")
    let took = await conversation.execute(name: "browser_take", argumentsJSON: #"{"tab":13}"#)
    expect(took.ok, "the next session's owner takes 13 while the give-back is still going")
    gate.open()
    await giveBack.value
    let released = channel.sent.map(\.command).filter(isRelease)
    expectEq(released.count, 1, "only 12 is given back: 13 has a new owner")
    let read = await conversation.execute(name: "browser_read", argumentsJSON: #"{"tab":13}"#)
    expect(read.ok, "and the new owner still controls 13")
}

// MARK: - M3: the first write to a spawned child

private func family(clock: LeaseClock, url: String = crm + "/new") -> [BrowserTab] {
    [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false, controlled: true),
     BrowserTab(id: 20, title: "", url: url, active: false, controlled: false, opener: 12,
                createdAt: clock.now.addingTimeInterval(4))]
}

@Test func aFirstNavigateOnASpawnedChildGetsItsSheetNotADeadEnd() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs(family(clock: r.clock))
    _ = await r.chat.execute(name: "browser_tabs", argumentsJSON: "{}")
    r.clock.advance(5)
    let arguments = #"{"tab":20,"url":"https://other.example/x"}"#
    guard let sheet = r.chat.approval(for: call("browser_navigate", arguments), said: "") else {
        Issue.record("the gate judges the child that would be adopted"); return
    }
    r.chat.granted(sheet)
    let out = await r.chat.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(out.ok, "adopted, then navigated with the user's yes: \(out.output)")
    expectEq(r.leases.owner(of: 20), "chat", "the child is the chat's")
}

@Test func aFirstClickOnAnUnreadSpawnedChildAsksToReadNotForApproval() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs(family(clock: r.clock))
    _ = await r.chat.execute(name: "browser_tabs", argumentsJSON: "{}")
    r.clock.advance(5)
    let arguments = #"{"tab":20,"element":1}"#
    let asked = r.chat.approval(for: call("browser_click", arguments), said: "")
    expect(asked == nil, "no page of the child was read: nothing to judge yet")
    let out = await r.chat.execute(name: "browser_click", argumentsJSON: arguments)
    expect(out.output.contains(BridgeCode.staleId), "read first: \(out.output)")
    expect(!out.output.contains("approval_required"), "never the approval dead end")
    expect(r.channel.writes.isEmpty, "no write sent")
}

@Test func aTabTheListingDoesNotShowAsSpawnedStillGetsNoSheet() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    let arguments = #"{"tab":20,"url":"https://other.example/x"}"#
    expect(r.chat.approval(for: call("browser_navigate", arguments), said: "") == nil, "no snapshot: no sheet")
    let out = await r.chat.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(!out.ok && r.channel.writes.isEmpty, "and nothing is sent")
}

@Test func aChildFirstSeenByTheWriteItselfIsAdoptedAndToldToRetryNotRefusedSilently() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs(family(clock: r.clock))
    r.clock.advance(5)
    let arguments = #"{"tab":20,"url":"https://other.example/x"}"#
    _ = r.chat.approval(for: call("browser_navigate", arguments), said: "")
    let out = await r.chat.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "fail closed: no yes was ever asked for")
    expect(out.output.contains("again"), "but it says what to do: \(out.output)")
    expectEq(r.leases.owner(of: 20), "chat", "the child is adopted, so the retry gets its sheet")
    expect(r.chat.approval(for: call("browser_navigate", arguments), said: "") != nil, "the retry asks")
}

// MARK: - criterion 5 from Settings

@Test func removingTheBrowserFromSettingsLeavesNothingControlled() async throws {
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let host = makeHost(channel: channel)
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    _ = await conversation.execute(name: "browser_take", argumentsJSON: tab12)
    let before = channel.sent.map(\.command).count
    _ = host.remove()
    host.presence.set(nil)
    host.presence.set(.chrome)
    let read = await conversation.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "after remove and a new connection: take again")
    let readFrames = channel.sent.map(\.command).dropFirst(before).filter { if case .read = $0 { return true }; return false }
    expect(readFrames.isEmpty, "zero read frames")
}

// MARK: - release with a failing extension

@Test func aReleaseTheExtensionAnswersWithFailureStillClearsTheLease() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.failReleases(with: ContractError(code: "tab_gone", message: "no such tab"))
    let out = await r.chat.execute(name: "browser_release", argumentsJSON: tab12)
    expect(!out.ok, "the failure is reported")
    expectEq(r.leases.owner(of: 12), nil, "but the caller gave the tab up")
    expectEq(r.releases, 1, "one release frame")
}
