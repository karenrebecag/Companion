import CompanionCore
import Foundation

/// P4: `browser_press`. Apart from the element writes because its element is
/// optional: without one the key goes to the page's focus, so the ticket is
/// bound to the page that was read rather than to an element of it.
extension BrowserToolRunner {
    private struct Press {
        let key: String
        let times: Int
        let element: Int?
    }

    // MARK: - approval

    func pressApproval(
        _ call: ToolCallRef, tab: Int, arguments: [String: Any], said: String
    ) -> ApprovalRequest? {
        // A malformed call or one with nothing read gets no ticket: `execute` refuses it.
        guard let press = Self.press(arguments), let page = cachedPage(tab),
              case .found(let element) = Self.target(press, in: page)
        else { return nil }
        let ticket = Self.pressTicket(call.arguments, tab: tab, page: page, element: element)
        switch BrowserPolicy.pressVerdict(key: press.key, element: element, said: said, pageOrigin: page.origin) {
        case .refuse:
            return nil
        case .act:
            tickets.issue(ticket)
            return nil
        case .ask:
            let request = ApprovalRequest(
                requestId: UUID().uuidString, toolName: call.name,
                summary: Self.pressSummary(press, element, origin: page.origin),
                inputJSON: Self.pressSheet(press, element, origin: page.origin))
            tickets.park(ticket, id: request.requestId)
            return request
        }
    }

    // MARK: - execution

    func press(tab: Int, arguments: [String: Any], raw: String, adopted: Bool) async -> ParentToolOutcome {
        let tool = BrowserTool.press
        guard let press = Self.press(arguments) else {
            return fail(tool, BridgeCode.invalidArgs, "key must be one of: "
                + BrowserTool.pressKeys.joined(separator: ", ")
                + "; times 1 to \(BrowserTool.pressMaxTimes), and 1 for Enter and Space; element an element number")
        }
        guard let page = cachedPage(tab), case .found(let element) = Self.target(press, in: page) else {
            return staleHere(tool, reason: "host_cache_miss")
        }
        // The gate issued no ticket for it: saying approval_required would invite a retry.
        if let element, BrowserPolicy.pressWritesIntoSecret(key: press.key, element: element) {
            return fail(tool, BridgeCode.secureField, BrowserCopy.failure(code: BridgeCode.secureField, language()))
        }
        guard tickets.redeem(Self.pressTicket(raw, tab: tab, page: page, element: element)) else {
            return needsApproval(tool, adopted: adopted)
        }
        guard await tabIsStillAt(tab, origin: page.origin) else { return leftItsOrigin(tool, tab) }
        let command = BrowserCommand.press(
            tab: tab, key: press.key, times: press.times,
            generation: element == nil ? nil : page.generation, element: element?.id)
        switch await channel.send(command, timeout: Self.actTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { forget(tab) }
            return failed(tool, error)
        case .success(let reply):
            let on = element.map { " on [\($0.id)]" } ?? ""
            let count = press.times == 1 ? "" : " \(press.times) times"
            return ParentToolOutcome(
                ok: true, output: "pressed \(press.key)\(on)\(count); read the tab again to see the result" + afterNote(reply),
                target: page.origin, tool: tool.rawValue)
        }
    }

    // MARK: - arguments

    private enum Target {
        case found(BrowserElement?)
        case missing
    }

    private static func target(_ press: Press, in page: BrowserPage) -> Target {
        guard let id = press.element else { return .found(nil) }
        return page.elements.first(where: { $0.id == id }).map { .found($0) } ?? .missing
    }

    /// nil outside the key list or the count. A JSON `true` arrives as an
    /// NSNumber that `intArgument` would read as 1.
    private static func press(_ arguments: [String: Any]) -> Press? {
        guard let key = arguments["key"] as? String, BrowserTool.pressKeys.contains(key) else { return nil }
        var times = 1
        if let raw = present(arguments["times"]) {
            let most = BrowserTool.pressOnce.contains(key) ? 1 : BrowserTool.pressMaxTimes
            guard let count = integer(raw), (1...most).contains(count) else { return nil }
            times = count
        }
        var element: Int?
        if let raw = present(arguments["element"]) {
            guard let id = integer(raw) else { return nil }
            element = id
        }
        return Press(key: key, times: times, element: element)
    }

    private static func present(_ raw: Any?) -> Any? {
        raw is NSNull ? nil : raw
    }

    private static func integer(_ raw: Any) -> Int? {
        if let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return ParentToolRunner.intArgument(raw)
    }

    // MARK: - tickets and sheet

    /// Bound to the scan generation even without an element: the verdict on
    /// a focus press was reached against the page as it was read.
    static func pressTicket(
        _ arguments: String, tab: Int, page: BrowserPage, element: BrowserElement?
    ) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: BrowserTool.press.rawValue, arguments: arguments, pid: Int32(clamping: tab),
            item: element?.label ?? page.origin, node: element?.id, generation: page.generation)
    }

    /// An Enter in a field is approved for the button it presses, so the
    /// sheet names that button rather than the field.
    private static func pressSummary(_ press: Press, _ element: BrowserElement?, origin: String) -> String {
        let key = press.times == 1 ? press.key : "\(press.key) \(press.times) times"
        guard let element else { return "press \(key) on \(origin)" }
        if let submit = element.submit, !submit.isEmpty, press.key == "Enter" {
            return "press \(key) in \(shown(element.label)), which presses \(shown(submit)), on \(origin)"
        }
        return "press \(key) on \(shown(element.label)) on \(origin)"
    }

    private static func pressSheet(_ press: Press, _ element: BrowserElement?, origin: String) -> String {
        var fields = ["key": press.key, "times": String(press.times), "app": origin]
        if let element {
            fields["element"] = shown(element.label)
            if let submit = element.submit, !submit.isEmpty { fields["submit"] = shown(submit) }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch {
            // Only strings go in; unreachable, and an empty sheet input still asks.
            return "{}"
        }
    }
}
