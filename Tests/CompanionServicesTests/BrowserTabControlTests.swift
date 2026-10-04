import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 18b criteria 1-6 at the runners: a tab is used only by the caller that
// controls it, and every denial leaves the channel's record without the frame.

final class LeaseClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 2_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private struct LeaseRig {
    let chat: BrowserToolRunner
    let bridge: BrowserToolRunner
    let channel: FakeBrowserChannel
    let presence: BrowserPresence
    let clock: LeaseClock
    let leases: BrowserLeases

    var reads: [BrowserCommand] { channel.sent.map(\.command).filter { if case .read = $0 { return true }; return false } }
    var takes: [BrowserCommand] { channel.sent.map(\.command).filter { if case .take = $0 { return true }; return false } }
    var releases: [BrowserCommand] { channel.sent.map(\.command).filter { if case .release = $0 { return true }; return false } }
}

private func leaseRig(tabs: [BrowserTab]? = nil, pages: [BrowserPage] = [crmPage()]) -> LeaseRig {
    let presence = BrowserPresence()
    presence.set(.comet)
    let clock = LeaseClock()
    let channel = FakeBrowserChannel(
        pages: pages, tabs: tabs ?? [BrowserTab(id: 12, title: "Gmail", url: crm + "/a", active: false)])
    let leases = BrowserLeases(epoch: presence.epoch, now: { clock.now })
    return LeaseRig(
        chat: BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "chat"),
        bridge: BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "bridge"),
        channel: channel, presence: presence, clock: clock, leases: leases)
}

private let tab12 = #"{"tab":12}"#

private func call(_ name: String, _ arguments: String) -> ToolCallRef { ToolCallRef(id: "c", name: name, arguments: arguments) }

/// The path the guard takes: gate, then the sheet's yes if there is one.
private func run(
    _ runner: BrowserToolRunner, _ name: String, _ arguments: String, approve: Bool = true, said: String = ""
) async -> (out: ParentToolOutcome, asked: ApprovalRequest?) {
    let asked = runner.approval(for: call(name, arguments), said: said)
    if let asked, approve { runner.granted(asked) }
    return (await runner.execute(name: name, argumentsJSON: arguments), asked)
}

// MARK: - criterion 1

@Test func readingATabNobodyTookIsNotControlledAndSendsNoReadFrame() async {
    let rig = leaseRig()
    let out = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(!out.ok && out.output.hasPrefix(BridgeCode.notControlled), "criterio 1: not_controlled")
    expect(out.output.contains("browser_take") && out.output.contains("browser_open"), "con la guia de reclamo")
    expect(rig.reads.isEmpty, "criterio 1: la extension no recibio read")
}

