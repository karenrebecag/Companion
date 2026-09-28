import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// Wave 16a: the parent's sight over Accessibility, the way Incredible's
/// `accessibility-helper` does it — walk the window, hand out ids, press by
/// id with the element's own action, then focus, then a mouse click posted
/// to the process. Keeps the handles of its latest walk only: an id from an
/// older walk is stale, never guessed.
public final class AXScreen: ScreenActing, @unchecked Sendable {
    /// A web page can have thousands of nodes; the walk stops on time or
    /// count and the scan says it is partial.
    static let budget: Duration = .milliseconds(600)
    static let maxVisited = 2_500
    static let maxCollected = 400
    static let messagingTimeout: Float = 0.25
    /// How far below an unlabeled button or link its caption may sit.
    static let captionDepth = 3
    static let dialogSubroles: Set<String> = ["AXDialog", "AXSystemDialog", "AXFloatingWindow"]
    /// Chromium browsers build their web tree only for a client that sets
    /// AXEnhancedUserInterface; Electron apps want AXManualAccessibility.
    /// Incredible's helper "primes" the same list before its first scan.
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
        "ai.perplexity.comet", "company.thebrowser.Browser", "org.chromium.Chromium", "com.vivaldi.Vivaldi",
    ]
    /// The tree a freshly primed app builds is not there on the same call.
    static let primeSettle: UInt32 = 300_000

    private let selfBundleID: String
    private let trust: @Sendable () -> Bool
    private let lock = NSLock()
    private var generation = 0
    private var handles: (pid: Int32, generation: Int, elements: [AXUIElement])?
    private var primed: Set<Int32> = []

    public init(selfBundleID: String, trust: @escaping @Sendable () -> Bool) {
        self.selfBundleID = selfBundleID
        self.trust = trust
    }

    /// Where the app's front window is, in AX's global top-left space: what
    /// the hands aura uses to pick a display. Nil without trust or a window.
    public func windowFrame(pid: Int32) -> CGRect? {
        guard trust() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application)
            ?? AXRead.element(kAXMainWindowAttribute, of: application)
            ?? AXRead.elements(kAXWindowsAttribute, of: application)?.first
        else { return nil }
        return AXRead.frame(of: window)
    }

    // MARK: - Walk

    public func walk(pid: Int32) -> ScreenWalk? {
        guard trust(), let app = actable(pid) else { return nil }
        // The clock starts before priming: the settle is part of the budget
        // the walk promises, not a hidden extra (code review 16, HIGH).
        var state = WalkState(deadline: ContinuousClock.now.advanced(by: Self.budget))
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        if prime(application, pid: pid, bundle: app.bundleIdentifier) { usleep(Self.primeSettle) }
        // An app in the background may report no focused or main window
        // (kAXErrorNoValue) while it still lists its windows.
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application)
            ?? AXRead.element(kAXMainWindowAttribute, of: application)
            ?? AXRead.elements(kAXWindowsAttribute, of: application)?.first
        else { return nil }
        visit(window, state: &state)
        // A permission prompt or a save dialog can be its own window.
        for other in AXRead.elements(kAXWindowsAttribute, of: application) ?? [] {
            guard !state.full() else { break }
            guard !CFEqual(other, window),
                  Self.dialogSubroles.contains(AXRead.string(kAXSubroleAttribute, of: other))
            else { continue }
            state.groups += 1
            state.group = state.groups
            visit(other, state: &state)
            state.group = 0
        }
        let next = lock.withLock { () -> Int in
            generation += 1
            handles = (pid, generation, state.elements)
            return generation
        }
        return ScreenWalk(
            nodes: state.nodes, partial: state.cut,
            window: AXRead.string(kAXTitleAttribute, of: window), generation: next)
    }

    private struct WalkState {
        let deadline: ContinuousClock.Instant
        var visited = 0
        /// The dialog being walked (0 = the window); see `ScanNode.group`.
        var group = 0
        var groups = 0
        var nodes: [ScanNode] = []
        var elements: [AXUIElement] = []
        var cut = false

        mutating func full() -> Bool {
            if visited >= AXScreen.maxVisited || nodes.count >= AXScreen.maxCollected
                || ContinuousClock.now >= deadline {
                cut = true
            }
            return cut
        }
    }

    private func visit(_ element: AXUIElement, state: inout WalkState) {
        guard !state.full() else { return }
        state.visited += 1
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let role = AXRead.string(kAXRoleAttribute, of: element)
        let subrole = AXRead.string(kAXSubroleAttribute, of: element)
        let secure = AXSecure.isSecure(role: role, subrole: subrole)
        // A sheet or alert inside the window is a dialog of its own.
        let outer = state.group
        if role == kAXSheetRole || Self.dialogSubroles.contains(subrole) {
            state.groups += 1
            state.group = state.groups
        }
        defer { state.group = outer }
        if secure || ScreenRoles.isInteresting(role) {
            state.nodes.append(node(element, role: role, subrole: subrole, secure: secure, state: &state))
            state.elements.append(element)
        }
        // A password field's children are glyphs; a control's children are
        // its own caption, already read into its label.
        guard !secure, !Self.isLeafControl(role) else { return }
        for child in AXRead.elements(kAXChildrenAttribute, of: element) ?? [] {
            guard !state.full() else { return }
            visit(child, state: &state)
        }
    }

    private static func isLeafControl(_ role: String) -> Bool {
        ScreenRoles.isControl(role)
    }

    private func node(
        _ element: AXUIElement, role: String, subrole: String, secure: Bool, state: inout WalkState
    ) -> ScanNode {
        let label = Self.label(
            title: AXRead.string(kAXTitleAttribute, of: element),
            description: AXRead.string(kAXDescriptionAttribute, of: element),
            placeholder: AXRead.string(kAXPlaceholderValueAttribute, of: element),
            role: role, secure: secure,
            caption: { caption(of: element, depth: Self.captionDepth, state: &state) })
        let value = secure ? nil : AXRead.string(kAXValueAttribute, of: element)
        return ScanNode(role: role, subrole: subrole, label: label,
                        value: value?.isEmpty == false ? value : nil, secure: secure,
                        group: state.group)
    }

    /// A control's own name, else the text its children show — never for a
    /// secure field, whose children are its characters (security review 16, C1).
    static func label(
        title: String, description: String, placeholder: String, role: String, secure: Bool,
        caption: () -> String
    ) -> String {
        if let own = [title, description, placeholder].first(where: { !$0.isEmpty }) { return own }
        guard !secure, ScreenRoles.isControl(role) else { return "" }
        return caption()
    }

    /// The label as it is now, for the check right before a press.
    private func liveLabel(_ element: AXUIElement) -> String {
        let role = AXRead.string(kAXRoleAttribute, of: element)
        let secure = AXSecure.isSecure(role: role, subrole: AXRead.string(kAXSubroleAttribute, of: element))
        var state = WalkState(deadline: ContinuousClock.now.advanced(by: .milliseconds(150)))
        return Self.label(
            title: AXRead.string(kAXTitleAttribute, of: element),
            description: AXRead.string(kAXDescriptionAttribute, of: element),
            placeholder: AXRead.string(kAXPlaceholderValueAttribute, of: element),
            role: role, secure: secure,
            caption: { caption(of: element, depth: Self.captionDepth, state: &state) })
    }

    /// The text an unlabeled web link or button shows, from its children.
    /// Every child read counts against the walk's own budget: an icon button
    /// with a deep SVG subtree must not blow the deadline (code review 16).
    private func caption(of element: AXUIElement, depth: Int, state: inout WalkState) -> String {
        guard depth > 0 else { return "" }
        for child in AXRead.elements(kAXChildrenAttribute, of: element) ?? [] {
            guard !state.full() else { return "" }
            state.visited += 1
            let text = AXRead.string(kAXValueAttribute, of: child)
            if !text.isEmpty { return text }
            let inner = caption(of: child, depth: depth - 1, state: &state)
            if !inner.isEmpty { return inner }
        }
        return ""
    }

    /// For the activation hook: prime the app that just came to the front.
    public func prime(pid: Int32, bundle: String?) {
        guard trust(), actable(pid) != nil else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        prime(application, pid: pid, bundle: bundle)
    }

    /// True the first time an app is primed: its tree needs a moment.
    /// Setting the flags on an app that ignores them is harmless.
    @discardableResult
    public func prime(_ application: AXUIElement, pid: Int32, bundle: String?) -> Bool {
        guard lock.withLock({ primed.insert(pid).inserted }) else { return false }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let bundle, Self.chromiumBrowsers.contains(bundle) {
            AXUIElementSetAttributeValue(
                application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        Log.app("sight: primed pid=\(pid) bundle=\(bundle ?? "-")")
        return true
    }

    // MARK: - Act

    private func handle(node: Int, generation: Int, pid: Int32) -> AXUIElement? {
        lock.withLock {
            guard let handles, handles.pid == pid, handles.generation == generation,
                  handles.elements.indices.contains(node)
            else { return nil }
            return handles.elements[node]
        }
    }

    public func click(node: Int, generation: Int, pid: Int32, label: String) -> ClickOutcome {
        guard trust(), actable(pid) != nil else { return .refused }
        guard let element = handle(node: node, generation: generation, pid: pid) else { return .stale }
        // The sheet approved a label; a page that swapped what sits behind
        // it since the look gets a fresh look, not a press (review 16, TOCTOU).
        guard ScreenScan.clip(liveLabel(element)) == label else { return .stale }
        let role = AXRead.string(kAXRoleAttribute, of: element)
        guard !AXSecure.isSecure(role: role, subrole: AXRead.string(kAXSubroleAttribute, of: element))
        else { return .refused }
        if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return .clicked(.press)
        }
        if AXScreen.editable(role),
           AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            return .clicked(.focus)
        }
        guard let frame = AXRead.frame(of: element), Self.mouseClick(at: frame.center, pid: pid) else {
            return .refused
        }
        return .clicked(.mouse)
    }

    static func editable(_ role: String) -> Bool {
        AXTextInjector.editableRoles.contains(role) || role == "AXSearchField"
    }

    /// Posted to the process, like `press`: it lands in that app even with
    /// Companion in front, and never moves the user's own pointer.
    private static func mouseClick(at point: CGPoint, pid: Int32) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left)
        else { return false }
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    public func scroll(node: Int?, generation: Int, direction: ScrollDirection, pid: Int32) -> Bool {
        guard trust(), actable(pid) != nil else { return false }
        let start = node.flatMap { handle(node: $0, generation: generation, pid: pid) }
        guard let area = start.flatMap(scrollArea(above:)) ?? firstScrollArea(pid: pid) else { return false }
        let action = direction == .down ? "AXScrollDownByPage" : "AXScrollUpByPage"
        if AXUIElementPerformAction(area, action as CFString) == .success { return true }
        guard let bar = AXRead.element(kAXVerticalScrollBarAttribute, of: area),
              let current = AXRead.number(kAXValueAttribute, of: bar)
        else { return false }
        let step = direction == .down ? 0.25 : -0.25
        let next = min(1, max(0, current + step)) as CFNumber
        return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, next) == .success
    }

    private func scrollArea(above element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let this = current else { return nil }
            if AXRead.string(kAXRoleAttribute, of: this) == kAXScrollAreaRole { return this }
            current = AXRead.element(kAXParentAttribute, of: this)
        }
        return nil
    }

    private func firstScrollArea(pid: Int32) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application) else { return nil }
        var queue = [window]
        var seen = 0
        let deadline = ContinuousClock.now.advanced(by: Self.budget)
        while !queue.isEmpty, seen < 300, ContinuousClock.now < deadline {
            let element = queue.removeFirst()
            seen += 1
            if AXRead.string(kAXRoleAttribute, of: element) == kAXScrollAreaRole { return element }
            queue += AXRead.elements(kAXChildrenAttribute, of: element) ?? []
        }
        return nil
    }

    public func menu(path: [String], pid: Int32) -> String? {
        guard trust(), actable(pid) != nil, !path.isEmpty else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard var level = AXRead.element(kAXMenuBarAttribute, of: application) else { return nil }
        for (index, step) in path.enumerated() {
            let items = AXRead.elements(kAXChildrenAttribute, of: level) ?? []
            let titles = items.map { AXRead.string(kAXTitleAttribute, of: $0) }
            guard let match = WindowTitles.bestMatch(titles, for: step) else { return nil }
            let item = items[match]
            if index == path.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                    ? titles[match] : nil
            }
            // A menu-bar item or a submenu item holds its menu as the only child.
            guard let submenu = AXRead.elements(kAXChildrenAttribute, of: item)?.first else { return nil }
            level = submenu
        }
        return nil
    }

    /// Alive, and not us: the one process the sight must never act on is
    /// the one running it.
    private func actable(_ pid: Int32) -> NSRunningApplication? {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier != selfBundleID
        else { return nil }
        return app
    }
}

/// Typed reads of one Accessibility attribute; empty or nil on any failure.
enum AXRead {
    static func string(_ name: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }

    static func number(_ name: String, of element: AXUIElement) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.doubleValue
    }

    static func element(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ name: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin: CGPoint = axValue(kAXPositionAttribute, of: element, type: .cgPoint),
              let size: CGSize = axValue(kAXSizeAttribute, of: element, type: .cgSize),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue<T>(_ name: String, of element: AXUIElement, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // The type id was checked above; CF types cannot be cast conditionally.
        let axValue = value as! AXValue
        return withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer -> T? in
            guard let base = buffer.baseAddress, AXValueGetValue(axValue, type, base) else { return nil }
            return base.pointee
        }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
