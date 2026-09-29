import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 18 PR2 security review: M2 (same-origin navigation is a GET that can
// change state), M3 (conversation and bridge must not share tickets), L4 (a
// reconnect must not inherit the last connection's pages or approvals).

private func navigateArgs(_ url: String) -> String { #"{"tab":12,"url":"\#(url)"}"# }

// MARK: - M2

@Test func sameOriginNavigationToADestructivePathAsksAndSendsNothingWhenDenied() async {
    for path in ["/account/delete?confirm=1", "/logout", "/unsubscribe?all", "/sign-out", "/settings/deleteAccount"] {
        let rig = makeToolRig()
        await rig.read()
        let arguments = navigateArgs(crm + path)
        expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "open the page") != nil,
               "\(path): asks")
        let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
        expect(!out.ok && out.output.contains("approval_required"), "\(path): denied is not run")
        expect(rig.channel.writes.isEmpty, "\(path): zero frames")
    }
}

@Test func sameOriginNavigationToADestructivePathActsWhenTheUserSaidIt() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = navigateArgs(crm + "/account/delete")
    expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "delete my account") == nil,
           "said it: no sheet")
    let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
    expect(out.ok, "runs")
}

@Test func fragmentOnlyAndPlainSameOriginNavigationsActWithoutASheet() async {
    // The cached page is crm + "/a".
    for target in ["/a#section", "/search?q=x", "/a?page=2", "/reports/2026"] {
        let rig = makeToolRig()
        await rig.read()
        let arguments = navigateArgs(crm + target)
        expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "") == nil, "\(target): no sheet")
        let out = await rig.runner.execute(name: "browser_navigate", argumentsJSON: arguments)
        expect(out.ok, "\(target): runs")
    }
}

@Test func aFragmentOnlyChangeOnADestructivePageActsBecauseNothingNewIsRequested() async {
    var page = crmPage()
    page.url = crm + "/account/delete?confirm=1"
    let rig = makeToolRig(page: page)
    await rig.read()
    let arguments = navigateArgs(crm + "/account/delete?confirm=1#top")
    expect(rig.runner.approval(for: rig.call("browser_navigate", arguments), said: "") == nil, "same path and query")
}

// MARK: - M3

private func hostWithFakeChannel() throws -> (host: BrowserHost, channel: FakeBrowserChannel) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("m3-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let host = BrowserHost(
        directory: root.appendingPathComponent("b", isDirectory: true),
        installer: NativeHostInstaller(home: root, executable: root),
        language: { .en }, commanding: channel)
    host.presence.set(.chrome)
    return (host, channel)
}

private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}

@Test func aTicketGrantedInConversationCannotBeRedeemedByTheBridge() async throws {
    let (host, channel) = try hostWithFakeChannel()
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    let bridge = host.bridgeTools(parent: NoTools())
    let read = #"{"tab":12}"#
    _ = await conversation.execute(name: "browser_read", argumentsJSON: read)
    _ = await bridge.execute(name: "browser_read", argumentsJSON: read)
    let arguments = #"{"tab":12,"element":2}"#
    let call = ToolCallRef(id: "c", name: "browser_click", arguments: arguments)
    guard let request = conversation.approval(for: call, said: "") else { Issue.record("no sheet"); return }
    conversation.granted(request)
    let out = await bridge.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "the peer finds no ticket")
    expect(channel.writes.isEmpty, "zero frames sent")
    let own = await conversation.execute(name: "browser_click", argumentsJSON: arguments)
    expect(own.ok, "the conversation still spends its own yes")
}

