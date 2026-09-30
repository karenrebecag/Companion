import Foundation

// Wave 16a. The parent's sight: the Accessibility tree of the window in
// front, flattened and numbered so the brain — which reads text, not
// pixels — can name what to press. Incredible's `scan` does the same.

/// One node of the walk, as the adapter read it. `label` is the element's
/// own name (title, description, placeholder); `value` is its content.
public struct ScanNode: Sendable, Equatable {
    public var role: String
    public var subrole: String
    public var label: String
    public var value: String?
    public var secure: Bool
    /// 0 = the window itself; each dialog, sheet or alert gets its own
    /// number, so a neutral "Sí" can be judged by what its dialog says.
    public var group: Int

    public init(
        role: String, subrole: String, label: String, value: String?, secure: Bool, group: Int = 0
    ) {
        self.role = role
        self.subrole = subrole
        self.label = label
        self.value = value
        self.secure = secure
        self.group = group
    }
}

/// One walk of one window. `generation` ties the ids handed to the model to
/// the element handles the adapter kept: a newer walk makes them stale.
public struct ScreenWalk: Sendable, Equatable {
    public var nodes: [ScanNode]
    public var partial: Bool
    public var window: String
    public var generation: Int

    public init(nodes: [ScanNode], partial: Bool, window: String, generation: Int) {
        self.nodes = nodes
        self.partial = partial
        self.window = window
        self.generation = generation
    }
}

public struct ScreenElement: Sendable, Equatable {
    public var id: Int
    /// Index into the walk's nodes: what the adapter presses.
    public var node: Int
    public var kind: String
    public var label: String
    /// The text of the dialog this control sits in; empty in the window.
    public var context: String
}

public struct ScreenScan: Sendable, Equatable {
    /// Enough for a dialog, a form or a mail list; a full web page is cut
    /// and says so, as Incredible's scan does.
    public static let maxElements = 150
    public static let maxChars = 6_000
    static let maxLine = 200

    public var app: String
    public var window: String
    public var generation: Int
    public var elements: [ScreenElement]
    public var partial: Bool
    var lines: [String]

    public func element(id: Int) -> ScreenElement? {
        elements.first { $0.id == id }
    }

    public func render() -> String {
        var text = "window \"\(window)\" (\(app))"
        for line in lines { text += "\n" + line }
        if partial {
            text += "\n(partial: the window has more than this; scroll or ask about one part)"
        }
        return text
    }

    public static func build(_ walk: ScreenWalk, app: String) -> ScreenScan {
        var elements: [ScreenElement] = []
        var lines: [String] = []
        var chars = 0
        var seenText: Set<String> = []
        var partial = walk.partial
        let contexts = dialogTexts(walk.nodes)
        for (index, node) in walk.nodes.enumerated() {
            let line: String
            if let kind = ScreenRoles.kind(node) {
                guard elements.count < maxElements else { partial = true; break }
                let id = elements.count + 1
                let label = clip(node.label)
                elements.append(ScreenElement(
                    id: id, node: index, kind: kind, label: label,
                    context: contexts[node.group] ?? ""))
                line = "[\(id)] \(kind) \"\(label)\"" + valueSuffix(node)
            } else if ScreenRoles.isText(node.role) {
                let text = clip(node.value ?? node.label)
                guard !text.isEmpty, seenText.insert(text).inserted else { continue }
                line = "- " + text
            } else {
                continue
            }
            guard chars + line.count <= maxChars else { partial = true; break }
            chars += line.count + 1
            lines.append(line)
        }
        return ScreenScan(app: app, window: walk.window, generation: walk.generation,
                          elements: elements, partial: partial, lines: lines)
    }

    /// Every dialog's own words — its text and its buttons — joined, never
    /// a secure field's value.
    static func dialogTexts(_ nodes: [ScanNode]) -> [Int: String] {
        var texts: [Int: [String]] = [:]
        for node in nodes where node.group > 0 {
            let words = [node.label, node.secure ? nil : node.value].compactMap { $0 }
                .filter { !$0.isEmpty }
            texts[node.group, default: []] += words
        }
        return texts.mapValues { $0.joined(separator: " ") }
    }

    private static func valueSuffix(_ node: ScanNode) -> String {
        guard !node.secure, let value = node.value.map(clipTail), !value.isEmpty,
              value != clip(node.label)
        else { return "" }
        return " = \"\(value)\""
    }

    /// A field's end is where the cursor and the latest output usually are.
    static func clipTail(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > maxLine ? "…" + String(flat.suffix(maxLine)) : flat
    }

    public static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > maxLine ? String(flat.prefix(maxLine)) + "…" : flat
    }
}

/// Which Accessibility roles are something to press or fill, and the short
/// word the model reads for each.
public enum ScreenRoles {
    static let kinds: [String: String] = [
        "AXButton": "button", "AXLink": "link", "AXCheckBox": "checkbox",
        "AXRadioButton": "radio", "AXPopUpButton": "popup", "AXMenuButton": "menu button",
        "AXMenuItem": "menu item", "AXTextField": "field", "AXTextArea": "text area",
        "AXComboBox": "combo box", "AXSearchField": "search field", "AXTab": "tab",
        "AXDisclosureTriangle": "disclosure", "AXSlider": "slider", "AXIncrementor": "stepper",
    ]

    public static func kind(_ node: ScanNode) -> String? {
        if node.secure { return "password field" }
        return kinds[node.role]
    }

    public static func isControl(_ role: String) -> Bool {
        kinds[role] != nil
    }

    public static func isText(_ role: String) -> Bool {
        role == "AXStaticText" || role == "AXHeading"
    }

    /// Roles worth walking into for their children, and roles the walk reads.
    public static func isInteresting(_ role: String) -> Bool {
        kinds[role] != nil || isText(role)
    }
}

// MARK: - Ports

public enum ScrollDirection: String, Sendable, Equatable, CaseIterable {
    case up, down
}

/// How a click landed, in Incredible's order: the element's own press
/// action, focusing it (a field), or a mouse click posted to the process.
public enum ClickRoute: String, Sendable, Equatable {
    case press, focus, mouse
}

public enum ClickOutcome: Sendable, Equatable {
    case clicked(ClickRoute)
    /// The walk that produced the id is no longer the latest.
    case stale
    /// The element refused every route, or it is a secure field.
    case refused
}

/// The window of one process, read and acted on through Accessibility. The
/// adapter keeps the element handles of its latest walk only.
public protocol ScreenActing: Sendable {
    func walk(pid: Int32) -> ScreenWalk?
    /// `label` is what the user or the sheet saw: a control whose live label
    /// changed since the look is stale, never pressed.
    func click(node: Int, generation: Int, pid: Int32, label: String) -> ClickOutcome
    func scroll(node: Int?, generation: Int, direction: ScrollDirection, pid: Int32) -> Bool
    /// The title of the item `path` resolves to, read-only: walking a menu
    /// never invokes anything. A step matches by prefix or substring, so this
    /// is what a press WOULD hit, and what the gate must classify.
    func menuTitle(path: [String], pid: Int32) -> String?
    /// Presses the item at `path` only if it still resolves to `expecting`
    /// (the title the gate classified); nil when a step did not match, the
    /// menu changed, or the press failed.
    func menu(path: [String], pid: Int32, expecting: String) -> String?
}
