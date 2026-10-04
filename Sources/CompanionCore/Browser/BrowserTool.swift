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
    case navigate = "browser_navigate"
    case open = "browser_open"
    case take = "browser_take"
    case release = "browser_release"

    package var isWrite: Bool {
        switch self {
        case .click, .doubleClick, .rightClick, .type, .navigate, .open, .take, .release: return true
        case .tabs, .read: return false
        }
    }

    /// The three presses on an element: a double click or a right click does
    /// whatever a click on that element would and more, so they share its gate.
    package var isClick: Bool {
        self == .click || self == .doubleClick || self == .rightClick
    }

    package func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: rawValue,
            description: BrowserCopy.description(self, language) + " " + BrowserCopy.toolDataSuffix(language),
            properties: properties.map {
                ToolProperty(name: $0.name, type: $0.type, description: BrowserCopy.parameter(copyKey($0.name), language),
                             minLength: $0.typed ? 1 : nil, maxBytes: $0.typed ? ToolProperty.maxTextBytes : nil)
            },
            required: properties.filter(\.required).map(\.name))
    }

    /// browser_type's `text` is what to type; the read's is what to look for, under the same name.
    private func copyKey(_ name: String) -> String {
        self == .read && name == "text" ? "find_text" : name
    }

    private struct Parameter {
        let name: String
        let type: String
        let required: Bool
        /// Text typed into the page: the same limit as type_text.
        var typed = false
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
        case .navigate: return [tab, Parameter(name: "url", type: "string", required: true)]
        case .open: return [Parameter(name: "url", type: "string", required: true)]
        case .take, .release: return [tab]
        }
    }
}
