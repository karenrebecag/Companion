@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// A test target with its own resources would get a synthesized Bundle.module
// that shadows CompanionUI's. Tests that read .lproj through Bundle.module
// (Island16m4Tests) rely on it staying CompanionUI's bundle.
@Test func bundleModuleResolvesToTheUIResourceBundle() {
    let bundle = Bundle.module
    expectEq(bundle.bundleURL.lastPathComponent, "Companion_CompanionUI.bundle",
             "Bundle.module is CompanionUI's resource bundle")
    expect(bundle.path(forResource: "es", ofType: "lproj") != nil,
           "es.lproj does not resolve in \(bundle.bundleURL.path)")
}