@Test func clickTypeAndNavigateNeedControlToo() async {
    let rig = leaseRig()
    for (name, arguments) in [
        ("browser_click", #"{"tab":12,"element":1}"#),
        ("browser_double_click", #"{"tab":12,"element":1}"#),
        ("browser_right_click", #"{"tab":12,"element":1}"#),
        ("browser_type", #"{"tab":12,"element":5,"text":"x"}"#),
        ("browser_select", #"{"tab":12,"element":5,"option":"x"}"#),
        ("browser_press", #"{"tab":12,"key":"Escape"}"#),
        ("browser_navigate", #"{"tab":12,"url":"https://crm.example/b"}"#),
    ] {
        let (out, asked) = await run(rig.chat, name, arguments)
        expect(asked == nil, "\(name): no hoja para una pestana ajena")
        expect(!out.ok && out.output.hasPrefix(BridgeCode.notControlled), "\(name): not_controlled")
    }
    expect(rig.channel.writes.isEmpty, "cero escrituras")
    let onlyTabs = rig.channel.sent.allSatisfy { if case .tabs = $0.command { return true }; return false }
    expect(onlyTabs, "y ningun frame salvo el listado inocuo con que se busca una pestana hija")
}

// MARK: - criterion 2

@Test func openMakesANewTabOwnedAndReadableAtOnce() async {
    let page = BrowserPage(
        tab: 41, origin: "https://sf.example", url: "https://sf.example/", title: "SF", text: "picklist",
        generation: 1, elements: [], truncated: false)
    let rig = leaseRig(pages: [page])
    let (out, asked) = await run(rig.chat, "browser_open", #"{"url":"https://sf.example/"}"#, said: "abre sf.example")
    expect(asked == nil, "open de un sitio nombrado no pide hoja")
    expect(out.ok && out.output.contains("41"), "devuelve el id de la pestana nueva")
    expectEq(rig.leases.owner(of: 41), "chat", "nace del que la abrio")
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":41}"#)
    expect(read.ok, "legible al instante")
    let other = await rig.bridge.execute(name: "browser_read", argumentsJSON: #"{"tab":41}"#)
    expect(!other.ok, "y no del otro llamador")
}

@Test func openRefusesAnythingButHttpAndSendsNothing() async {
    let rig = leaseRig()
    for url in ["file:///etc/passwd", "javascript:alert(1)", "about:blank", "", "not a url"] {
        let (out, _) = await run(rig.chat, "browser_open", #"{"url":"\#(url)"}"#)
        expect(!out.ok, "\(url): rechazada")
    }
    let missing = await rig.chat.execute(name: "browser_open", argumentsJSON: "{}")
    expect(!missing.ok && missing.output.contains(BridgeCode.invalidArgs), "sin url: invalid_args")
    expect(rig.channel.sent.isEmpty, "cero frames")
}

// MARK: - criterion 3

@Test func takingInTheChatNeedsNoSheet() async {
    let rig = leaseRig()
    let (out, asked) = await run(rig.chat, "browser_take", tab12)
    expect(asked == nil, "criterio 3: sin hoja en el chat")
    expect(out.ok, "toma")
    expectEq(rig.takes.count, 1, "un frame take")
    expectEq(rig.leases.owner(of: 12), "chat", "suya")
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.ok, "ya la puede leer")
}

@Test func takingOverTheBridgeAsksASheetNamingTheTab() async {
    let rig = leaseRig()
    guard let asked = rig.bridge.approval(for: call("browser_take", tab12), said: "") else {
        Issue.record("criterio 3: por el puente pide hoja"); return
    }
    let bound = await rig.bridge.bound(asked)
    expect(bound.summary.contains("\u{AB}Gmail\u{BB}"), "la hoja nombra la pestana: \(bound.summary)")
    expectEq(bound.toolName, "browser_take", "es la del take")
    rig.bridge.granted(bound)
    let out = await rig.bridge.execute(name: "browser_take", argumentsJSON: tab12)
    expect(out.ok, "con un si, toma")
    expectEq(rig.leases.owner(of: 12), "bridge", "del puente")
    expectEq(rig.takes.count, 1, "un frame")
}

@Test func aDeniedBridgeTakeSendsNothingAndTheTabStaysPut() async {
    let rig = leaseRig()
    let (out, asked) = await run(rig.bridge, "browser_take", tab12, approve: false)
    expect(asked != nil, "hubo hoja")
    expect(!out.ok && out.output.contains("approval_required"), "sin ticket no corre")
    expect(rig.takes.isEmpty, "criterio 3: la pestana no se movio, cero frames take")
    expectEq(rig.leases.owner(of: 12), nil, "y no es del puente")
}

@Test func aBridgeSheetIsNotSpendableByTheChatRunner() async {
    let rig = leaseRig()
    guard let asked = rig.bridge.approval(for: call("browser_take", tab12), said: "") else { return }
    rig.chat.granted(asked)
    let out = await rig.bridge.execute(name: "browser_take", argumentsJSON: tab12)
    expect(!out.ok && rig.takes.isEmpty, "el si dado al otro runner no se gasta aqui")
}

// MARK: - criterion 4

@Test func aTabTheChatTookIsBusyForTheBridgeUntilItIdlesTwoMinutes() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    rig.clock.advance(BrowserLease.takeoverAfter - 1)
    let read = await rig.bridge.execute(name: "browser_read", argumentsJSON: tab12)
    expect(!read.ok && read.output.hasPrefix(BridgeCode.busy), "criterio 4: busy")
    let (take, asked) = await run(rig.bridge, "browser_take", tab12)
    expect(asked == nil, "no se molesta al usuario por una pestana que no se puede tomar")
    expect(!take.ok && take.output.hasPrefix(BridgeCode.busy), "tomarla tampoco")
    expectEq(rig.takes.count, 1, "solo el take del chat")
    expect(rig.reads.isEmpty, "cero reads")

    rig.clock.advance(1)
    let (taken, sheet) = await run(rig.bridge, "browser_take", tab12)
    expect(sheet != nil, "a los 120 s la puede tomar, con hoja")
    expect(taken.ok, "y la toma")
    let chatRead = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(!chatRead.ok && chatRead.output.hasPrefix(BridgeCode.busy), "ahora el chat es quien espera")
}

@Test func actingKeepsATabWarm() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    rig.clock.advance(100)
    _ = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    rig.clock.advance(100)
    let read = await rig.bridge.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.busy), "el chat actuo hace 100 s: sigue ocupada")
}

// MARK: - criterion 5

@Test func releaseSendsTheFrameAndClearsOwnership() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    let (out, asked) = await run(rig.chat, "browser_release", tab12)
    expect(asked == nil && out.ok, "sin hoja")
    expectEq(rig.releases.count, 1, "un frame release")
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "ya no la controla")
}

@Test func releasingATabYouDoNotControlSendsNothing() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    let mine = await rig.bridge.execute(name: "browser_release", argumentsJSON: tab12)
    expect(!mine.ok && mine.output.hasPrefix(BridgeCode.busy), "el puente no suelta la del chat")
    let stranger = await rig.chat.execute(name: "browser_release", argumentsJSON: #"{"tab":99}"#)
    expect(!stranger.ok && stranger.output.hasPrefix(BridgeCode.notControlled), "ni una que nadie tomo")
    expect(rig.releases.isEmpty, "cero frames release")
}

@Test func tenIdleMinutesReleaseTheTabAndTheSweepTellsTheExtension() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    rig.clock.advance(BrowserLease.idleRelease)
    await rig.leases.sweep(channel: rig.channel, epoch: rig.presence.epoch)
    expectEq(rig.releases.count, 1, "criterio 5: el barrido le devuelve la pestana")
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "ya no es suya")
}

@Test func anIdleTabIsNotUsableEvenBeforeTheSweepRuns() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    rig.clock.advance(BrowserLease.idleRelease + 1)
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "10 min sin uso: suelta")
    expect(rig.reads.isEmpty, "cero reads")
}

