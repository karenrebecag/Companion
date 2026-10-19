import ApplicationServices
import CompanionCore
import Foundation

/// One Accessibility read. `absent` is a leaf or an attribute the element
/// does not have; `failed` is a timeout or a dead element, which can hide a
/// secure field and so never reads as "none here".
enum AXAttempt<Value> {
    case value(Value)
    case absent
    case unsupported
    case failed
}

/// The reads the field walk needs, behind a seam so the walk runs in tests
/// with a fake tree. Production is `LiveSecureFieldTree`.
protocol SecureFieldTree {
    associatedtype Node
    func prime(_ pid: pid_t)
    func settle()
    func windows(_ pid: pid_t) -> AXAttempt<[Node]>
    func role(_ node: Node) -> AXAttempt<String>
    func subrole(_ node: Node) -> AXAttempt<String>
    func frame(_ node: Node) -> CGRect?
    func children(_ node: Node) -> AXAttempt<[Node]>
}

extension AXAttempt: Sendable where Value: Sendable {}

/// Chromium and Electron build their tree only after an assistive client
/// asks for it, and the first read of a fresh app comes back empty.
struct LiveSecureFieldTree: SecureFieldTree {
    typealias Node = AXUIElement

    /// Only Chromium-family apps take AXEnhancedUserInterface; setting it on
    /// every app would change how those apps animate, for no gain.
    let enhancedPIDs: Set<pid_t>
    /// Shared with `SecureFieldReader`: a freshly primed tree needs a moment.
    static let settleDelay: UInt32 = 300_000

    func prime(_ pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, SecureFieldReader.messagingTimeout)
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if enhancedPIDs.contains(pid) {
            AXUIElementSetAttributeValue(
                application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    func settle() {
        usleep(Self.settleDelay)
    }

    func windows(_ pid: pid_t) -> AXAttempt<[AXUIElement]> {
        Self.attempt(kAXWindowsAttribute, of: AXUIElementCreateApplication(pid)) { $0 as? [AXUIElement] }
    }

    func role(_ node: AXUIElement) -> AXAttempt<String> {
        Self.attempt(kAXRoleAttribute, of: node) { $0 as? String }
    }

    func subrole(_ node: AXUIElement) -> AXAttempt<String> {
        Self.attempt(kAXSubroleAttribute, of: node) { $0 as? String }
    }

    func frame(_ node: AXUIElement) -> CGRect? {
        AXRead.frame(of: node)
    }

    func children(_ node: AXUIElement) -> AXAttempt<[AXUIElement]> {
        Self.attempt(kAXChildrenAttribute, of: node) { $0 as? [AXUIElement] }
    }

    // The error code is the point: a timeout and a leaf both come back
    // without a value, and only the code tells them apart.
    private static func attempt<Value>(
        _ name: String, of element: AXUIElement, _ cast: (CFTypeRef) -> Value?
    ) -> AXAttempt<Value> {
        AXUIElementSetMessagingTimeout(element, SecureFieldReader.messagingTimeout)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success:
            guard let value, let typed = cast(value) else { return .failed }
            return .value(typed)
        case .noValue:
            return .absent
        case .attributeUnsupported:
            return .unsupported
        default:
            return .failed
        }
    }
}
