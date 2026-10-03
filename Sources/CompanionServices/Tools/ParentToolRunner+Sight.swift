import CompanionCore
import Foundation

/// The latest look per process (Wave 16a). A click names an id from it; the
/// adapter's generation says whether the handles behind it are still live.
final class ScanMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: (pid: Int32, scan: ScreenScan)?

    func remember(_ scan: ScreenScan, pid: Int32) { lock.withLock { latest = (pid, scan) } }

    func scan(for pid: Int32) -> ScreenScan? {
        lock.withLock { latest?.pid == pid ? latest?.scan : nil }
    }
}

extension ParentToolRunner {
    /// A click on a delete/pay/send button asks unless the user used a word
    /// of that family; the gate issues the ticket either way it clears.
    func clickApproval(
        _ call: ToolCallRef, said: String, hands: ScreenHands, pid: Int32
    ) -> ApprovalRequest? {
        guard let (element, generation) = Self.clickTarget(call, hands: hands, pid: pid),
              HandsGate.clickNeedsTicket(label: element.label, context: element.context)
        else { return nil }
        let ticket = ApprovalTickets.Ticket.click(call, pid: pid, element: element, generation: generation)
        switch HandsGate.clickVerdict(label: element.label, context: element.context, said: said) {
        case .act:
            hands.tickets.issue(ticket)
            return nil
        case .refuse:
            // No ticket: `execute` refuses the click for lack of one.
            return nil
        case .ask:
            let app = hands.bundleID(pid) ?? "app"
            let shown = element.label.isEmpty ? "(\(element.kind) [\(element.node)] sin nombre)" : element.label
            let request = HandsGate.clickRequest(call, label: shown, app: app)
            hands.tickets.park(ticket, id: request.requestId)
            return request
        }
    }

    /// The same gate as a click, for the item the menu path RESOLVES to: the
    /// adapter matches partial names, so the ticket is bound to the resolved
    /// title and the sheet names it. The typed name is judged too, so a
    /// destructive word the model typed still asks.
    func menuApproval(
        _ call: ToolCallRef, said: String, hands: ScreenHands, pid: Int32,
        ticket: ApprovalTickets.Ticket
    ) -> ApprovalRequest? {
        let path = HandsGate.menuPath(ToolArguments.parse(call.arguments) ?? [:])
        let resolved = hands.screen?.menuTitle(path: path, pid: pid)
        guard HandsGate.menuNeedsTicket(path: path, resolved: resolved) else { return nil }
        let bound = ApprovalTickets.Ticket(
            name: ticket.name, arguments: ticket.arguments, pid: pid, item: resolved ?? path.last ?? "")
        guard HandsGate.menuVerdict(path: path, resolved: resolved, said: said) == .ask else {
            hands.tickets.issue(bound)
            return nil
        }
        let request = HandsGate.menuRequest(
            call, path: path, resolved: resolved, app: hands.bundleID(pid) ?? "app")
        hands.tickets.park(bound, id: request.requestId)
        return request
    }

    static func clickTarget(
        _ call: ToolCallRef, hands: ScreenHands, pid: Int32
    ) -> (element: ScreenElement, generation: Int)? {
        guard let arguments = ToolArguments.parse(call.arguments), let id = intArgument(arguments["id"]),
              let scan = hands.scans.scan(for: pid), let element = scan.element(id: id)
        else { return nil }
        return (element, scan.generation)
    }

