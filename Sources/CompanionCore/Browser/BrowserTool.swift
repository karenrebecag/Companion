import Foundation

/// Wave 18. The browser's tools. They live apart from `ParentTool` on
/// purpose: they exist only while an extension is connected, and a new case
/// in `ParentTool` would break its exhaustive switches.
package enum BrowserTool: String, CaseIterable, Sendable {
    case tabs = "browser_tabs"
    case read = "browser_read"
    case click = "browser_click"
    case doubleClick = "browser_double_click"
    case rightClick = "browser_right_click"
    case type = "browser_type"
    case select = "browser_select"
    case scroll = "browser_scroll"
    case hover = "browser_hover"
    case press = "browser_press"
    case drag = "browser_drag"
    case clickAt = "browser_click_at"
    case navigate = "browser_navigate"
    case open = "browser_open"
    case take = "browser_take"
    case release = "browser_release"

    package var isWrite: Bool {
        switch self {
        case .click, .doubleClick, .rightClick, .type, .select, .scroll, .hover, .press, .drag, .clickAt, .navigate, .open,
             .take, .release:
            return true
        case .tabs, .read: return false
        }
    }

    /// The three presses on an element: a double click or a right click does
    /// whatever a click on that element would and more, so they share its gate.
    package var isClick: Bool {
        self == .click || self == .doubleClick || self == .rightClick
    }

    /// They move the view or the pointer and change nothing the page holds, so
    /// no sheet; they still need control of the tab and count as writes.
    package var skipsApproval: Bool {
        self == .scroll || self == .hover
    }

    /// Pixels per axis in one call: a few screens, so a runaway loop pages
    /// through a document instead of flinging to its end.
    package static let scrollLimit = 20_000
    /// Incredible's el.press keys, minus anything that reaches the browser
    /// itself (shortcuts, function keys). Kept in step with wire.js PRESS_KEYS.
    package static let pressKeys = [
        "Enter", "Escape", "Tab", "Shift+Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight",
        "Space", "Backspace", "Delete", "Home", "End", "PageUp", "PageDown",
    ]
    package static let pressMaxTimes = 10
    /// The gate judges one activation: a second Enter lands wherever the
    /// first one left the focus. Kept in step with wire.js PRESS_ONCE.
    package static let pressOnce: Set<String> = ["Enter", "Space"]

    /// The largest viewport coordinate click_at takes; no screen is wider, so
    /// a bigger number is a mistake, not a place on the page.
    package static let pointLimit = 20_000

    /// How long the read that click_at's point and drag's target come from
    /// stays good, as in Incredible: after it the page may have moved under them.
    package static let readFreshness: TimeInterval = 60

    package func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: rawValue,
            description: BrowserCopy.description(self, language) + " " + BrowserCopy.toolDataSuffix(language),
            properties: properties.map {
                ToolProperty(name: $0.name, type: $0.type,
                             description: BrowserCopy.parameter(copyKey($0.name), language),
                             allowed: $0.allowed, minLength: $0.typed ? 1 : nil, maxBytes: $0.typed ? ToolProperty.maxTextBytes : nil)
            },
            required: properties.filter(\.required).map(\.name))
    }

    private struct Parameter {
        let name: String
        let type: String
        let required: Bool
        /// Text typed into the page: the same limit as type_text.
        var typed = false
        var allowed: [String]?
    }

    /// browser_type's `text` is what to type; the read's is what to look for. The press's
    /// element is optional and its key is not typed text: each reads differently from the shared names.
    private func copyKey(_ name: String) -> String {
        if self == .read && name == "text" { return "find_text" }
        return self == .press && (name == "element" || name == "key") ? "press_" + name : name
    }

    private var properties: [Parameter] {
        let tab = Parameter(name: "tab", type: "integer", required: true)
        let element = Parameter(name: "element", type: "integer", required: true)
        switch self {
        case .tabs: return []
        case .read:
            return [tab] + [("selector", "string"), ("text", "string"), ("exact", "boolean"), ("role", "string"),
                            ("name", "string"), ("within", "integer"), ("max", "integer"), ("max_chars", "integer")]
                .map { Parameter(name: $0.0, type: $0.1, required: false) }
        case .click, .doubleClick, .rightClick: return [tab, element]
        case .type: return [tab, element, Parameter(name: "text", type: "string", required: true, typed: true)]
        case .select: return [tab, element, Parameter(name: "option", type: "string", required: true, typed: true)]
        case .scroll:
            return [tab, Parameter(name: "dx", type: "integer", required: false),
                    Parameter(name: "dy", type: "integer", required: false),
                    Parameter(name: "element", type: "integer", required: false)]
        case .hover: return [tab, element]
        case .press:
            return [tab, Parameter(name: "key", type: "string", required: true, allowed: Self.pressKeys),
                    Parameter(name: "element", type: "integer", required: false),
                    Parameter(name: "times", type: "integer", required: false)]
        case .drag:
            return [tab, element, Parameter(name: "to", type: "integer", required: false),
                    Parameter(name: "dx", type: "integer", required: false),
                    Parameter(name: "dy", type: "integer", required: false)]
        case .clickAt:
            return [tab, Parameter(name: "x", type: "integer", required: true),
                    Parameter(name: "y", type: "integer", required: true)]
        case .navigate: return [tab, Parameter(name: "url", type: "string", required: true)]
        case .open: return [Parameter(name: "url", type: "string", required: true)]
        case .take, .release: return [tab]
        }
    }
}
