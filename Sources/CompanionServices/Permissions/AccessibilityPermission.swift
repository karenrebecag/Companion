import ApplicationServices
import CompanionCore
import Foundation

/// The only permission Wave 10a introduces. Probed at launch and on every
/// sense, shown in Settings; the system prompt fires only when the user
/// flips the toggle. It appears ONCE per app and signing identity — after a
/// deny, `AXIsProcessTrustedWithOptions` returns false with no UI, which is
/// why the Settings row always offers the deep link too (BUILD-LEDGER P5).
package struct AccessibilityPermission: AccessibilityChecking {
    package init() {}

    package func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    package func request() -> Bool {
        // The framework's constant is an unsafe global under Swift 6; its
        // documented value is the string below.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
