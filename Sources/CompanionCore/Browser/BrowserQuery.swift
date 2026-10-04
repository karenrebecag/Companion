import Foundation

/// An element numbered by one read: the number means nothing without that read's generation.
package struct BrowserElementRef: Sendable, Equatable {
    package var generation: Int
    package var element: Int

    package init(generation: Int, element: Int) {
        self.generation = generation
        self.element = element
    }
}

/// H-7 P2a: Incredible reads by finder (find_by_text, find_by_role, scoped el.find, max,
/// max_chars) rather than by serializing the whole page; `browser_read` takes the same ways in.
/// An empty query is the whole page, as before.
package struct BrowserQuery: Sendable, Equatable {
    package var selector: String?
    package var text: String?
    package var exact: Bool
    package var role: String?
    package var name: String?
    package var within: BrowserElementRef?
    package var max: Int?
    package var maxChars: Int?

    package init(
        selector: String? = nil, text: String? = nil, exact: Bool = false, role: String? = nil, name: String? = nil,
        within: BrowserElementRef? = nil, max: Int? = nil, maxChars: Int? = nil
    ) {
        self.selector = selector
        self.text = text
        self.exact = exact
        self.role = role
        self.name = name
        self.within = within
        self.max = max
        self.maxChars = maxChars
    }

    /// Only what was asked travels, so an older extension sees the read it always got.
    var wireArguments: [String: Any] {
        var out: [String: Any] = ["selector": selector.map { $0 as Any } ?? NSNull()]
        if let text { out["text"] = text }
        if exact { out["exact"] = true }
        if let role { out["role"] = role }
        if let name { out["name"] = name }
        if let within {
            out["generation"] = within.generation
            out["within"] = within.element
        }
        if let max { out["max"] = max }
        if let maxChars { out["maxChars"] = maxChars }
        return out
    }
}
