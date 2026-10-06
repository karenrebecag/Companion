import CompanionCore
import Foundation

/// H-7 P5b: scroll and hover. They change nothing the page holds, so no
/// ticket; control of the tab is still required, and an element they name is
/// bound to the tab's last read and to the origin it was read at.
extension BrowserToolRunner {
    func hover(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let tool = BrowserTool.hover
        guard let tab = Self.tab(arguments) else { return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab") }
        if let denied = await requireControl(tool, tab) { return denied }
        guard let id = ParentToolRunner.intArgument(arguments["element"]) else {
            return fail(tool, BridgeCode.invalidArgs, "missing or invalid element")
        }
        switch await readElement(tool, tab: tab, id: id) {
        case .failure(let refused): return refused.outcome
        case .success(let page):
            return await send(tool, .hover(tab: tab, generation: page.generation, element: id), tab: tab,
                              target: page.origin,
                              done: "hovered over [\(id)]; read the tab again to see what it revealed")
        }
    }

    func scroll(_ arguments: [String: Any]) async -> ParentToolOutcome {
        let tool = BrowserTool.scroll
        guard let tab = Self.tab(arguments) else { return fail(tool, BridgeCode.invalidArgs, "missing or invalid tab") }
        if let denied = await requireControl(tool, tab) { return denied }
        switch Self.scrollRequest(arguments) {
        case .failure(let error):
            return fail(tool, BridgeCode.invalidArgs, error.message)
        case .success(.element(let id)):
            switch await readElement(tool, tab: tab, id: id) {
            case .failure(let refused): return refused.outcome
            case .success(let page):
                return await send(tool, .scrollTo(tab: tab, generation: page.generation, element: id), tab: tab,
                                  target: page.origin,
                                  done: "scrolled [\(id)] into view; read the tab again to see what is around it")
            }
        case .success(.offset(let dx, let dy)):
            return await send(tool, .scroll(tab: tab, dx: dx, dy: dy), tab: tab,
                              target: cachedPage(tab)?.origin ?? "",
                              done: "scrolled tab \(tab) by dx \(dx), dy \(dy); read the tab again to see what came into view")
        }
    }

    enum ScrollRequest: Equatable {
        case offset(dx: Int, dy: Int)
        case element(Int)
    }

    /// One of the two shapes, never both: an offset and an element would each
    /// decide where the page ends up.
    static func scrollRequest(_ arguments: [String: Any]) -> Result<ScrollRequest, ScrollArgumentError> {
        func axis(_ key: String) -> Result<Int, ScrollArgumentError> {
            guard arguments[key] != nil else { return .success(0) }
            guard let value = ParentToolRunner.intArgument(arguments[key]) else {
                return .failure(ScrollArgumentError("\(key) must be a whole number of pixels"))
            }
            // A range test, not abs(): abs(Int.min) traps, and these numbers come from the model or a bridge client.
            guard (-BrowserTool.scrollLimit...BrowserTool.scrollLimit).contains(value) else {
                return .failure(ScrollArgumentError("\(key) is more than \(BrowserTool.scrollLimit) pixels; scroll in steps"))
            }
            return .success(value)
        }
        let hasOffset = arguments["dx"] != nil || arguments["dy"] != nil
        if let raw = arguments["element"] {
            guard !hasOffset else { return .failure(ScrollArgumentError("give dx and dy, or element, not both")) }
            guard let id = ParentToolRunner.intArgument(raw) else {
                return .failure(ScrollArgumentError("missing or invalid element"))
            }
            return .success(.element(id))
        }
        let dx: Int
        let dy: Int
        switch (axis("dx"), axis("dy")) {
        case (.failure(let error), _), (_, .failure(let error)): return .failure(error)
        case (.success(let x), .success(let y)): dx = x; dy = y
        }
        guard dx != 0 || dy != 0 else { return .failure(ScrollArgumentError("give dx or dy in pixels, or an element")) }
        return .success(.offset(dx: dx, dy: dy))
    }

    struct ScrollArgumentError: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// The element as the newest kept read numbered it, on a tab still at that read's origin.
    private func readElement(_ tool: BrowserTool, tab: Int, id: Int) async -> Result<BrowserPage, OutcomeError> {
        guard let (page, _) = cachedPage(tab, holding: id) else {
            return .failure(OutcomeError(staleHere(tool, reason: "host_cache_miss")))
        }
        guard await tabIsStillAt(tab, origin: page.origin) else { return .failure(OutcomeError(leftItsOrigin(tool, tab))) }
        return .success(page)
    }

    struct OutcomeError: Error {
        let outcome: ParentToolOutcome
        init(_ outcome: ParentToolOutcome) { self.outcome = outcome }
    }

    private func send(
        _ tool: BrowserTool, _ command: BrowserCommand, tab: Int, target: String, done: String
    ) async -> ParentToolOutcome {
        switch await channel.send(command, timeout: Self.actTimeout) {
        case .failure(let error):
            if error.code == BridgeCode.staleId { forget(tab) }
            return failed(tool, error)
        case .success:
            return ParentToolOutcome(ok: true, output: done, target: target, tool: tool.rawValue)
        }
    }
}
