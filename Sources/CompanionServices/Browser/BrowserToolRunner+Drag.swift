import CompanionCore
import Foundation

/// H-7 P7: drag and click_at. A drag presses one element and lets go over
/// another, so it passes the click's gate on both ends; a point, or a drag by
/// an offset, has no label at that end to judge, so it always asks. Every call
/// here acts on the read it was approved against: that read goes stale after
/// `BrowserTool.readFreshness`, on navigation or on another read, and a stale
/// call is refused, never retried.
extension BrowserToolRunner {
    enum DragTarget: Equatable {
        case element(Int)
        case offset(dx: Int, dy: Int)
    }

    struct DragRequest: Equatable {
        let element: Int
        let target: DragTarget
    }

    // MARK: - approval

    func dragApproval(_ call: ToolCallRef, tab: Int, arguments: [String: Any], said: String) -> ApprovalRequest? {
        guard case .success(let request) = Self.dragRequest(arguments), let page = cachedPage(tab),
              let source = page.elements.first(where: { $0.id == request.element })
        else { return nil }
        var verdict = BrowserPolicy.clickVerdict(source, said: said, pageOrigin: page.origin)
        let named: String
        let item: String
        guard freshPage(tab) != nil else { return nil }
        switch request.target {
        case .element(let to):
            guard let target = page.elements.first(where: { $0.id == to }) else { return nil }
            verdict = Self.stricter(verdict, BrowserPolicy.clickVerdict(target, said: said, pageOrigin: page.origin))
            named = "\(Self.shown(source.label)) to \(Self.shown(target.label))"
            item = Self.dragItem(source, target)
        case .offset(let dx, let dy):
            // No element at the drop end to judge, so like a bare point it asks.
            verdict = Self.stricter(verdict, .ask)
            named = "\(Self.shown(source.label)) by (\(dx), \(dy))"
            item = source.label
        }
        let ticket = Self.dragTicket(call.name, call.arguments, tab: tab, source: source, item: item, page: page)
        switch verdict {
        case .refuse:
            return nil
        case .act:
            tickets.issue(ticket)
            return nil
        case .ask:
            let sheet = HandsGate.clickRequest(call, label: named, app: page.origin, verb: "drag")
            tickets.park(ticket, id: sheet.requestId)
            return sheet
        }
    }

    // HACK: the sheet names a point and the origin, not what is drawn there: approval is synchronous and a read
    // carries no geometry. Have the read report each element's box and name the one under the point once the
    // model uses click_at for more than canvases and maps.
    func clickAtApproval(_ call: ToolCallRef, tab: Int, arguments: [String: Any]) -> ApprovalRequest? {
        guard case .success(let point) = Self.point(arguments), let page = freshPage(tab) else { return nil }
        let sheet = HandsGate.clickRequest(call, label: "(\(point.x), \(point.y))", app: page.origin, verb: "click at")
        tickets.park(Self.pointTicket(call.name, call.arguments, tab: tab, page: page), id: sheet.requestId)
        return sheet
    }

    // MARK: - execution