@Test func aDisconnectClearsEveryLease() async {
    let rig = leaseRig()
    _ = await run(rig.chat, "browser_take", tab12)
    rig.presence.set(nil)
    rig.presence.set(.comet)
    let read = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(read.output.hasPrefix(BridgeCode.notControlled), "criterio 5: al reconectar hay que volver a tomar")
    expect(rig.reads.isEmpty, "cero reads")
    let other = await rig.bridge.execute(name: "browser_read", argumentsJSON: tab12)
    expect(other.output.hasPrefix(BridgeCode.notControlled), "para los dos")
}

// MARK: - criterion 6

private func spawnedTabs(url: String, born: TimeInterval, clock: LeaseClock) -> [BrowserTab] {
    [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false, controlled: true),
     BrowserTab(id: 20, title: "", url: url, active: false, controlled: false, opener: 12,
                createdAt: clock.now.addingTimeInterval(born))]
}

private func page20() -> BrowserPage {
    BrowserPage(tab: 20, origin: crm, url: crm + "/new", title: "New", text: "hija", generation: 1,
                elements: [], truncated: false)
}

@Test func aTabOpenedByTheAgentsClickBecomesItsOwn() async {
    let rig = leaseRig(pages: [crmPage(), page20()])
    _ = await run(rig.chat, "browser_take", tab12)
    let acted = await rig.chat.execute(name: "browser_read", argumentsJSON: tab12)
    expect(acted.ok, "el agente actua")
    rig.channel.setTabs(spawnedTabs(url: crm + "/new", born: 4, clock: rig.clock))
    rig.clock.advance(5)
    let out = await rig.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(out.ok, "criterio 6: la hija nace controlada")
    expectEq(rig.leases.owner(of: 20), "chat", "del mismo dueno")
    expectEq(rig.takes.count, 2, "y se manda al grupo con un take")
    let bridge = await rig.bridge.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(!bridge.ok, "no del puente")
}

