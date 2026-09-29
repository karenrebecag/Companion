import Foundation

/// Wave 18. The browser's tools. They live apart from `ParentTool` on
/// purpose: they exist only while an extension is connected, and a new case
/// in `ParentTool` would break its exhaustive switches.
public enum BrowserTool: String, CaseIterable, Sendable {
    case tabs = "browser_tabs"
    case read = "browser_read"
    case click = "browser_click"
    case type = "browser_type"
    case navigate = "browser_navigate"
    case open = "browser_open"
    case take = "browser_take"
    case release = "browser_release"

    public var isWrite: Bool {
        switch self {
        case .click, .type, .navigate, .open, .take, .release: return true
        case .tabs, .read: return false
        }
    }

    public func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: rawValue,
            description: BrowserCopy.description(self, language) + " " + BrowserCopy.toolDataSuffix(language),
            properties: properties.map {
                ToolProperty(name: $0.name, type: $0.type, description: BrowserCopy.parameter($0.name, language))
            },
            required: properties.filter(\.required).map(\.name))
    }

    private struct Parameter {
        let name: String
        let type: String
        let required: Bool
    }

    private var properties: [Parameter] {
        let tab = Parameter(name: "tab", type: "integer", required: true)
        let element = Parameter(name: "element", type: "integer", required: true)
        switch self {
        case .tabs: return []
        case .read: return [tab, Parameter(name: "selector", type: "string", required: false)]
        case .click: return [tab, element]
        case .type: return [tab, element, Parameter(name: "text", type: "string", required: true)]
        case .navigate: return [tab, Parameter(name: "url", type: "string", required: true)]
        case .open: return [Parameter(name: "url", type: "string", required: true)]
        case .take, .release: return [tab]
        }
    }
}
