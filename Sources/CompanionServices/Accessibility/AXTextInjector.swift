import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// The probe and the hands of dictation (Wave 12e), both over the
/// Accessibility API of the app in front. Never the password field, never
/// an app other than the one probed at press, never keystrokes letter by
/// letter (they lose accents and are slow): the selected text attribute
/// first, the pasteboard and one Command-V when the app ignores it.
package final class AXTextInjector: FocusedFieldProbing, TextInjecting, @unchecked Sendable {
    let selfBundleID: String
    let trust: @Sendable () -> Bool
    static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
    ]
    /// How long the pasted text stays on the pasteboard before the previous
    /// contents come back: the target has to have read it by then.
    static let pasteSettle: UInt64 = 300_000_000
    /// A single Accessibility call is a round trip to the app in front. A
    /// busy one (a beachballing Electron window) would otherwise hold the
    /// voice actor for the default timeout and freeze the hold, so every
    /// call is bounded (security and code reviews 2026-09-06).
    static let messagingTimeout: Float = 0.25

    /// Without our own bundle id there is no way to exclude our window from
    /// the targets, and dictating into Companion is exactly what must never
    /// happen: refuse to exist instead of failing open (security review).
    package init?(
        selfBundleID: String,
        trust: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }
    ) {
        let id = selfBundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }
        self.selfBundleID = id
        self.trust = trust
    }

    package func isTrusted() -> Bool { trust() }

    package func focusedField() -> FocusedField? {
        guard let app = front(), let element = focusedElement(of: app.pid) else { return nil }
        if AXSecure.isSecure(element) {
            return FocusedField(app: app.name, pid: app.pid, secure: true)
        }
        let role = self.role(of: element)
        guard Self.editableRoles.contains(role) || isSettable(kAXValueAttribute, element) else {
            return nil
        }
        return FocusedField(app: app.name, pid: app.pid)
    }

    package func inject(_ text: String, into field: FocusedField) async -> InjectionResult {
        guard trust() else { return .failed(.needsAccessibility) }
        guard let app = front(), app.pid == field.pid,
              let element = focusedElement(of: field.pid)
        else { return .failed(.fieldGone) }
        guard !AXSecure.isSecure(element) else { return .failed(.refused) }
        let status = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if status == .success { return .injected(text.count, via: .ax) }
        return await paste(text, pid: field.pid)
    }

    package func paste(_ text: String, into field: FocusedField) async -> InjectionResult {
        guard trust() else { return .failed(.needsAccessibility) }
        guard let app = front(), app.pid == field.pid,
              let element = focusedElement(of: field.pid)
        else { return .failed(.fieldGone) }
        guard !AXSecure.isSecure(element) else { return .failed(.refused) }
        return await paste(text, pid: field.pid)
    }

    // MARK: - Reading the app in front

    private struct Front {
        let name: String
        let pid: pid_t
    }

    /// Companion in front is never a target: its own field takes typing.
    private func front() -> Front? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != selfBundleID
        else { return nil }
        return Front(
            name: app.localizedName ?? app.bundleIdentifier ?? "app",
            pid: app.processIdentifier)
    }

    func focusedElement(of pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &value) == .success,
            let value
        else { return nil }
        // The focused element comes back as a CFTypeRef; a type check on a
        // Core Foundation bridge is the one way to tell it is an element.
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func role(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }

    func isSettable(_ attribute: String, _ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    // MARK: - The pasteboard road

    /// Whatever was on the pasteboard comes back, every type of it: a
    /// dictation must not eat the image the user was about to paste.
    private func paste(_ text: String, pid: pid_t) async -> InjectionResult {
        let board = NSPasteboard.general
        let saved = Self.snapshot(board)
        board.clearContents()
        board.setString(text, forType: .string)
        let mine = board.changeCount
        guard Self.postCommandV(pid: pid) else {
            _ = Self.restore(saved, to: board, ifUnchangedFrom: mine)
            return .failed(.refused)
        }
        do {
            try await Task.sleep(nanoseconds: Self.pasteSettle)
        } catch {
            // Cancelled mid-paste: the pasteboard still goes back to its owner.
        }
        if !Self.restore(saved, to: board, ifUnchangedFrom: mine) {
            Log.app("dictation: the clipboard changed meanwhile; leaving it alone")
        }
        return .injected(text.count, via: .paste)
    }

    static func snapshot(_ board: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (board.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { entry[type] = data }
            }
            return entry
        }
    }

    /// False when someone else wrote to the pasteboard while the dictated
    /// text sat there: restoring blindly would eat what they just copied
    /// (security review 2026-09-06).
    @discardableResult
    static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]], to board: NSPasteboard,
        ifUnchangedFrom expected: Int
    ) -> Bool {
        guard board.changeCount == expected else { return false }
        board.clearContents()
        let items = saved.map { entry in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { board.writeObjects(items) }
        return true
    }

    /// Command-V to the field's process, the way `press` sends Return.
    /// Posted at the HID tap it also reached Companion's own hold-key tap and
    /// could cut the hold that was dictating (review 2026-09-25, L3); a
    /// private source keeps a held modifier out of it. Posting needs
    /// Accessibility, which `inject` checked first.
    private static func postCommandV(pid: pid_t) -> Bool {
        let keyV: CGKeyCode = 9
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}