@Test func aNewTabTheUserOpenedIsNeverAdopted() async {
    let rig = leaseRig(pages: [crmPage(), page20()])
    _ = await run(rig.chat, "browser_take", tab12)
    rig.channel.setTabs(spawnedTabs(url: "chrome://newtab/", born: 1, clock: rig.clock))
    rig.clock.advance(2)
    let out = await rig.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(!out.ok && out.output.hasPrefix(BridgeCode.notControlled), "criterio 6: una newtab no")
    expect(rig.reads.isEmpty, "cero reads")
    expectEq(rig.takes.count, 1, "ningun take extra")
}

@Test func aTabBornLongAfterTheLastActIsNotAdopted() async {
    let rig = leaseRig(pages: [crmPage(), page20()])
    _ = await run(rig.chat, "browser_take", tab12)
    rig.channel.setTabs(spawnedTabs(url: crm + "/new", born: 30, clock: rig.clock))
    rig.clock.advance(31)
    let out = await rig.chat.execute(name: "browser_read", argumentsJSON: #"{"tab":20}"#)
    expect(out.output.hasPrefix(BridgeCode.notControlled), "fuera de los 10 s")
}

// MARK: - listing

@Test func theTabListShowsWhichTabsAreYoursAndWhichAreAnotherAgents() async {
    let rig = leaseRig(tabs: [
        BrowserTab(id: 12, title: "Mine", url: crm, active: false),
        BrowserTab(id: 13, title: "Theirs", url: crm, active: false),
        BrowserTab(id: 14, title: "Free", url: crm, active: false),
    ])
    _ = await run(rig.chat, "browser_take", tab12)
    _ = await run(rig.bridge, "browser_take", #"{"tab":13}"#)
    let out = await rig.chat.execute(name: "browser_tabs", argumentsJSON: "{}")
    let lines = out.output.split(separator: "\n").map(String.init)
    expect(lines.first { $0.contains("[12]") }?.contains("(yours)") == true, "la suya")
    expect(lines.first { $0.contains("[13]") }?.contains("(another agent)") == true, "la del otro")
    expect(lines.first { $0.contains("[14]") }?.contains("yours") == false, "la libre, sin marca")
}

// MARK: - one lease across both runners of the host

private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "", tool: name)
    }
}

@Test func theHostSharesOneLeaseBetweenTheConversationAndTheBridge() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("l18b-\(UUID().uuidString.prefix(8))", isDirectory: true)
    let channel = FakeBrowserChannel(
        pages: [crmPage()], tabs: [BrowserTab(id: 12, title: "CRM", url: crm + "/a", active: false)])
    let host = BrowserHost(
        directory: root.appendingPathComponent("b", isDirectory: true),
        installer: NativeHostInstaller(home: root, executable: root),
        language: { .en }, commanding: channel)
    host.presence.set(.chrome)
    let conversation = host.conversationTools(parent: NoTools(), apps: NoTools())
    let bridge = host.bridgeTools(parent: NoTools())
    _ = await conversation.execute(name: "browser_take", argumentsJSON: tab12)
    let read = await bridge.execute(name: "browser_read", argumentsJSON: tab12)
    expect(!read.ok && read.output.hasPrefix(BridgeCode.busy), "una pestana es una: el puente la ve ocupada")
    let own = await conversation.execute(name: "browser_read", argumentsJSON: tab12)
    expect(own.ok, "el chat la sigue leyendo")
}
