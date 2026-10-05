import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Shared doubles and the rig for the browser tool tests.

final class FakeBrowserChannel: BrowserCommanding, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(command: BrowserCommand, timeout: Duration)] = []
    private var pages: [Int: BrowserPage] = [:]
    private var tabList: [BrowserTab] = []
    private var failure: ContractError?
    private var nextOpened = 40
    private var staleReads: Set<Int> = []
    private var navigateNote: String?
    private var openedLoading = false

    init(pages: [BrowserPage] = [], tabs: [BrowserTab] = [], failure: ContractError? = nil) {
        self.pages = Dictionary(uniqueKeysWithValues: pages.map { ($0.tab, $0) })
        self.tabList = tabs
        self.failure = failure
    }

    var sent: [(command: BrowserCommand, timeout: Duration)] { lock.withLock { log } }
    var writes: [BrowserCommand] {
        sent.map(\.command).filter {
            if case .click = $0 { return true }
            if case .doubleClick = $0 { return true }
            if case .rightClick = $0 { return true }
            if case .hover = $0 { return true }
            if case .dragTo = $0 { return true }
            if case .dragBy = $0 { return true }
            if case .clickAt = $0 { return true }
            if case .scroll = $0 { return true }
            if case .scrollTo = $0 { return true }
            if case .type = $0 { return true }
            if case .select = $0 { return true }
            if case .press = $0 { return true }
            if case .navigate = $0 { return true }
            return false
        }
    }

    private var writeFailure: ContractError?
    func failWrites(with error: ContractError) { lock.withLock { writeFailure = error } }

    private var writeNote = "ok"
    func answerWrites(with note: String) { lock.withLock { writeNote = note } }

    private var releaseFailure: ContractError?
    func failReleases(with error: ContractError) { lock.withLock { releaseFailure = error } }

    /// Holds the reply to every matching command until the gate opens. The
    /// reply is worked out when the command arrives, so it is the state of that
    /// moment: what a slow extension would have answered.
    private var gates: [(match: @Sendable (BrowserCommand) -> Bool, gate: ReplyGate)] = []
    func hold(_ match: @escaping @Sendable (BrowserCommand) -> Bool) -> ReplyGate {
        let gate = ReplyGate()
        lock.withLock { gates.append((match, gate)) }
        return gate
    }

    /// What the extension says once a navigation or a new tab ran out of its load budget.
    func stillLoading() { lock.withLock { navigateNote = "still loading"; openedLoading = true } }

    /// The extension answers `stale_id` to a read of this tab, as for a tab that is gone.
    func goneOnRead(_ tab: Int) { lock.withLock { _ = staleReads.insert(tab) } }
    func setTabs(_ tabs: [BrowserTab]) { lock.withLock { tabList = tabs } }
    func setPage(_ page: BrowserPage) { lock.withLock { pages[page.tab] = page } }

    func send(_ command: BrowserCommand, timeout: Duration) async -> Result<BrowserInbound, ContractError> {
        let (reply, gate) = answer(command, timeout: timeout)
        if let gate { await gate.pass() }
        return reply
    }

    private func answer(
        _ command: BrowserCommand, timeout: Duration
    ) -> (Result<BrowserInbound, ContractError>, ReplyGate?) {
        lock.withLock {
            (reply(command, timeout: timeout), gates.first { $0.match(command) }?.gate)
        }
    }

    private func reply(_ command: BrowserCommand, timeout: Duration) -> Result<BrowserInbound, ContractError> {
        log.append((command, timeout))
        if let failure { return .failure(failure) }
        if case .navigate = command, let navigateNote { return .success(.done(id: 1, message: navigateNote)) }
        switch command {
        case .tabs: return .success(.tabs(id: 1, tabList))
        case .read(let tab, _):
            if staleReads.contains(tab) { return .failure(ContractError(code: BridgeCode.staleId, message: "no such tab")) }
            guard let page = pages[tab] else { return .failure(ContractError(code: BridgeCode.invalidArgs, message: "no tab")) }
            return .success(.page(id: 1, page))
        case .open(let url):
            nextOpened += 1
            return .success(.opened(id: 1, BrowserTab(
                id: nextOpened, title: "", url: url.absoluteString, active: false, loading: openedLoading)))
        case .release:
            if let releaseFailure { return .failure(releaseFailure) }
            return .success(.done(id: 1, message: "ok"))
        case .take:
            return .success(.done(id: 1, message: "ok"))
        case .click, .doubleClick, .rightClick, .hover, .scroll, .scrollTo, .dragTo, .dragBy, .clickAt, .type, .select, .press,
             .navigate:
            if let writeFailure { return .failure(writeFailure) }
            return .success(.done(id: 1, message: writeNote))
        }
    }
}

