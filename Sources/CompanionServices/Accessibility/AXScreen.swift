import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// Wave 16a: the parent's sight over Accessibility, the way Incredible's
/// `accessibility-helper` does it — walk the window, hand out ids, press by
/// id with the element's own action, then focus, then a mouse click posted
/// to the process. Keeps the handles of its latest walk only: an id from an
/// older walk is stale, never guessed.
package final class AXScreen: ScreenActing, FrontWindowReading, @unchecked Sendable {
    /// A web page can have thousands of nodes; the walk stops on its budget
    /// and the scan says it is partial.
    static let messagingTimeout: Float = 0.25
    /// Chromium browsers build their web tree only for a client that sets
    /// AXEnhancedUserInterface; Electron apps want AXManualAccessibility.
    /// Incredible's helper "primes" the same list before its first scan.
    /// The Chrome/Edge channels ship the same engine as their stable
    /// counterparts, so they get the same priming and the same refusal
    /// when the user has not connected them.
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.brave.Browser", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.operasoftware.Opera",
        "ai.perplexity.comet", "company.thebrowser.Browser",
        "org.chromium.Chromium", "com.vivaldi.Vivaldi",
    ]
    /// The tree a freshly primed app builds is not there on the same call.
    static let primeSettle: UInt32 = 300_000

    private let selfBundleID: String
    private let trust: @Sendable () -> Bool
    private let lock = NSLock()
    private var generation = 0
    private var handles: (pid: Int32, generation: Int, elements: [AXUIElement])?
    private var primed: Set<Int32> = []

    package init(selfBundleID: String, trust: @escaping @Sendable () -> Bool) {
        self.selfBundleID = selfBundleID
        self.trust = trust
    }

    /// Where the app's front window is, in AX's global top-left space: what
    /// the hands aura uses to pick a display. Nil without trust or a window.
    package func windowFrame(pid: Int32) -> CGRect? {
        guard trust() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application)
            ?? AXRead.element(kAXMainWindowAttribute, of: application)
            ?? AXRead.elements(kAXWindowsAttribute, of: application)?.first
        else { return nil }
        return AXRead.frame(of: window)
    }

    /// The window `look` would return, wrapped so the runner can compare it
    /// across reads. Same focused -> main -> first order the walk uses.
    /// Nil without trust or a window; a missing window is itself the signal
    /// the runner needs to refuse the call.
    package func frontWindow(pid: Int32) -> HandsWindow? {
        guard trust() else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application)
            ?? AXRead.element(kAXMainWindowAttribute, of: application)
            ?? AXRead.elements(kAXWindowsAttribute, of: application)?.first
        else { return nil }
        return HandsWindow(window)
    }

    // MARK: - Walk

    package func walk(pid: Int32) -> ScreenWalk? {
        guard trust(), let app = actable(pid) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        // The settle is a wait for the app to build its tree, not a read, so it
        // stays outside the budget the walk promises.
        if prime(application, pid: pid, bundle: app.bundleIdentifier) { usleep(Self.primeSettle) }
        // An app in the background may report no focused or main window
        // (kAXErrorNoValue) while it still lists its windows.
        guard let window = AXRead.element(kAXFocusedWindowAttribute, of: application)
            ?? AXRead.element(kAXMainWindowAttribute, of: application)
            ?? AXRead.elements(kAXWindowsAttribute, of: application)?.first
        else { return nil }
        // A permission prompt or a save dialog can be its own window.
        let dialogs = (AXRead.elements(kAXWindowsAttribute, of: application) ?? []).filter { other in
            !CFEqual(other, window)
                && ScreenRoles.dialogSubroles.contains(AXRead.string(kAXSubroleAttribute, of: other))
        }
        let result = Self.walker(budget: .standard).walk(roots: [window] + dialogs)
        let next = lock.withLock { () -> Int in
            generation += 1
            handles = (pid, generation, result.elements)
            return generation
        }
        return ScreenWalk(
            nodes: result.nodes, partial: result.partial,
            window: AXRead.string(kAXTitleAttribute, of: window), generation: next)
    }

    /// The window as the verifier and the control chooser read it.
    package func snapshot(pid: Int32) -> ScreenSnapshot? {
        walk(pid: pid).map(ScreenSnapshot.init(walk:))
    }

    private static func walker(budget: ReadBudget) -> ScreenWalker<LiveAXTree> {
        let start = ContinuousClock.now
        return ScreenWalker(tree: LiveAXTree(), budget: budget, elapsed: { start.duration(to: ContinuousClock.now) })
    }

    /// The label as it is now, for the check right before a press.
    private func liveLabel(_ element: AXUIElement) -> String {
        Self.walker(budget: ReadBudget(time: .milliseconds(150), nodes: 60)).label(of: element)
    }

    /// For the activation hook: prime the app that just came to the front.
    package func prime(pid: Int32, bundle: String?) {
        guard trust(), actable(pid) != nil else { return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        prime(application, pid: pid, bundle: bundle)
    }

    /// True the first time an app is primed: its tree needs a moment.
    /// Setting the flags on an app that ignores them is harmless.
    @discardableResult
    package func prime(_ application: AXUIElement, pid: Int32, bundle: String?) -> Bool {
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

    package func click(node: Int, generation: Int, pid: Int32, label: String) -> ClickOutcome {
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

    package func scroll(node: Int?, generation: Int, direction: ScrollDirection, pid: Int32) -> Bool {
        guard trust(), actable(pid) != nil else { return false }
        let start = node.flatMap { handle(node: $0, generation: generation, pid: pid) }
        if direction == .intoView {
            // The control itself, not its scroll area: that is the one the
            // action brings into view.
            guard let target = start else { return false }
            return AXUIElementPerformAction(target, "AXScrollToVisible" as CFString) == .success
        }
        guard let area = start.flatMap(scrollArea(above:)) ?? firstScrollArea(pid: pid) else { return false }
        if AXUIElementPerformAction(area, Self.pageAction(direction) as CFString) == .success { return true }
        let horizontal = direction == .left || direction == .right
        guard let bar = AXRead.element(
                horizontal ? kAXHorizontalScrollBarAttribute : kAXVerticalScrollBarAttribute, of: area),
              let current = AXRead.number(kAXValueAttribute, of: bar)
        else { return false }
        let step = direction == .down || direction == .right ? 0.25 : -0.25
        let next = min(1, max(0, current + step)) as CFNumber
        return AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, next) == .success
    }

    static func pageAction(_ direction: ScrollDirection) -> String {
        switch direction {
        case .up: "AXScrollUpByPage"
        case .down: "AXScrollDownByPage"
        case .left: "AXScrollLeftByPage"
        case .right: "AXScrollRightByPage"
        case .intoView: "AXScrollToVisible"
        }
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
        let deadline = ContinuousClock.now.advanced(by: ReadBudget.standard.time)
        while !queue.isEmpty, seen < 300, ContinuousClock.now < deadline {
            let element = queue.removeFirst()
            seen += 1
            if AXRead.string(kAXRoleAttribute, of: element) == kAXScrollAreaRole { return element }
            queue += AXRead.elements(kAXChildrenAttribute, of: element) ?? []
        }
        return nil
    }

    package func menuTitle(path: [String], pid: Int32) -> String? {
        resolveMenu(path: path, pid: pid)?.title
    }

    package func menuEnabled(path: [String], pid: Int32) -> Bool {
        guard let target = resolveMenu(path: path, pid: pid) else { return true }
        return Self.enabled(target.item)
    }

    /// An item that does not say it is disabled is enabled: only an explicit
    /// false blocks the press.
    private static func enabled(_ item: AXUIElement) -> Bool {
        isEnabled(AXRead.number(kAXEnabledAttribute, of: item))
    }

    static func isEnabled(_ attribute: Double?) -> Bool { attribute != 0 }

    package func menu(path: [String], pid: Int32, expecting: String) -> String? {
        // Resolved again at press time: the menu may have changed since the
        // gate classified `expecting`, and only that title was approved.
        guard let target = resolveMenu(path: path, pid: pid), target.title == expecting,
              Self.enabled(target.item),
              AXUIElementPerformAction(target.item, kAXPressAction as CFString) == .success
        else { return nil }
        return target.title
    }

    /// Walks the path without invoking anything; only the final press acts.
    private func resolveMenu(path: [String], pid: Int32) -> (item: AXUIElement, title: String)? {
        guard trust(), actable(pid) != nil, !path.isEmpty else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard var level = AXRead.element(kAXMenuBarAttribute, of: application) else { return nil }
        for (index, step) in path.enumerated() {
            let items = AXRead.elements(kAXChildrenAttribute, of: level) ?? []
            let titles = items.map { AXRead.string(kAXTitleAttribute, of: $0) }
            guard let match = WindowTitles.bestMatch(titles, for: step) else { return nil }
            let item = items[match]
            if index == path.count - 1 { return (item, titles[match]) }
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

/// The live tree behind the walker. Every child it hands out gets the
/// messaging timeout, so one hung element cannot stall a walk.
struct LiveAXTree: ScreenTree {
    func kind(of element: AXUIElement) -> ScreenKind {
        let role = AXRead.string(kAXRoleAttribute, of: element)
        let subrole = AXRead.string(kAXSubroleAttribute, of: element)
        return ScreenKind(role: role, subrole: subrole, secure: AXSecure.isSecure(role: role, subrole: subrole))
    }

    func details(of element: AXUIElement, readValue: Bool) -> ScreenDetails {
        ScreenDetails(
            title: AXRead.string(kAXTitleAttribute, of: element),
            description: AXRead.string(kAXDescriptionAttribute, of: element),
            placeholder: AXRead.string(kAXPlaceholderValueAttribute, of: element),
            value: readValue ? AXRead.string(kAXValueAttribute, of: element) : "",
            enabled: AXScreen.isEnabled(AXRead.number(kAXEnabledAttribute, of: element)),
            focused: AXRead.number(kAXFocusedAttribute, of: element) == 1)
    }

    func value(of element: AXUIElement) -> String {
        AXRead.string(kAXValueAttribute, of: element)
    }

    func children(of element: AXUIElement) -> [AXUIElement] {
        let children = AXRead.elements(kAXChildrenAttribute, of: element) ?? []
        for child in children { AXUIElementSetMessagingTimeout(child, AXScreen.messagingTimeout) }
        return children
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
