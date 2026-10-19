import Foundation

// The breadth-first walk of one window's Accessibility tree, pure: the
// adapter supplies the tree, tests supply a fake one. Breadth-first is the
// point: a depth-first walk spent its budget inside the first long list
// (Notes' note list), so the toolbar after it never got an id.

/// The time and node budget one read may spend. Computah's read uses about
/// a third of a second and under a thousand nodes.
package struct ReadBudget: Sendable, Equatable {
    package static let standard = ReadBudget(time: .milliseconds(350), nodes: 900)

    package var time: Duration
    package var nodes: Int

    package init(time: Duration, nodes: Int) {
        self.time = time
        self.nodes = nodes
    }
}

/// What the adapter reads of an element's identity before deciding to keep it.
package struct ScreenKind: Sendable, Equatable {
    package var role: String
    package var subrole: String
    package var secure: Bool

    package init(role: String, subrole: String, secure: Bool) {
        self.role = role
        self.subrole = subrole
        self.secure = secure
    }
}

/// The attributes a kept element is read with; "" and nil mean not set.
package struct ScreenDetails: Sendable, Equatable {
    package var title: String
    package var description: String
    package var placeholder: String
    package var value: String
    package var enabled: Bool
    package var focused: Bool

    package init(
        title: String = "", description: String = "", placeholder: String = "",
        value: String = "", enabled: Bool = true, focused: Bool = false
    ) {
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.value = value
        self.enabled = enabled
        self.focused = focused
    }
}

/// The Accessibility tree as the walk sees it. `kind` is the cheap read every
/// visited element pays; `details` and `value` are paid only for what is kept
/// or used as a caption; `details` is never asked for a secure field's value.
package protocol ScreenTree {
    associatedtype Element
    func kind(of element: Element) -> ScreenKind
    func details(of element: Element, readValue: Bool) -> ScreenDetails
    func value(of element: Element) -> String
    func children(of element: Element) -> [Element]
}

/// `elements` runs parallel to `nodes`: the adapter presses by index.
package struct ScreenReadResult<Element> {
    package var nodes: [ScanNode]
    package var elements: [Element]
    package var partial: Bool
}

package struct ScreenWalker<Tree: ScreenTree> {
    /// How far below an unlabeled button or link its caption may sit.
    static var captionDepth: Int { 3 }

    let tree: Tree
    let budget: ReadBudget
    let elapsed: () -> Duration

    package init(tree: Tree, budget: ReadBudget, elapsed: @escaping () -> Duration) {
        self.tree = tree
        self.budget = budget
        self.elapsed = elapsed
    }

    /// The first root is the window (group 0); every further root is a dialog
    /// window of the app and gets a group of its own.
    package func walk(roots: [Tree.Element]) -> ScreenReadResult<Tree.Element> {
        var meter = Meter(budget: budget, elapsed: elapsed)
        var nodes: [ScanNode] = []
        var elements: [Tree.Element] = []
        var groups = 0
        var queue: [(element: Tree.Element, group: Int)] = []
        for (index, root) in roots.enumerated() {
            if index > 0 { groups += 1 }
            queue.append((root, index > 0 ? groups : 0))
        }
        var head = 0
        while head < queue.count {
            guard meter.allowsOneMore() else { break }
            let (element, inherited) = queue[head]
            head += 1
            let kind = tree.kind(of: element)
            var group = inherited
            if kind.role == ScreenRoles.sheetRole || ScreenRoles.dialogSubroles.contains(kind.subrole) {
                groups += 1
                group = groups
            }
            if kind.secure || ScreenRoles.isInteresting(kind.role) {
                nodes.append(node(element, kind: kind, group: group, meter: &meter))
                elements.append(element)
            }
            // A password field's children are glyphs; a control's children are
            // its own caption, already read into its label.
            guard !kind.secure, !ScreenRoles.isControl(kind.role) else { continue }
            for child in tree.children(of: element) {
                queue.append((child, group))
            }
        }
        return ScreenReadResult(nodes: nodes, elements: elements, partial: meter.cut)
    }

    /// The label as it is now, for the check right before a press.
    package func label(of element: Tree.Element) -> String {
        var meter = Meter(budget: budget, elapsed: elapsed)
        let kind = tree.kind(of: element)
        let details = tree.details(of: element, readValue: false)
        return ScreenRoles.label(
            title: details.title, description: details.description, placeholder: details.placeholder,
            role: kind.role, secure: kind.secure,
            caption: { caption(of: element, depth: Self.captionDepth, meter: &meter) })
    }

    private func node(
        _ element: Tree.Element, kind: ScreenKind, group: Int, meter: inout Meter
    ) -> ScanNode {
        let details = tree.details(of: element, readValue: !kind.secure)
        let label = ScreenRoles.label(
            title: details.title, description: details.description, placeholder: details.placeholder,
            role: kind.role, secure: kind.secure,
            caption: { caption(of: element, depth: Self.captionDepth, meter: &meter) })
        let value = kind.secure || details.value.isEmpty ? nil : details.value
        return ScanNode(
            role: kind.role, subrole: kind.subrole, label: label, value: value,
            secure: kind.secure, group: group, enabled: details.enabled, focused: details.focused)
    }

    /// The text an unlabeled control shows, from its children. Each child read
    /// spends the same budget as the walk: an icon with a deep subtree must not
    /// overrun it.
    private func caption(of element: Tree.Element, depth: Int, meter: inout Meter) -> String {
        guard depth > 0 else { return "" }
        for child in tree.children(of: element) {
            guard meter.allowsOneMore() else { return "" }
            let text = tree.value(of: child)
            if !text.isEmpty { return text }
            let inner = caption(of: child, depth: depth - 1, meter: &meter)
            if !inner.isEmpty { return inner }
        }
        return ""
    }
}

/// One spend per element visited or caption read, and a cut the first time
/// the budget is out. `cut` is set only when something was left unread.
private struct Meter {
    let budget: ReadBudget
    let elapsed: () -> Duration
    var spent = 0
    var cut = false

    mutating func allowsOneMore() -> Bool {
        if cut { return false }
        if spent >= budget.nodes || elapsed() >= budget.time {
            cut = true
            return false
        }
        spent += 1
        return true
    }
}
