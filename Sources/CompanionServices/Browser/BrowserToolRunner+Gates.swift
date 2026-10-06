import CompanionCore
import Foundation

/// The gates of the browser writes on a page. A write runs only against a ticket
/// the gate issued (or parked and the sheet granted) for that exact call, and
/// the ticket is bound to the page it was judged against, so a denied call
/// finds none and the extension never hears about it.
extension BrowserToolRunner {
    private static let sheetLabel = 120

    // MARK: - approval

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let tool = BrowserTool(rawValue: call.name), tool.isWrite, !tool.skipsApproval,
              let arguments = ToolArguments.parse(call.arguments)
        else { return nil }
        syncEpoch()
        // Open names no tab: it is judged by the address alone.
        if tool == .open { return openApproval(call, arguments: arguments, said: said) }
        guard let tab = Self.tab(arguments) else { return nil }
        if tool == .take { return takeApproval(call, tab: tab) }
        // Release never asks; the rest only for a tab this caller controls,
        // or the refusal in `execute` would find a ticket waiting.
        guard tool != .release, mayAct(tab) else { return nil }
        if tool == .navigate { return navigateApproval(call, tab: tab, arguments: arguments, said: said) }
        if tool == .press { return pressApproval(call, tab: tab, arguments: arguments, said: said) }
        if tool == .drag { return dragApproval(call, tab: tab, arguments: arguments, said: said) }
        if tool == .clickAt { return clickAtApproval(call, tab: tab, arguments: arguments) }
        // A spoken yes is not consent to hand a file to a site.
        if tool == .setFiles { return setFilesApproval(call, arguments: arguments) }
        return elementApproval(call, tool: tool, tab: tab, arguments: arguments, said: said)
    }

    private func elementApproval(
        _ call: ToolCallRef, tool: BrowserTool, tab: Int, arguments: [String: Any], said: String
    ) -> ApprovalRequest? {
        guard let id = ParentToolRunner.intArgument(arguments["element"]),
              let (page, element) = cachedPage(tab, holding: id)
        else { return nil }
        let verdict: HandsVerdict
        switch tool {
        case .click, .doubleClick, .rightClick:
            verdict = BrowserPolicy.clickVerdict(element, said: said, pageOrigin: page.origin)
        case .select:
            // Only a list takes an option: no sheet for a call `execute` refuses anyway.
            guard Self.isList(element), let option = arguments["option"] as? String else { return nil }
            verdict = BrowserPolicy.selectVerdict(element, option: option, said: said, pageOrigin: page.origin)
        default:
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
            let request: ApprovalRequest
            switch tool {
            case .click, .doubleClick, .rightClick:
                request = HandsGate.clickRequest(call, label: Self.shown(element.label), app: page.origin, verb: Self.verb(tool))
            case .select:
                let option = Self.shown(arguments["option"] as? String ?? "")
                let list = Self.shown(element.label)
                request = ApprovalRequest(
                    requestId: UUID().uuidString, toolName: call.name,
                    summary: "choose \(option) in \(list) on \(page.origin)",
                    inputJSON: Self.sheetJSON(["option": option, "list": list, "app": page.origin]))
            default:
                request = HandsGate.request(call, app: page.origin, commandApp: false)
            }
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
        let wasControlled = controls(tab)
        if let denied = await requireControl(tool, tab) { return denied }
        // A child adopted by this very call was never judged by the gate.
        let adopted = !wasControlled
        if tool == .navigate { return await navigate(tab: tab, arguments: arguments, raw: raw, adopted: adopted) }
        if tool == .press { return await press(tab: tab, arguments: arguments, raw: raw, adopted: adopted) }
        return await act(tool, tab: tab, arguments: arguments, raw: raw, adopted: adopted)
    }

    func needsApproval(_ tool: BrowserTool, adopted: Bool) -> ParentToolOutcome {
        fail(tool, "approval_required", adopted
            ? "tab is yours now (opened by a page you control); call again so it can be approved"
            : "this action needs approval before it runs")
    }

    private func act(
        _ tool: BrowserTool, tab: Int, arguments: [String: Any], raw: String, adopted: Bool
    ) async -> ParentToolOutcome {
        guard let id = ParentToolRunner.intArgument(arguments["element"]) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid element")
        }
        var text = ""
        if tool == .type || tool == .select {
            let key = tool == .type ? "text" : "option"
            guard let typed = arguments[key] as? String else {
                return fail(tool, BridgeCode.invalidArgs, "missing \(key)")
            }
            text = typed
        }
        guard let (page, element) = cachedPage(tab, holding: id) else {
            return staleHere(tool, reason: "host_cache_miss")
        }
        if tool == .select, !Self.isList(element) {
            return fail(tool, BridgeCode.notSelectable, BrowserCopy.failure(code: BridgeCode.notSelectable, language()))
        }
        if tool == .type || tool == .select, BrowserPolicy.isSensitive(element) {
            return fail(tool, BridgeCode.secureField, BrowserCopy.failure(code: BridgeCode.secureField, language()))
        }
        guard tickets.redeem(Self.ticket(tool.rawValue, raw, tab: tab, element: element, page: page)) else {
            return needsApproval(tool, adopted: adopted)
        }
        guard await tabIsStillAt(tab, origin: page.origin) else { return leftItsOrigin(tool, tab) }
        // Exhaustive on purpose: a new tool must choose its command here, not fall into a click.
        let command: BrowserCommand
        switch tool {
        case .click: command = .click(tab: tab, generation: page.generation, element: id)
        case .doubleClick: command = .doubleClick(tab: tab, generation: page.generation, element: id)
        case .rightClick: command = .rightClick(tab: tab, generation: page.generation, element: id)
        case .type: command = .type(tab: tab, generation: page.generation, element: id, text: text)
        case .select: command = .select(tab: tab, generation: page.generation, element: id, option: text)
        case .tabs, .read, .scroll, .hover, .press, .drag, .clickAt, .setFiles, .navigate, .open, .take, .release:
            return fail(tool, BridgeCode.invalidArgs, "\(tool.rawValue) does not act on an element")
        }
        switch await channel.send(command, timeout: Self.actTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { forget(tab) }
            if error.code == BridgeCode.optionNotFound { return missedOption(error) }
            return failed(tool, error)
        case .success(let reply):
            // Without this the model reports a multi-paragraph text that went in as one line.
            if reply.doneMessage == BrowserCopy.typedWithoutLineBreaks {
                return ParentToolOutcome(
                    ok: true,
                    output: "typed into [\(id)] without its line breaks, so the text is on one line; read the tab "
                        + "again, and tell the user the line breaks are missing" + afterNote(reply),
                    target: page.origin, tool: tool.rawValue)
            }
            let done = tool == .type ? "typed into" : tool == .select ? "chose an option in" : Self.verb(tool, past: true)
            let base = "\(done) [\(id)]; read the tab again to see the result"
            let output: String
            if reply.isUnconfirmed { output = base + " " + BrowserCopy.pressUnconfirmed(language()) } else { output = base }
            return ParentToolOutcome(
                ok: true, output: output + afterNote(reply),
                target: page.origin, tool: tool.rawValue)
        }
    }

    /// What the action did to the page, in the host's own wording; empty when the extension sent nothing.
    func afterNote(_ reply: BrowserInbound) -> String {
        reply.after.map { " " + BrowserCopy.afterNote($0, language()) } ?? ""
    }

    private func navigate(
        tab: Int, arguments: [String: Any], raw: String, adopted: Bool
    ) async -> ParentToolOutcome {
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
            return needsApproval(tool, adopted: adopted)
        }
        // Security finding M4: the verdict was reached against the origin the
        // tab had when it was last read. The tab's live address decides.
        if let origin, !(await tabIsStillAt(tab, origin: origin)) { return leftItsOrigin(tool, tab) }
        switch await channel.send(.navigate(tab: tab, url: url), timeout: Self.navigateTimeout) {
        case .failure(let error):
            return failed(tool, error)
        case .success(let reply):
            forget(tab)
            // A read right after a slow navigation sees the old or an empty page, and the model would report that.
            let stillLoading: Bool
            stillLoading = reply.doneMessage == BrowserCopy.stillLoading
            return ParentToolOutcome(
                ok: true,
                output: stillLoading
                    ? "tab \(tab) is still loading; wait a moment, then read it with browser_read"
                    : "navigated tab \(tab) and it loaded; read it with browser_read",
                target: url.absoluteString, tool: tool.rawValue)
        }
    }

    /// Incredible lists the options on a miss. The labels are the page's
    /// words, already cut to one short line by `BrowserSanitize`, so they go
    /// after the copy and are declared data like any read.
    private func missedOption(_ error: ContractError) -> ParentToolOutcome {
        let copy = BrowserCopy.failure(code: error.code, language())
        let message = error.message.isEmpty
            ? copy
            : copy + " " + error.message + " " + BrowserCopy.toolDataSuffix(language())
        return fail(.select, error.code, message)
    }

    /// Clipped like a click's sheet: the raw arguments would put up to the
    /// whole text limit of the model's option on the sheet.
    private static func sheetJSON(_ fields: [String: String]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Only strings go in; unreachable, and an empty sheet input still asks.
            return "{}"
        }
    }

    /// The extension's own word for a `<select>`: what `browser_select` can drive.
    private static func isList(_ element: BrowserElement) -> Bool {
        element.inputType == "select"
    }

    /// Fails closed: a tab that cannot be found, or an origin that cannot be
    /// compared, is not a tab that stayed where it was read.
    func tabIsStillAt(_ tab: Int, origin: String) async -> Bool {
        guard !origin.isEmpty, let live = await liveURL(tab) else { return false }
        return BrowserPolicy.sameOrigin(live, origin)
    }

    /// A point or a drag lands on whatever is drawn there, so the origin is too
    /// coarse: a link, a redirect or a pushState to another path of the same
    /// site is another screen. Only the fragment may differ, as an anchor jump
    /// leaves the page as it was read.
    func tabIsStillOn(_ tab: Int, url: String) async -> Bool {
        guard !url.isEmpty, let live = await liveURL(tab) else { return false }
        return Self.withoutFragment(live) == Self.withoutFragment(url)
    }

    private func liveURL(_ tab: Int) async -> String? {
        let asOf = leases.sequence
        guard case .success(.tabs(_, let tabs)) = await channel.send(.tabs, timeout: Self.actTimeout)
        else { return nil }
        leases.noteListing(tabs, asOf: asOf)
        guard let current = tabs.first(where: { $0.id == tab }), !current.url.isEmpty else { return nil }
        return current.url
    }

    private static func withoutFragment(_ url: String) -> String {
        url.firstIndex(of: "#").map { String(url[..<$0]) } ?? url
    }

    func leftItsOrigin(_ tool: BrowserTool, _ tab: Int) -> ParentToolOutcome {
        forget(tab)
        return staleHere(tool, reason: "origin_changed")
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

    /// The press as the sheet and the result name it. Exhaustive, so a new
    /// tool is named here rather than borrowing "click".
    private static func verb(_ tool: BrowserTool, past: Bool = false) -> String {
        switch tool {
        case .doubleClick: return past ? "double-clicked" : "double-click"
        case .rightClick: return past ? "right-clicked" : "right-click"
        case .setFiles: return past ? "uploaded" : "upload"
        case .click, .tabs, .read, .type, .select, .scroll, .hover, .press, .drag, .clickAt, .navigate, .open, .take,
             .release:
            return past ? "clicked" : "click"
        }
    }

    static func shown(_ label: String) -> String {
        label.isEmpty ? "(unnamed control)" : String(oneLine(label).prefix(sheetLabel))
    }
}
