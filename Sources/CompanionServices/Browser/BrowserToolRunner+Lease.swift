import CompanionCore
import Foundation

/// Wave 18b. The three tools that move control (`open`, `take`, `release`)
/// and the check every other tool passes first. A denial is decided here, from
/// the shared lease, before any frame is built: the extension hears nothing.
extension BrowserToolRunner {
    /// The conversation's caller id. Anything else is a bridge session.
    static let chatCaller = "chat"

    var asksBeforeTaking: Bool { caller != Self.chatCaller }

    // MARK: - the check

    /// Nil means this caller controls the tab and the call may go on.
    func requireControl(_ tool: BrowserTool, _ tab: Int) async -> ParentToolOutcome? {
        var denial = leases.authorize(tab: tab, caller: caller, allowTake: false)
        if denial == .notControlled, await adoptSpawned(tab) { denial = nil }
        guard let denial else {
            leases.touch(tab: tab, caller: caller)
            return nil
        }
        return refuse(tool, denial, tab)
    }

    /// Same verdict without side effects, for the synchronous gate: a call the
    /// lease will refuse must not leave a ticket or a sheet behind.
    func controls(_ tab: Int) -> Bool {
        leases.authorize(tab: tab, caller: caller, allowTake: false) == nil
    }

    /// Controlled, or a child that `requireControl` will adopt for this caller
    /// per the last listing seen. Without a listing the answer is no: the gate
    /// stays closed and `execute` adopts, then says to repeat the call.
    func mayAct(_ tab: Int) -> Bool {
        controls(tab) || leases.foreseenSpawnOwner(of: tab) == caller
    }

    private func refuse(_ tool: BrowserTool, _ denial: BrowserLease.Denial, _ tab: Int) -> ParentToolOutcome {
        let code = denial == .busy ? BridgeCode.busy : BridgeCode.notControlled
        return fail(tool, code, BrowserCopy.leaseDenial(denial, tab: tab, language()))
    }

    /// Incredible's spawned-tab rule: a page the agent was driving opened this
    /// one moments after the agent acted, so it is the agent's. The tab list
    /// is the only place the opener and birth time are known.
    private func adoptSpawned(_ tab: Int) async -> Bool {
        let asOf = leases.sequence
        guard case .success(.tabs(_, let tabs)) = await channel.send(.tabs, timeout: Self.actTimeout) else {
            return false
        }
        leases.noteListing(tabs, asOf: asOf)
        // WHY same origin: a controlled page can open any site, and that new
        // tab carries the user's cookies for it. Cross-origin goes through
        // `browser_take` or `browser_open`, which have their own gates.
        guard leases.spawnOwner(of: tab, in: tabs) == caller else { return false }
        // The extension puts it in the group; only then is it controlled.
        guard case .success = await channel.send(.take(tab: tab), timeout: Self.actTimeout) else { return false }
        leases.acquire(tab: tab, caller: caller)
        return true
    }

    // MARK: - open