let crm = "https://crm.example"

func webElement(
    _ id: Int, _ role: String = "button", _ label: String, context: String = "",
    inputType: String? = nil, autocomplete: String? = nil, value: String? = nil,
    frameOrigin: String? = nil, href: String? = nil
) -> BrowserElement {
    BrowserElement(
        id: id, frame: 0, role: role, label: label, context: context, inputType: inputType,
        autocomplete: autocomplete, value: value, frameOrigin: frameOrigin, href: href)
}

func crmPage(generation: Int = 3, text: String = "Hola") -> BrowserPage {
    BrowserPage(
        tab: 12, origin: crm, url: crm + "/a", title: "CRM", text: text, generation: generation,
        elements: [
            webElement(1, "button", "Guardar"),
            webElement(2, "button", "Eliminar"),
            webElement(3, "link", "Docs", href: "https://other.example/x"),
            webElement(4, "input", "Clave", inputType: "password", value: "hunter2"),
            webElement(5, "input", "Nombre", inputType: "text"),
            webElement(6, "button", "Guardar", frameOrigin: "https://ads.example"),
            webElement(7, "link", "Ayuda", href: crm + "/help"),
        ], truncated: false)
}

struct BrowserToolRig {
    let runner: BrowserToolRunner
    let channel: FakeBrowserChannel
    let presence: BrowserPresence
}

/// Wave 18b: the tools under test read tab 12, which since then must be
/// controlled; `owned: false` is the tab nobody took.
func makeToolRig(
    connected: Bool = true, page: BrowserPage = crmPage(), tabs: [BrowserTab]? = nil, owned: Bool = true
) -> BrowserToolRig {
    let presence = BrowserPresence()
    if connected { presence.set(.comet) }
    let channel = FakeBrowserChannel(
        pages: [page], tabs: tabs ?? [BrowserTab(id: 12, title: "CRM", url: page.url, active: false)])
    let leases = BrowserLeases(epoch: presence.epoch)
    if owned { leases.acquire(tab: 12, caller: "chat") }
    let runner = BrowserToolRunner(channel: channel, presence: presence, leases: leases, caller: "chat")
    return BrowserToolRig(runner: runner, channel: channel, presence: presence)
}

extension BrowserToolRig {
    func call(_ name: String, _ arguments: String) -> ToolCallRef { ToolCallRef(id: "c", name: name, arguments: arguments) }

    func read() async {
        _ = await runner.execute(name: "browser_read", argumentsJSON: #"{"tab":12}"#)
    }

    /// The path every runtime takes: ask the gate, answer the sheet, run.
    func run(_ name: String, _ arguments: String, said: String = "", approve: Bool? = nil) async -> ParentToolOutcome {
        if let request = runner.approval(for: call(name, arguments), said: said), approve == true {
            runner.granted(request)
        }
        return await runner.execute(name: name, argumentsJSON: arguments)
    }
}

/// One held reply: `pass()` parks until `open()`, and `waitUntilReached()`
/// lets a test act at the moment the command is in flight.
final class ReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var reached = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock { () -> Bool in
                reached += 1
                if !opened { waiting.append(continuation) }
                return opened
            }
            if resume { continuation.resume() }
        }
    }

    func open() {
        let parked = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            opened = true
            defer { waiting = [] }
            return waiting
        }
        for continuation in parked { continuation.resume() }
    }

    /// Bounded: a command that never arrives fails the test instead of hanging it.
    func waitUntilReached() async -> Bool {
        for _ in 0..<400 {
            if lock.withLock({ reached > 0 }) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}