    func drag(_ arguments: [String: Any], raw: String) async -> ParentToolOutcome {
        let tool = BrowserTool.drag
        guard let tab = Self.tab(arguments) else { return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab") }
        let wasControlled = controls(tab)
        if let denied = await requireControl(tool, tab) { return denied }
        let request: DragRequest
        switch Self.dragRequest(arguments) {
        case .failure(let error): return fail(tool, BridgeCode.invalidArgs, error.message)
        case .success(let parsed): request = parsed
        }
        guard let page = cachedPage(tab), let source = page.elements.first(where: { $0.id == request.element }) else {
            return stale(tool, reason: "host_cache_miss")
        }
        // Checked before the ticket: a yes given a minute ago was for a screen that may be gone.
        guard freshPage(tab) != nil else { return stale(tool, reason: "read_expired") }
        let command: BrowserCommand
        let item: String
        let done: String
        switch request.target {
        case .element(let to):
            guard let target = page.elements.first(where: { $0.id == to }) else { return stale(tool, reason: "host_cache_miss") }
            command = .dragTo(tab: tab, generation: page.generation, element: source.id, to: to)
            item = Self.dragItem(source, target)
            done = "dragged [\(source.id)] to [\(to)]"
        case .offset(let dx, let dy):
            command = .dragBy(tab: tab, generation: page.generation, element: source.id, dx: dx, dy: dy)
            item = source.label
            done = "dragged [\(source.id)] by (\(dx), \(dy))"
        }
        let ticket = Self.dragTicket(tool.rawValue, raw, tab: tab, source: source, item: item, page: page)
        guard tickets.redeem(ticket) else {
            if tickets.voidSuperseded(by: ticket) { return stale(tool) }
            return needsApproval(tool, adopted: !wasControlled)
        }
        guard await tabIsStillOn(tab, url: page.url) else { return leftItsOrigin(tool, tab) }
        return await press(tool, command, tab: tab, target: page.origin, done: done)
    }

    func clickAt(_ arguments: [String: Any], raw: String) async -> ParentToolOutcome {
        let tool = BrowserTool.clickAt
        guard let tab = Self.tab(arguments) else { return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab") }
        let wasControlled = controls(tab)
        if let denied = await requireControl(tool, tab) { return denied }
        let point: (x: Int, y: Int)
        switch Self.point(arguments) {
        case .failure(let error): return fail(tool, BridgeCode.invalidArgs, error.message)
        case .success(let parsed): point = parsed
        }
        guard let page = freshPage(tab) else { return stale(tool, reason: "read_expired") }
        let ticket = Self.pointTicket(tool.rawValue, raw, tab: tab, page: page)
        guard tickets.redeem(ticket) else {
            if tickets.voidSuperseded(by: ticket) { return stale(tool) }
            return needsApproval(tool, adopted: !wasControlled)
        }
        guard await tabIsStillOn(tab, url: page.url) else { return leftItsOrigin(tool, tab) }
        return await press(tool, .clickAt(tab: tab, generation: page.generation, x: point.x, y: point.y), tab: tab,
                           target: page.origin, done: "clicked at (\(point.x), \(point.y))")
    }

    // MARK: - arguments

    /// A source and exactly one way to move it: onto another element, or by
    /// an offset that goes somewhere.
    static func dragRequest(_ arguments: [String: Any]) -> Result<DragRequest, ScrollArgumentError> {
        guard let element = ParentToolRunner.intArgument(arguments["element"]) else {
            return .failure(ScrollArgumentError("missing or invalid element"))
        }
        let hasOffset = arguments["dx"] != nil || arguments["dy"] != nil
        if let raw = arguments["to"] {
            guard !hasOffset else { return .failure(ScrollArgumentError("give to, or dx and dy, not both")) }
            guard let to = ParentToolRunner.intArgument(raw) else {
                return .failure(ScrollArgumentError("to must be an element number from the last read"))
            }
            guard to != element else { return .failure(ScrollArgumentError("to must be another element")) }
            return .success(DragRequest(element: element, target: .element(to)))
        }
        guard hasOffset else { return .failure(ScrollArgumentError("give to, or dx and dy in pixels")) }
        let dx: Int
        let dy: Int
        switch (offset(arguments, "dx"), offset(arguments, "dy")) {
        case (.failure(let error), _), (_, .failure(let error)): return .failure(error)
        case (.success(let x), .success(let y)): dx = x; dy = y
        }
        guard dx != 0 || dy != 0 else { return .failure(ScrollArgumentError("a drag by (0, 0) moves nothing")) }
        return .success(DragRequest(element: element, target: .offset(dx: dx, dy: dy)))
    }

    private static func offset(_ arguments: [String: Any], _ key: String) -> Result<Int, ScrollArgumentError> {
        guard arguments[key] != nil else { return .success(0) }
        // A range test, not abs(): abs(Int.min) traps.
        guard let value = ParentToolRunner.intArgument(arguments[key]),
              (-BrowserTool.pointLimit...BrowserTool.pointLimit).contains(value)
        else { return .failure(ScrollArgumentError("\(key) must be whole pixels, at most \(BrowserTool.pointLimit)")) }
        return .success(value)
    }

    static func point(_ arguments: [String: Any]) -> Result<(x: Int, y: Int), ScrollArgumentError> {
        func coordinate(_ key: String) -> Int? {
            ParentToolRunner.intArgument(arguments[key]).flatMap { (0...BrowserTool.pointLimit).contains($0) ? $0 : nil }
        }
        guard let x = coordinate("x"), let y = coordinate("y") else {
            return .failure(ScrollArgumentError("x and y must be whole pixels inside the visible page"))
        }
        return .success((x, y))
    }

    // MARK: - tickets

    /// Bound to the source node, the generation and both labels: a page that
    /// relabels either end under the same ids does not inherit the yes.
    static func dragTicket(
        _ name: String, _ arguments: String, tab: Int, source: BrowserElement, item: String, page: BrowserPage
    ) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: name, arguments: arguments, pid: Int32(clamping: tab), item: item, node: source.id,
            generation: page.generation)
    }

    /// Bound to the origin and the generation of the read the point came from.
    static func pointTicket(_ name: String, _ arguments: String, tab: Int, page: BrowserPage) -> ApprovalTickets.Ticket {
        ApprovalTickets.Ticket(
            name: name, arguments: arguments, pid: Int32(clamping: tab), item: page.origin, generation: page.generation)
    }

    /// A separator no label can carry, so "a" + "b c" never equals "a b" + "c".
    private static func dragItem(_ source: BrowserElement, _ target: BrowserElement) -> String {
        source.label + "\u{1F}" + target.label
    }

    static func stricter(_ first: HandsVerdict, _ second: HandsVerdict) -> HandsVerdict {
        switch (first, second) {
        case (.refuse, _): return first
        case (_, .refuse): return second
        case (.ask, _), (_, .ask): return .ask
        case (.act, .act): return .act
        }
    }

    private func stale(_ tool: BrowserTool, reason: String = "superseded") -> ParentToolOutcome {
        staleHere(tool, reason: reason)
    }

    private func press(
        _ tool: BrowserTool, _ command: BrowserCommand, tab: Int, target: String, done: String
    ) async -> ParentToolOutcome {
        switch await channel.send(command, timeout: Self.actTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { forget(tab) }
            return failed(tool, error)
        case .success(let reply):
            return ParentToolOutcome(
                ok: true, output: "\(done); read the tab again to see the result" + afterNote(reply), target: target, tool: tool.rawValue)
        }
    }
}
