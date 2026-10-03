import Foundation

// Wave 16a. The parent's sight: the Accessibility tree of the window in
// front, flattened and numbered so the brain — which reads text, not
// pixels — can name what to press. Incredible's `scan` does the same.

/// One node of the walk, as the adapter read it. `label` is the element's
/// own name (title, description, placeholder); `value` is its content.
package struct ScanNode: Sendable, Equatable {
    package var role: String
    package var subrole: String
    package var label: String
    package var value: String?
    package var secure: Bool
    /// 0 = the window itself; each dialog, sheet or alert gets its own
    /// number, so a neutral "Sí" can be judged by what its dialog says.
    package var group: Int

    package init(
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
package struct ScreenWalk: Sendable, Equatable {
    package var nodes: [ScanNode]
    package var partial: Bool
    package var window: String
    package var generation: Int

    package init(nodes: [ScanNode], partial: Bool, window: String, generation: Int) {
        self.nodes = nodes
        self.partial = partial
        self.window = window
        self.generation = generation
    }
}

package struct ScreenElement: Sendable, Equatable {
    package var id: Int
    /// Index into the walk's nodes: what the adapter presses.
    package var node: Int
    package var kind: String
    package var label: String
    /// The text of the dialog this control sits in; empty in the window.
    package var context: String
}

package struct ScreenScan: Sendable, Equatable {
    /// Enough for a dialog, a form or a mail list; a full web page is cut
    /// and says so, as Incredible's scan does.
    package static let maxElements = 150
    package static let maxChars = 6_000
    static let maxLine = 200

    package var app: String
    package var window: String
    package var generation: Int
    package var elements: [ScreenElement]
    package var partial: Bool
    var lines: [String]

    package func element(id: Int) -> ScreenElement? {
        elements.first { $0.id == id }
    }

    package func render() -> String {
        var text = "window \"\(window)\" (\(app))"
        for line in lines { text += "\n" + line }
        if partial {
            text += "\n(partial: the window has more than this; scroll or ask about one part)"
        }
        return text
    }

    package static func build(_ walk: ScreenWalk, app: String) -> ScreenScan {
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

    package static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > maxLine ? String(flat.prefix(maxLine)) + "…" : flat
    }
}

/// Which Accessibility roles are something to press or fill, and the short
/// word the model reads for each.
package enum ScreenRoles {
    static let kinds: [String: String] = [
        "AXButton": "button", "AXLink": "link", "AXCheckBox": "checkbox",
        "AXRadioButton": "radio", "AXPopUpButton": "popup", "AXMenuButton": "menu button",
        "AXMenuItem": "menu item", "AXTextField": "field", "AXTextArea": "text area",
        "AXComboBox": "combo box", "AXSearchField": "search field", "AXTab": "tab",
        "AXDisclosureTriangle": "disclosure", "AXSlider": "slider", "AXIncrementor": "stepper",
    ]

    package static func kind(_ node: ScanNode) -> String? {
        if node.secure { return "password field" }
        return kinds[node.role]
    }

    package static func isControl(_ role: String) -> Bool {
        kinds[role] != nil
    }

    package static func isText(_ role: String) -> Bool {
        role == "AXStaticText" || role == "AXHeading"
    }

    /// Roles worth walking into for their children, and roles the walk reads.
    package static func isInteresting(_ role: String) -> Bool {
        kinds[role] != nil || isText(role)
    }

    /// Reading the children's roles ahead costs one AX call per child, so
    /// only a window pays it, once per walk.
    package static func readsChildRoles(of parentRole: String) -> Bool {
        parentRole == "AXWindow"
    }

    /// The order to walk children in: a window's toolbars first, everything
    /// else as AX gives it. The walk stops on time, and a long list walked
    /// first left Notes' toolbar ("Nueva nota") without an id.
    package static func childOrder(parentRole: String, childRoles: [String]) -> [Int] {
        guard readsChildRoles(of: parentRole) else { return Array(childRoles.indices) }
        let toolbars = childRoles.indices.filter { childRoles[$0] == "AXToolbar" }
        return toolbars + childRoles.indices.filter { childRoles[$0] != "AXToolbar" }
    }
}

// MARK: - Ports

package enum ScrollDirection: String, Sendable, Equatable, CaseIterable {
    case up, down, left, right
    /// Brings one control into the visible part of its scroll area; needs an id.
    case intoView = "into_view"
}

/// How a click landed, in Incredible's order: the element's own press
/// action, focusing it (a field), or a mouse click posted to the process.
package enum ClickRoute: String, Sendable, Equatable {
    case press, focus, mouse
}

package enum ClickOutcome: Sendable, Equatable {
    case clicked(ClickRoute)
    /// The walk that produced the id is no longer the latest.
    case stale
    /// The element refused every route, or it is a secure field.
    case refused
}

/// The window of one process, read and acted on through Accessibility. The
/// adapter keeps the element handles of its latest walk only.
package protocol ScreenActing: Sendable {
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
    /// False when the item `path` resolves to is greyed out: pressing it does
    /// nothing, and the model must be told instead of shown a success.
    func menuEnabled(path: [String], pid: Int32) -> Bool
}

extension ScreenActing {
    package func menuEnabled(path: [String], pid: Int32) -> Bool { true }
}
