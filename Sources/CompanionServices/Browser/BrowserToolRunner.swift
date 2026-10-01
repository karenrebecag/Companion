import CompanionCore
import Foundation

/// What the runner needs from the extension's channel: one call, one answer.
/// A seam so the gates can be tested against a channel that records what it
/// was asked to send.
package protocol BrowserCommanding: Sendable {
    func send(_ command: BrowserCommand, timeout: Duration) async -> Result<BrowserInbound, ContractError>
}

extension BrowserChannel: BrowserCommanding {}

/// Wave 18-3. The browser's hand, as a `ParentToolExecuting` composed next to
/// the parent's own runner. It is offered only while an extension is
/// connected (a tool with nothing behind it is not advertised), and it owns
/// the two things the gates need: the last scrubbed page read from each tab,
/// which the synchronous `approval(for:said:)` judges against, and its own
/// tickets, so a yes cannot be spent by another runner's call.
package final class BrowserToolRunner: ParentToolExecuting, @unchecked Sendable {
    static let readBytes = 48_000
    static let readTimeout: Duration = .seconds(15)
    static let navigateTimeout: Duration = .seconds(30)
    static let actTimeout: Duration = .seconds(15)
    /// HACK: dropping the whole cache at the limit. A per-tab LRU when
    /// someone works across more than this many tabs in one session.
    static let cacheLimit = 64
    private static let lineLimit = 200

    let channel: any BrowserCommanding
    let language: @Sendable () -> AppLanguage
    let tickets = ApprovalTickets()
    let leases: BrowserLeases
    let caller: String
    static let titleLimit = 120
    private let presence: BrowserPresence
    private let lock = NSLock()
    private var pages: [Int: BrowserPage] = [:]
    private var seenEpoch: Int

    /// Alone, a runner has its own lease and is the conversation's.
    package convenience init(
        channel: any BrowserCommanding, presence: BrowserPresence,
        language: @escaping @Sendable () -> AppLanguage = { .en }
    ) {
        self.init(
            channel: channel, presence: presence, language: language,
            leases: BrowserLeases(epoch: presence.epoch), caller: Self.chatCaller)
    }

    /// The host builds one lease and hands it to both runners, each with its
    /// own caller id.
    init(
        channel: any BrowserCommanding, presence: BrowserPresence,
        language: @escaping @Sendable () -> AppLanguage = { .en },
        leases: BrowserLeases, caller: String
    ) {
        self.channel = channel
        self.presence = presence
        self.language = language
        self.leases = leases
        self.caller = caller
        self.seenEpoch = presence.epoch
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        presence.connected ? BrowserTool.allCases.map { $0.spec(language) } : []
    }

    package func handles(_ name: String) -> Bool {
        BrowserTool(rawValue: name) != nil && presence.connected
    }

    package func unavailability(for name: String) -> String? {
        BrowserTool(rawValue: name) != nil && !presence.connected ? BridgeCode.notConnected : nil
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let tool = BrowserTool(rawValue: name) else {
            return .failed(.notFound("unknown tool: \(name)"))
        }
        syncEpoch()
        guard let arguments = ToolArguments.parse(argumentsJSON) else {
            return fail(tool, BridgeCode.invalidArgs, "could not parse arguments; send one JSON object")
        }
        switch tool {
        case .tabs: return await tabs()
        case .read: return await read(arguments)
        case .click, .type, .navigate: return await write(tool, arguments, argumentsJSON)
        case .open: return await open(arguments)
        case .take: return await take(arguments, raw: argumentsJSON)
        case .release: return await release(arguments)
        }
    }

    package func granted(_ request: ApprovalRequest) {
        syncEpoch()
        tickets.grant(id: request.requestId)
    }

    package func withdraw(_ call: ToolCallRef) {
        tickets.revoke(name: call.name, arguments: call.arguments)
        // An open's ticket is keyed by the address it resolved to, not by
        // the raw arguments, so it is rebuilt the same way.
        guard call.name == BrowserTool.open.rawValue,
              let raw = ToolArguments.parse(call.arguments)?["url"] as? String else { return }
        do {
            let url = try ParentToolPolicy.httpURL(raw)
            let ticket = Self.openTicket(url)
            tickets.revoke(name: ticket.name, arguments: ticket.arguments)
        } catch {
            // Never resolved, so no ticket was ever issued for it.
        }
    }

    // MARK: - reads

    private func tabs() async -> ParentToolOutcome {
        let asOf = leases.sequence
        switch await channel.send(.tabs, timeout: Self.actTimeout) {
        case .failure(let error):
            return failed(.tabs, error)
        case .success(.tabs(_, let tabs)):
            leases.noteListing(tabs, asOf: asOf)
            let lines = tabs.map {
                "[\($0.id)] \(Self.oneLine($0.title)) — \(Self.oneLine($0.url))" + ($0.active ? " (active)" : "")
                    + ownership(of: $0.id)
            }
            let body = lines.isEmpty ? "no open tabs" : lines.joined(separator: "\n")
            return ParentToolOutcome(ok: true, output: withDataNote(body), tool: BrowserTool.tabs.rawValue)
        case .success:
            return fail(.tabs, BridgeCode.badFrame, "unexpected reply")
        }
    }

    private func read(_ arguments: [String: Any]) async -> ParentToolOutcome {
        guard let tab = Self.tab(arguments) else {
            return fail(.read, BridgeCode.invalidArgs, "missing or invalid tab")
        }
        if let denied = await requireControl(.read, tab) { return denied }
        var selector: String?
        if let raw = arguments["selector"], !(raw is NSNull) {
            guard let text = raw as? String else {
                return fail(.read, BridgeCode.invalidArgs, "selector must be a string")
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            selector = trimmed.isEmpty ? nil : trimmed
        }
        let epoch = presence.epoch
        switch await channel.send(.read(tab: tab, selector: selector), timeout: Self.readTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { lost(tab) }
            return failed(.read, error)
        case .success(.page(_, let page)) where page.tab == tab:
            let clean = BrowserPolicy.scrub(page)
            remember(clean, epoch: epoch)
            let text = BrowserPolicy.render(clean, maxBytes: Self.readBytes, language: language())
            return ParentToolOutcome(
                ok: true, output: withDataNote(text), target: clean.origin, tool: BrowserTool.read.rawValue)
        case .success:
            return fail(.read, BridgeCode.badFrame, "unexpected reply")
        }
    }

    /// Only says who holds a tab, never why: the listing is for locating.
    private func ownership(of tab: Int) -> String {
        switch leases.owner(of: tab) {
        case nil: return ""
        case caller?: return " (yours)"
        default: return " (another agent)"
        }
    }

    // MARK: - shared

    func cachedPage(_ tab: Int) -> BrowserPage? {
        syncEpoch()
        return lock.withLock { pages[tab] }
    }

    func forget(_ tab: Int) { lock.withLock { pages[tab] = nil } }

    /// The extension says the tab is gone: nobody owns it any more.
    func lost(_ tab: Int) {
        leases.release(tab: tab)
        forget(tab)
    }

    /// Pages and approvals belong to the connection that produced them: ids
    /// and generations mean nothing to a reconnected extension, and a yes
    /// given for the old session must not be spendable in the new one.
    func syncEpoch() {
        let current = presence.epoch
        leases.sync(epoch: current)
        // WHY the reset is inside the lock: outside it, a redeem racing the
        // transition could spend an old-session yes after the pages were
        // already cleared. Tickets take their own lock and never call back.
        lock.withLock {
            guard current != seenEpoch else { return }
            seenEpoch = current
            pages.removeAll()
            tickets.reset()
        }
    }

    /// A read that finished after the connection changed describes a page of
    /// the old session and is not kept.
    private func remember(_ page: BrowserPage, epoch: Int) {
        syncEpoch()
        lock.withLock {
            guard epoch == seenEpoch else { return }
            if pages[page.tab] == nil, pages.count >= Self.cacheLimit { pages.removeAll() }
            pages[page.tab] = page
        }
    }

    static func tab(_ arguments: [String: Any]) -> Int? {
        ParentToolRunner.intArgument(arguments["tab"]).flatMap { $0 >= 0 ? $0 : nil }
    }

    func withDataNote(_ body: String) -> String {
        body + "\n" + BrowserCopy.toolDataSuffix(language())
    }

    /// Page-controlled text on one line: a newline in a title must not start
    /// a second entry.
    static func oneLine(_ text: String) -> String {
        String(text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .prefix(lineLimit))
    }

    /// Logs carry the tool and the code, never what the page or the model said.
    func fail(_ tool: BrowserTool, _ code: String, _ message: String) -> ParentToolOutcome {
        Log.browser("tool=\(tool.rawValue) code=\(code)")
        return .failed(ContractError(code: code, message: message), tool: tool.rawValue)
    }

    /// The extension's own wording never reaches the model: the code picks the copy.
    func failed(_ tool: BrowserTool, _ error: ContractError) -> ParentToolOutcome {
        .failed(
            ContractError(code: error.code, message: BrowserCopy.failure(code: error.code, language())),
            tool: tool.rawValue)
    }
}
