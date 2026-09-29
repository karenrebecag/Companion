import CompanionCore
import Foundation

/// The gates of the three browser writes. A write runs only against a ticket
/// the gate issued (or parked and the sheet granted) for that exact call, and
/// the ticket is bound to the page it was judged against, so a denied call
/// finds none and the extension never hears about it.
extension BrowserToolRunner {
    private static let sheetLabel = 120

    // MARK: - approval

    public func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let tool = BrowserTool(rawValue: call.name), tool.isWrite,
              let arguments = ToolArguments.parse(call.arguments), let tab = Self.tab(arguments)
        else { return nil }
        if tool == .navigate { return navigateApproval(call, tab: tab, arguments: arguments, said: said) }
        return elementApproval(call, tool: tool, tab: tab, arguments: arguments, said: said)
    }

    private func elementApproval(
        _ call: ToolCallRef, tool: BrowserTool, tab: Int, arguments: [String: Any], said: String
    ) -> ApprovalRequest? {
        guard let id = ParentToolRunner.intArgument(arguments["element"]),
              let page = cachedPage(tab), let element = page.elements.first(where: { $0.id == id })
        else { return nil }
        let verdict: HandsVerdict
        if tool == .click {
            verdict = BrowserPolicy.clickVerdict(element, said: said, pageOrigin: page.origin)
        } else {
            guard let text = arguments["text"] as? String else { return nil }
            verdict = BrowserPolicy.typeVerdict(element, text: text, said: said, pageOrigin: page.origin)
        }
        let ticket = Self.ticket(call.name, call.arguments, tab: tab, element: element, page: page)
        switch verdict {
        case .refuse:
            // No ticket: `execute` refuses with the reason.
            return nil
        case .act:
            tickets.issue(ticket)
            return nil
        case .ask:
            let request = tool == .click
                ? HandsGate.clickRequest(call, label: Self.shown(element.label), app: page.origin)
                : HandsGate.request(call, app: page.origin, commandApp: false)
            tickets.park(ticket, id: request.requestId)
            return request
        }
    }

    private func navigateApproval(
        _ call: ToolCallRef, tab: Int, arguments: [String: Any], said: String
    ) -> ApprovalRequest? {
        guard let raw = arguments["url"] as? String else { return nil }
        let page = cachedPage(tab)
        let origin = page?.origin
        let ticket = Self.navigateTicket(call.arguments, tab: tab, origin: origin)
        // A refusal (a scheme that is not http/https) is also nil: `execute`
        // refuses it with the policy's reason.
        guard case .success(let verdict) = BrowserPolicy.navigateVerdict(
            from: origin, currentURL: page?.url, to: raw, said: said)
        else { return nil }
        switch verdict {
        case .refuse:
            return nil
        case .act:
            tickets.issue(ticket)
            return nil
        case .ask:
            let host = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "another site"
            let request = ApprovalRequest(
                requestId: UUID().uuidString, toolName: call.name,
                summary: "open \(host) in the browser", inputJSON: call.arguments)
            tickets.park(ticket, id: request.requestId)
            return request
        }
    }

    // MARK: - execution

    func write(_ tool: BrowserTool, _ arguments: [String: Any], _ raw: String) async -> ParentToolOutcome {
        guard let tab = Self.tab(arguments) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab")
        }
        if tool == .navigate { return await navigate(tab: tab, arguments: arguments, raw: raw) }
        return await act(tool, tab: tab, arguments: arguments, raw: raw)
    }

    private func act(
        _ tool: BrowserTool, tab: Int, arguments: [String: Any], raw: String
    ) async -> ParentToolOutcome {
        guard let id = ParentToolRunner.intArgument(arguments["element"]) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid element")
        }
        var text = ""
        if tool == .type {
            guard let typed = arguments["text"] as? String else {
                return fail(tool, BridgeCode.invalidArgs, "missing text")
            }
            text = typed
        }
        guard let page = cachedPage(tab), let element = page.elements.first(where: { $0.id == id }) else {
            return fail(tool, BridgeCode.staleId, BrowserCopy.failure(code: BridgeCode.staleId, language()))
        }
        if tool == .type, BrowserPolicy.isSensitive(element) {
            return fail(tool, BridgeCode.secureField, BrowserCopy.failure(code: BridgeCode.secureField, language()))
        }
        guard tickets.redeem(Self.ticket(tool.rawValue, raw, tab: tab, element: element, page: page)) else {
            return fail(tool, "approval_required", "this action needs approval before it runs")
        }
        guard await tabIsStillAt(tab, origin: page.origin) else { return leftItsOrigin(tool, tab) }
        let command: BrowserCommand = tool == .click
            ? .click(tab: tab, generation: page.generation, element: id)
            : .type(tab: tab, generation: page.generation, element: id, text: text)
        switch await channel.send(command, timeout: Self.actTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { forget(tab) }
            return failed(tool, error)
        case .success:
            let verb = tool == .click ? "clicked" : "typed into"
            return ParentToolOutcome(
                ok: true, output: "\(verb) [\(id)]; read the tab again to see the result",
                target: page.origin, tool: tool.rawValue)
        }
    }

    private func navigate(tab: Int, arguments: [String: Any], raw: String) async -> ParentToolOutcome {
        let tool = BrowserTool.navigate
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
        let origin = cachedPage(tab)?.origin
        guard tickets.redeem(Self.navigateTicket(raw, tab: tab, origin: origin)) else {
            return fail(tool, "approval_required", "this action needs approval before it runs")
        }
        // Security finding M4: the verdict was reached against the origin the
        // tab had when it was last read. The tab's live address decides.
        if let origin, !(await tabIsStillAt(tab, origin: origin)) { return leftItsOrigin(tool, tab) }
        switch await channel.send(.navigate(tab: tab, url: url), timeout: Self.navigateTimeout) {
        case .failure(let error):
            return failed(tool, error)
        case .success:
            forget(tab)
            return ParentToolOutcome(
                ok: true, output: "navigating tab \(tab); read it again once it has loaded",
                target: url.absoluteString, tool: tool.rawValue)
        }
    }

    /// Fails closed: a tab that cannot be found, or an origin that cannot be
    /// compared, is not a tab that stayed where it was read.
    private func tabIsStillAt(_ tab: Int, origin: String) async -> Bool {
        guard !origin.isEmpty,
              case .success(.tabs(_, let tabs)) = await channel.send(.tabs, timeout: Self.actTimeout),
              let current = tabs.first(where: { $0.id == tab }), !current.url.isEmpty
        else { return false }
        return BrowserPolicy.sameOrigin(current.url, origin)
    }

    private func leftItsOrigin(_ tool: BrowserTool, _ tab: Int) -> ParentToolOutcome {
        forget(tab)
        return fail(tool, BridgeCode.staleId, BrowserCopy.failure(code: BridgeCode.staleId, language()))
    }

    // MARK: - tickets

    /// Bound to the tab, the scan generation, the element and its label: the
    /// bare arguments would match whatever a later read put at that number.
    static func ticket(
        _ name: String, _ arguments: String, tab: Int, element: BrowserElement, page: BrowserPage
    ) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: name, arguments: arguments, pid: Int32(clamping: tab), item: element.label,
            node: element.id, generation: page.generation)
    }

    /// Bound to the tab and the origin the verdict was reached from.
    static func navigateTicket(_ arguments: String, tab: Int, origin: String?) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: BrowserTool.navigate.rawValue, arguments: arguments, pid: Int32(clamping: tab),
            item: origin ?? "")
    }

    private static func shown(_ label: String) -> String {
        label.isEmpty ? "(unnamed control)" : String(oneLine(label).prefix(sheetLabel))
    }
}
