import ApplicationServices
import CompanionCore
import Foundation

/// Wave 15b-6: the AX tree of the focused window, read for its visible
/// text — the same method Incredible measures (spec 13a §1: screen-text/
/// macos, 378-442 ms). Roles that carry prose: static text, text areas,
/// non-secure text fields, and heading titles. Never `AXSecureTextField` —
/// the same promise dictation already makes (12e, `AXTextInjector`).
public struct AXScreenText: Sendable {
    static let textRoles: Set<String> = [kAXStaticTextRole, kAXTextAreaRole, kAXTextFieldRole]
    static let headingRole = kAXHeadingRole
    /// A busy app (a live-updating table, an IDE) can have thousands of
    /// static-text children; the walk must not pay for all of them (spec
    /// 15b §9 "AX lento en apps pesadas").
    public static let maxNodes = 300
    public static let maxChars = 600
    /// A single Accessibility round trip to a busy app must not hold the
    /// walk hostage — same bound as dictation's own probe.
    static let messagingTimeout: Float = 0.25
    public static let budget: Duration = .milliseconds(450)

    private let trusted: @Sendable () -> Bool
    private let selfPID: pid_t?

    public init(
        trusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        selfPID: pid_t? = ProcessInfo.processInfo.processIdentifier
    ) {
        self.trusted = trusted
        self.selfPID = selfPID
    }

    /// Raw strings only — `ScreenTextSnippets` (Core, pure) caps, dedupes
    /// and tags them. Empty without AX trust, without a real pid, or on
    /// Companion's own process: reading our own window is not "the screen"
    /// (spec 15b §8).
    public func harvest(pid: pid_t) -> [String] {
        guard trusted(), pid > 0, pid != selfPID else { return [] }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = focusedWindow(of: application) else { return [] }
        var texts: [String] = []
        var chars = 0
        var visited = 0
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.budget)
        walk(window, texts: &texts, chars: &chars, visited: &visited, clock: clock, deadline: deadline)
        return texts
    }

    private func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        attributeElement(kAXFocusedWindowAttribute, of: application)
    }

    private func walk(
        _ element: AXUIElement, texts: inout [String], chars: inout Int, visited: inout Int,
        clock: ContinuousClock, deadline: ContinuousClock.Instant
    ) {
        guard visited < Self.maxNodes, chars < Self.maxChars, clock.now < deadline else { return }
        visited += 1
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let role = attribute(kAXRoleAttribute, of: element)
        // Never descend into a password field either — its children are
        // obfuscated glyphs, not readable text.
        guard !AXSecure.isSecure(role: role, subrole: attribute(kAXSubroleAttribute, of: element))
        else { return }
        if Self.textRoles.contains(role) {
            append(attribute(kAXValueAttribute, of: element), to: &texts, chars: &chars)
        } else if role == Self.headingRole {
            append(attribute(kAXTitleAttribute, of: element), to: &texts, chars: &chars)
        }
        guard let children = attributeElements(kAXChildrenAttribute, of: element) else { return }
        for child in children {
            guard visited < Self.maxNodes, chars < Self.maxChars, clock.now < deadline else { return }
            walk(child, texts: &texts, chars: &chars, visited: &visited, clock: clock, deadline: deadline)
        }
    }

    private func append(_ text: String, to texts: inout [String], chars: inout Int) {
        guard !text.isEmpty else { return }
        texts.append(text)
        chars += text.count
    }

    private func attribute(_ name: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }

    private func attributeElement(_ name: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func attributeElements(_ name: String, of element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return nil }
        return children
    }
}