@Test func theBridgeDoesNotSeeAPageOnlyTheConversationRead() async throws {
    let (host, channel) = try hostWithFakeChannel()
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    let bridge = host.bridgeTools(parent: NoTools())
    _ = await conversation.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    let out = await bridge.execute(name: "browser_click", argumentsJSON: #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "no shared page cache")
    expect(channel.writes.isEmpty, "zero frames")
}

// MARK: - L4

@Test func aReconnectDropsTheCachedPagesOfTheLastConnection() async {
    let rig = makeToolRig()
    await rig.read()
    rig.presence.set(nil)
    rig.presence.set(.comet)
    let out = await rig.run("browser_click", #"{"tab":12,"element":1}"#)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "the old page is gone: read again")
    expect(rig.channel.writes.isEmpty, "zero frames")
}

@Test func aReconnectDropsTicketsGrantedBeforeIt() async {
    let rig = makeToolRig()
    await rig.read()
    let arguments = #"{"tab":12,"element":2}"#
    if let request = rig.runner.approval(for: rig.call("browser_click", arguments), said: "") { rig.runner.granted(request) }
    rig.presence.set(nil)
    rig.presence.set(.comet)
    await rig.read()
    let out = await rig.runner.execute(name: "browser_click", argumentsJSON: arguments)
    expect(!out.ok && out.output.contains("approval_required"), "a yes does not outlive its connection")
    expect(rig.channel.writes.isEmpty, "zero frames")
}

// MARK: - M2 at the policy

private func nav(_ current: String?, _ raw: String, said: String = "") -> Result<HandsVerdict, ContractError> {
    BrowserPolicy.navigateVerdict(
        from: current.flatMap { URL(string: $0) }.map { "\($0.scheme ?? "")://\($0.host ?? "")" },
        currentURL: current, to: raw, said: said)
}

@Test func sameOriginNavigationIsJudgedAgainstTheCurrentPathAndQuery() {
    let here = "https://x.test/inbox?page=1"
    expectEq(nav(here, "https://x.test/account/delete?confirm=1"), .success(.ask), "delete + confirm")
    expectEq(nav(here, "https://x.test/logout"), .success(.ask), "logout")
    expectEq(nav(here, "https://x.test/unsubscribe?all"), .success(.ask), "unsubscribe")
    expectEq(nav(here, "https://x.test/inbox?page=1#section"), .success(.act), "fragment only")
    expectEq(nav(here, "https://x.test/search?q=x"), .success(.act), "plain query")
    expectEq(nav(here, "https://x.test/logout", said: "cierra sesion"), .success(.act), "said it")
    expectEq(nav(nil, "https://x.test/logout"), .success(.ask), "no current address: cautious")
    expectEq(nav(here, "https://x.test/search?q=delete"), .success(.ask), "a destructive word in the query asks")
}

// MARK: - M2 residual bypasses

@Test func anEncodedDestructiveWordInTheQueryOrPathAsks() {
    let here = "https://x.test/inbox"
    expectEq(nav(here, "https://x.test/inbox?action=%64elete"), .success(.ask), "encoded first letter")
    expectEq(nav(here, "https://x.test/inbox?action=del%65te"), .success(.ask), "encoded middle letter")
    expectEq(nav(here, "https://x.test/inbox?action=%2564elete"), .success(.ask), "double encoded")
    expectEq(nav(here, "https://x.test/acc/del%65te"), .success(.ask), "encoded path")
    expectEq(nav(here, "https://x.test/inbox?q=caf%C3%A9"), .success(.act), "benign encoding still acts")
}

@Test func aDestructiveFragmentAsksEvenWhenPathAndQueryAreUnchanged() {
    let here = "https://x.test/app"
    expectEq(nav(here, "https://x.test/app#/logout"), .success(.ask), "hash-router logout")
    expectEq(nav(here, "https://x.test/app#/account/delete"), .success(.ask), "hash-router delete")
    expectEq(nav(here, "https://x.test/app#/account/%64elete"), .success(.ask), "encoded fragment")
    expectEq(nav(here, "https://x.test/app#/logout", said: "log out"), .success(.act), "said it")
    expectEq(nav(here, "https://x.test/app#section"), .success(.act), "plain anchor")
}

@Test func aSameOriginRedirectParameterToAnotherHostAsks() {
    let here = "https://x.test/inbox"
    expectEq(nav(here, "https://x.test/out?next=https://evil.tld/?d=x"), .success(.ask), "absolute url")
    expectEq(nav(here, "https://x.test/out?next=%2F%2Fevil.tld"), .success(.ask), "scheme-relative")
    expectEq(nav(here, "https://x.test/out?next=https%253A%252F%252Fevil.tld"), .success(.ask), "double encoded")
    expectEq(nav(here, "https://x.test/out#https://evil.tld"), .success(.ask), "fragment")
    expectEq(nav(here, "https://x.test/out?next=/local/page"), .success(.act), "local path")
    expectEq(nav(here, "https://x.test/out?next=https://x.test/page"), .success(.act), "same host")
    expectEq(nav(here, "https://x.test/out?next=https://evil.tld", said: "go via evil.tld"), .success(.act), "user said the host")
}

@Test func moreDestructiveStemsInTheUrlAsk() {
    let here = "https://x.test/inbox"
    for stem in ["destroy", "purge", "cancel", "disable", "terminate", "close"] {
        expectEq(nav(here, "https://x.test/acct/\(stem)Account"), .success(.ask), stem)
    }
    expectEq(nav(here, "https://x.test/acct/cancelSub", said: "cancel it"), .success(.act), "said it")
}
