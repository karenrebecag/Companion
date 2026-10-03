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
    case press = "browser_press"
    case navigate = "browser_navigate"
    case open = "browser_open"
    case take = "browser_take"
    case release = "browser_release"

    package var isWrite: Bool {
        switch self {
        case .click, .doubleClick, .rightClick, .type, .press, .navigate, .open, .take, .release: return true
        case .tabs, .read: return false
        }
    }

    /// The three presses on an element: a double click or a right click does
    /// whatever a click on that element would and more, so they share its gate.
    package var isClick: Bool {
        self == .click || self == .doubleClick || self == .rightClick
    }

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

    /// The press's element is optional and its key is not typed text, so
    /// both read differently from the shared names.
    private func copyKey(_ name: String) -> String {
        self == .press && (name == "element" || name == "key") ? "press_" + name : name
    }

    private var properties: [Parameter] {
        let tab = Parameter(name: "tab", type: "integer", required: true)
        let element = Parameter(name: "element", type: "integer", required: true)
        switch self {
        case .tabs: return []
        case .read: return [tab, Parameter(name: "selector", type: "string", required: false)]
        case .click, .doubleClick, .rightClick: return [tab, element]
        case .type: return [tab, element, Parameter(name: "text", type: "string", required: true, typed: true)]
        case .press:
            return [tab, Parameter(name: "key", type: "string", required: true, allowed: Self.pressKeys),
                    Parameter(name: "element", type: "integer", required: false),
                    Parameter(name: "times", type: "integer", required: false)]
        case .navigate: return [tab, Parameter(name: "url", type: "string", required: true)]
        case .open: return [Parameter(name: "url", type: "string", required: true)]
        case .take, .release: return [tab]
        }
    }
}