    func open(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let tool = BrowserTool.open
        guard let address = arguments["url"] as? String else {
            return fail(tool, BridgeCode.invalidArgs, "missing url")
        }
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(address)
        } catch {
            Log.browser("tool=\(tool.rawValue) code=\(error.code)")
            return .failed(error, target: address, tool: tool.rawValue)
        }
        // Approved for this exact address, or the extension hears nothing.
        guard tickets.redeem(Self.openTicket(url)) else {
            return fail(tool, "approval_required", "this action needs approval before it runs")
        }
        switch await channel.send(.open(url: url), timeout: Self.navigateTimeout) {
        case .failure(let error):
            return failed(tool, error)
        case .success(.opened(_, let opened)):
            leases.acquire(tab: opened.id, caller: caller)
            return ParentToolOutcome(
                ok: true,
                output: opened.loading
                    ? "opened tab \(opened.id) in the background; it is still loading, so wait a moment, then read it "
                        + "with browser_read"
                    : "opened tab \(opened.id) in the background; read it with browser_read",
                target: url.absoluteString, tool: tool.rawValue)
        case .success:
            return fail(tool, BridgeCode.badFrame, "unexpected reply")
        }
    }

    /// A new tab carries the user's cookies, so opening is navigating: it acts
    /// only for a site the user named. The bridge has no user words of its own.
    func openApproval(_ call: ToolCallRef, arguments: [String: Any], said: String) -> ApprovalRequest? {
        guard let raw = arguments["url"] as? String else { return nil }
        let url: URL
        do {
            url = try ParentToolPolicy.httpURL(raw)
        } catch {
            // `execute` refuses it with the policy's reason.
            return nil
        }
        guard case .success(let verdict) = BrowserPolicy.navigateVerdict(
            from: nil, currentURL: nil, to: raw, said: asksBeforeTaking ? "" : said)
        else { return nil }
        switch verdict {
        case .refuse:
            return nil
        case .act:
            tickets.issue(Self.openTicket(url))
            return nil
        case .ask:
            let request = ApprovalRequest(
                requestId: UUID().uuidString, toolName: call.name,
                summary: "open \(url.host ?? "another site") in a new tab", inputJSON: call.arguments)
            tickets.park(Self.openTicket(url), id: request.requestId)
            return request
        }
    }

    static func openTicket(_ url: URL) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: BrowserTool.open.rawValue, arguments: url.absoluteString, pid: 0, item: url.absoluteString)
    }

    // MARK: - take

    /// A sheet is asked only where it can change the answer: on the bridge,
    /// for a tab that is takeable and not already this caller's.
    func takeApproval(_ call: ToolCallRef, tab: Int) -> ApprovalRequest? {
        guard asksBeforeTaking, leases.owner(of: tab) != caller,
              leases.authorize(tab: tab, caller: caller, allowTake: true) == nil
        else { return nil }
        let request = ApprovalRequest(
            requestId: UUID().uuidString, toolName: call.name,
            summary: BrowserCopy.takeSummary(title: "#\(tab)", language()), inputJSON: call.arguments)
        tickets.park(Self.takeTicket(call.arguments, tab: tab), id: request.requestId)
        return request
    }

    /// The sheet names the tab by its title, which only the extension knows.
    package func bound(_ request: ApprovalRequest) async -> ApprovalRequest {
        guard request.toolName == BrowserTool.take.rawValue,
              let arguments = ToolArguments.parse(request.inputJSON), let tab = Self.tab(arguments),
              case .success(.tabs(_, let tabs)) = await channel.send(.tabs, timeout: Self.actTimeout),
              let title = tabs.first(where: { $0.id == tab })?.title, !title.isEmpty
        else { return request }
        var named = request
        named.summary = BrowserCopy.takeSummary(title: String(Self.oneLine(title).prefix(Self.titleLimit)), language())
        return named
    }

    func take(_ arguments: [String: Any], raw: String) async -> ParentToolOutcome {
        let tool = BrowserTool.take
        guard let tab = Self.tab(arguments) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab")
        }
        if let denial = leases.authorize(tab: tab, caller: caller, allowTake: true) {
            return refuse(tool, denial, tab)
        }
        if asksBeforeTaking, leases.owner(of: tab) != caller,
           !tickets.redeem(Self.takeTicket(raw, tab: tab)) {
            return fail(tool, "approval_required", "this action needs approval before it runs")
        }
        switch await channel.send(.take(tab: tab), timeout: Self.actTimeout) {
        case .failure(let error):
            return failed(tool, error)
        case .success:
            leases.acquire(tab: tab, caller: caller)
            forget(tab)
            return ParentToolOutcome(
                ok: true, output: "took control of tab \(tab); read it with browser_read", tool: tool.rawValue)
        }
    }

    // MARK: - release

    func release(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let tool = BrowserTool.release
        guard let tab = Self.tab(arguments) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab")
        }
        if let denial = leases.authorize(tab: tab, caller: caller, allowTake: false) {
            return refuse(tool, denial, tab)
        }
        // Whatever the extension answers, the caller gave the tab up: keeping
        // a lease over a tab that may already be gone helps nobody.
        leases.release(tab: tab)
        forget(tab)
        switch await channel.send(.release(tab: tab), timeout: Self.actTimeout) {
        case .failure(let error):
            return failed(tool, error)
        case .success:
            return ParentToolOutcome(ok: true, output: "gave tab \(tab) back", tool: tool.rawValue)
        }
    }

    static func takeTicket(_ arguments: String, tab: Int) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(name: BrowserTool.take.rawValue, arguments: arguments, pid: Int32(clamping: tab))
    }
}
