import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// The parent's hands (Wave 15g) over the same Accessibility adapter as
/// dictation, keyed to a pid instead of to whatever is in front: the user
/// talks to Companion, so Companion may be in front while it acts on the
/// app they were in. Never our own process, never a password field. Logs
/// carry pids and counts, never text.
extension AXTextInjector: FocusedReading, KeyPressing, WindowRaising {
    package func focusedField(pid: Int32) -> FocusedField? {
        guard trust(), let app = actable(pid), let element = focusedElement(of: pid) else {
            return nil
        }
        let name = app.localizedName ?? app.bundleIdentifier ?? "app"
        if AXSecure.isSecure(element) { return FocusedField(app: name, pid: pid, secure: true) }
        let role = self.role(of: element)
        guard Self.editableRoles.contains(role) || isSettable(kAXValueAttribute, element) else {
            return nil
        }
        return FocusedField(app: name, pid: pid)
    }

    /// The value first; an element that exposes none (some web fields) may
    /// still answer with its selection.
    package func read(pid: Int32) -> String? {
        guard trust(), actable(pid) != nil, let element = focusedElement(of: pid),
              !AXSecure.isSecure(element)
        else { return nil }
        for attribute in [kAXValueAttribute, kAXSelectedTextAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let text = value as? String, !text.isEmpty
            else { continue }
            return FocusedText.clip(text, caret: Self.caret(of: element))
        }
        return nil
    }

    /// Where the insertion point is, as a UTF-16 offset; nil when the field
    /// does not say.
    private static func caret(of element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        // The type id was checked above; CF types cannot be cast conditionally.
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location
    }

    /// Posted to the process, not to the HID stream: it lands in that app
    /// even with Companion in front. A private event source and cleared
    /// flags, so a modifier the user is holding (the FN hold) never turns
    /// Return into a shortcut.
    package func press(_ key: NamedKey, pid: Int32) -> Bool {
        guard trust(), actable(pid) != nil,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCode(key), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCode(key), keyDown: false)
        else { return false }
        down.flags = []
        up.flags = []
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    package func raise(titleContaining title: String, pid: Int32) -> String? {
        guard trust(), let app = actable(pid) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return nil }
        let titles = windows.map(windowTitle)
        guard let index = WindowTitles.match(titles, containing: title) else {
            Log.app("hands: no window matched among \(titles.count) pid=\(pid)")
            return nil
        }
        let status = AXUIElementPerformAction(windows[index], kAXRaiseAction as CFString)
        guard status == .success else {
            Log.app("hands: raise failed status=\(status.rawValue) pid=\(pid)")
            return nil
        }
        // Raising orders the window inside its app; activating brings the
        // app itself above Companion.
        app.activate()
        return titles[index]
    }

    package static func bundleID(of pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// ANSI virtual key codes (HIToolbox Events.h); layout-independent for
    /// these eight, which is why the list stops here.
    static func keyCode(_ key: NamedKey) -> CGKeyCode {
        switch key {
        case .return: 36
        case .tab: 48
        case .escape: 53
        case .backspace: 51
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        }
    }

    /// Alive, and not us by pid or by bundle id: the one process the hands
    /// must never touch is the one running them.
    private func actable(_ pid: Int32) -> NSRunningApplication? {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              app.bundleIdentifier != selfBundleID
        else { return nil }
        return app
    }

    private func windowTitle(_ window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }
}