    static func intArgument(_ raw: Any?) -> Int? {
        if let number = raw as? Int { return number }
        if let text = raw as? String { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func runSee(_ arguments: [String: Any], hands: ScreenHands, pid: Int32) async -> ParentToolOutcome {
        guard let see = hands.see else {
            return .failed(Self.handsError("no_vision", "no screen vision"), tool: ParentTool.see.rawValue)
        }
        guard hands.screenRecording() else {
            Log.app("sight: see refused, no Screen Recording pid=\(pid)")
            return .failed(Self.handsError(BridgeCode.screenRecordingRequired, BridgeMessages.screenRecordingRequired),
                           tool: ParentTool.see.rawValue)
        }
        let app = hands.reader.focusedField(pid: pid)?.app
        let request = SeeRequest(
            app: app, question: arguments["question"] as? String, pid: pid)
        guard let brief = await see(request) else {
            Log.app("sight: see failed pid=\(pid)")
            return .failed(Self.handsError(
                "no_capture", "no screen capture (Screen Recording off, or no OpenAI key)"),
                tool: ParentTool.see.rawValue)
        }
        // Locked while capturing: the pixels may be the lock screen, so they never reach the model.
        guard !hands.locked() else {
            Log.app("sight: see dropped, session locked during the capture pid=\(pid)")
            return .failed(Self.handsError(BridgeCode.screenLocked, BridgeMessages.screenLocked),
                           tool: ParentTool.see.rawValue)
        }
        let lines = [brief.summary].compactMap { $0 } + brief.snippets.map { "- " + $0.text }
        Log.app("sight: see snippets=\(brief.snippets.count) pid=\(pid)")
        return ParentToolOutcome(ok: true, output: ScreenSeePrompt.envelope(lines.joined(separator: "\n")),
                                 tool: ParentTool.see.rawValue)
    }

    func runSight(
        _ tool: ParentTool, _ call: ToolCallRef, _ arguments: [String: Any],
        hands: ScreenHands, pid: Int32, bundle: String
    ) async -> ParentToolOutcome {
        guard let screen = hands.screen else {
            return .failed(Self.handsError("needs_accessibility", "no screen access"), tool: tool.rawValue)
        }
        let sight = SightAct(hands: hands, screen: screen, pid: pid, bundle: bundle, tool: tool)
        switch tool {
        case .look: return sight.look()
        case .click: return await hands.observing(pid: pid) { sight.click(call, arguments) }
        case .scroll: return sight.scroll(arguments)
        default: return await hands.observing(pid: pid) { sight.menu(call, arguments) }
        }
    }
}

/// One sight call against one captured pid. Logs carry counts, ids, pid and
/// bundle — never labels, values or window titles.
private struct SightAct {
    let hands: ScreenHands
    let screen: any ScreenActing
    let pid: Int32
    let bundle: String
    let tool: ParentTool

    private func fail(_ code: String, _ message: String) -> ParentToolOutcome {
        Log.app("sight: \(tool.rawValue) \(code) pid=\(pid) bundle=\(bundle)")
        return .failed(ParentToolRunner.handsError(code, message), tool: tool.rawValue)
    }

    private var appName: String {
        hands.reader.focusedField(pid: pid)?.app ?? bundle
    }

    func look() -> ParentToolOutcome {
        guard let walk = screen.walk(pid: pid) else {
            return fail("no_window", "no readable window in the app in front")
        }
        let scan = ScreenScan.build(walk, app: appName)
        hands.scans.remember(scan, pid: pid)
        Log.app("sight: look elements=\(scan.elements.count) nodes=\(walk.nodes.count) "
            + "partial=\(scan.partial) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: scan.render(), tool: tool.rawValue)
    }

    func click(_ call: ToolCallRef, _ arguments: [String: Any]) -> ParentToolOutcome {
        guard let id = ParentToolRunner.intArgument(arguments["id"]) else {
            return .failed(.invalidArgs("missing id"), tool: tool.rawValue)
        }
        guard let scan = hands.scans.scan(for: pid) else {
            return fail("look_first", "call look first; ids come from it")
        }
        guard let element = scan.element(id: id) else {
            return fail("unknown_id", "no control [\(id)] in the latest look; look again")
        }
        if HandsGate.clickNeedsTicket(label: element.label, context: element.context),
           !hands.tickets.redeem(.click(call, pid: pid, element: element, generation: scan.generation)) {
            return fail("approval_required", "this button deletes, pays or sends; it needs approval")
        }
        switch screen.click(node: element.node, generation: scan.generation, pid: pid, label: element.label) {
        case .clicked(let route):
            Log.app("sight: click id=\(id) via=\(route.rawValue) pid=\(pid) bundle=\(bundle)")
            // With an observer the result ends with what changed; without
            // one the model is the only eyes left.
            let next = hands.changes == nil ? "; look again to see the result" : "."
            return ParentToolOutcome(
                ok: true, output: "clicked [\(id)] \(element.kind) \"\(element.label)\"" + next,
                tool: tool.rawValue)
        case .stale:
            return fail("stale_id", "the window changed since that look; look again")
        case .refused:
            return fail("refused", "the control did not accept the click")
        }
    }

    func scroll(_ arguments: [String: Any]) -> ParentToolOutcome {
        let raw = (arguments["direction"] as? String ?? "").lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard let direction = ScrollDirection(rawValue: raw) else {
            return .failed(.invalidArgs(
                "direction must be one of: " + ScrollDirection.allCases.map(\.rawValue).joined(separator: ", ")),
                tool: tool.rawValue)
        }
        let scan = hands.scans.scan(for: pid)
        let node = ParentToolRunner.intArgument(arguments["id"]).flatMap { scan?.element(id: $0)?.node }
        if direction == .intoView, node == nil {
            return .failed(.invalidArgs("into_view needs the id of a control from your latest look"),
                           tool: tool.rawValue)
        }
        guard screen.scroll(node: node, generation: scan?.generation ?? -1, direction: direction, pid: pid)
        else { return fail("not_scrollable", "nothing in the window could be scrolled") }
        Log.app("sight: scroll \(direction.rawValue) pid=\(pid) bundle=\(bundle)")
        let done = direction == .intoView ? "brought into view" : "scrolled \(direction.rawValue)"
        return ParentToolOutcome(ok: true, output: done + "; look again", tool: tool.rawValue)
    }

    func menu(_ call: ToolCallRef, _ arguments: [String: Any]) -> ParentToolOutcome {
        let path = HandsGate.menuPath(arguments)
        guard !path.isEmpty else { return .failed(.invalidArgs("missing path"), tool: tool.rawValue) }
        guard let resolved = screen.menuTitle(path: path, pid: pid) else {
            return fail("menu_not_found", "no menu item at that path")
        }
        guard screen.menuEnabled(path: path, pid: pid) else {
            return fail("menu_disabled", "the menu item \"\(resolved)\" is greyed out right now; "
                + "the app may need a selection or another state first")
        }
        if HandsGate.menuNeedsTicket(path: path, resolved: resolved),
           !hands.tickets.redeem(.init(name: call.name, arguments: call.arguments, pid: pid, item: resolved)) {
            return fail("approval_required", "this menu item cannot be undone (delete, pay, send, quit or close); it needs approval")
        }
        guard let item = screen.menu(path: path, pid: pid, expecting: resolved) else {
            return fail("menu_not_found", "the menu item is gone or changed since it was read")
        }
        Log.app("sight: menu steps=\(path.count) pid=\(pid) bundle=\(bundle)")
        return ParentToolOutcome(ok: true, output: "chose \(item)", tool: tool.rawValue)
    }
}
