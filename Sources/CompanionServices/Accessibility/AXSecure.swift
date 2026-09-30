import ApplicationServices
import Foundation

/// A password field can show up two ways in the Accessibility tree: the
/// modern one is role `AXTextField` with subrole `AXSecureTextField`, and a
/// legacy one reports the role itself as `AXSecureTextField`. Checking only
/// `kAXRoleAttribute` (as the dictation and screen-reading code all did)
/// misses the modern shape entirely — a real `NSSecureTextField` never
/// matched (security review C1, 2026-09-25). Every caller routes through
/// this one check.
package enum AXSecure {
    static let marker = "AXSecureTextField"

    package static func isSecure(role: String, subrole: String) -> Bool {
        role == marker || subrole == marker
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        isSecure(role: attribute(kAXRoleAttribute, of: element),
                 subrole: attribute(kAXSubroleAttribute, of: element))
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }
}
