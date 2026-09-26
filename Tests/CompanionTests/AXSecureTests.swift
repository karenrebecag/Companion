import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Security review C1 (2026-09-25): a real NSSecureTextField reports role
// AXTextField with subrole AXSecureTextField — the subrole carries the
// signal, not the role. Comparing only kAXRoleAttribute (as AXTextInjector,
// AXTextInjectorHands and AXScreenText all did) never matches it.

@Test func axSecureTests() {
    expect(
        AXSecure.isSecure(role: "AXTextField", subrole: "AXSecureTextField"),
        "secure: modern shape is role=AXTextField + subrole=AXSecureTextField")
    expect(
        !AXSecure.isSecure(role: "AXTextField", subrole: ""),
        "secure: a plain text field is not secure")
    expect(
        AXSecure.isSecure(role: "AXSecureTextField", subrole: ""),
        "secure: legacy role AXSecureTextField is still honored")
}
