import ApplicationServices
import CompanionCore
import Foundation

/// The boxes of the secure fields in the windows of the apps a frame shows,
/// read from the same Accessibility tree the app already walks for its text.
/// Only the secure boxes leave the walk; a read that cannot finish is
/// reported as incomplete, never as an empty list.
package enum SecureFieldReader {
    static let messagingTimeout: Float = 0.25
    /// The whole read spends this long at most, across every app in the frame.
    static let budget: Duration = .seconds(1)
    // HACK: a window past this many nodes is withheld, not partly masked.
    // Upgrade to a role-filtered search when large web pages show up in the
    // "frame withheld" log often.
    static let maxNodes = 2_000

    package static func read(pids: [pid_t]) -> SecureFieldMask.Read {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var frames: [CGRect] = []
        for pid in pids {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, messagingTimeout)
            guard let windows = AXRead.elements(kAXWindowsAttribute, of: application) else {
                return .incomplete("window list unreadable")
            }
            var walk = Walk(clock: clock, deadline: deadline)
            for window in windows { walk.visit(window) }
            if let reason = walk.incomplete { return .incomplete(reason) }
            frames += walk.frames
        }
        return .fields(frames)
    }

    private struct Walk {
        let clock: ContinuousClock
        let deadline: ContinuousClock.Instant
        var nodes = 0
        var frames: [CGRect] = []
        var incomplete: String?

        mutating func visit(_ element: AXUIElement) {
            guard incomplete == nil else { return }
            guard nodes < SecureFieldReader.maxNodes, clock.now < deadline else {
                incomplete = "accessibility walk over budget"
                return
            }
            nodes += 1
            AXUIElementSetMessagingTimeout(element, SecureFieldReader.messagingTimeout)
            let (roleValue, roleError) = Self.copy(kAXRoleAttribute, of: element)
            guard roleError == .success, let role = roleValue as? String else {
                incomplete = "element role unreadable"
                return
            }
            let subrole = AXRead.string(kAXSubroleAttribute, of: element)
            if AXSecure.isSecure(role: role, subrole: subrole) {
                // A secure field's children are its glyphs: nothing below it
                // is needed, and nothing below it may be read.
                guard let frame = AXRead.frame(of: element) else {
                    incomplete = "secure field frame unreadable"
                    return
                }
                frames.append(frame)
                return
            }
            let (childValue, childError) = Self.copy(kAXChildrenAttribute, of: element)
            switch childError {
            case .success:
                guard let children = childValue as? [AXUIElement] else {
                    incomplete = "children unreadable"
                    return
                }
                for child in children {
                    visit(child)
                    if incomplete != nil { return }
                }
            case .noValue:
                return
            default:
                incomplete = "children unreadable"
            }
        }

        // The error code is the point: a timeout and a leaf both come back
        // without a value, and only the code tells a leaf from a failed read.
        private static func copy(_ name: String, of element: AXUIElement) -> (CFTypeRef?, AXError) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return (value, error)
        }
    }
}
