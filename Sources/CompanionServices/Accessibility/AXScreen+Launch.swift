import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// open_app's eyes on a launch: the process the name became, and whether it
/// shows a window yet.
extension AXScreen: AppWindowProbing {
    package func pid(ofApp name: String) -> Int32? {
        NSWorkspace.shared.runningApplications
            .first { app in
                guard !app.isTerminated, app.activationPolicy == .regular else { return false }
                // The opener names apps by file name; the running app may
                // carry a localized display name that differs from it.
                return app.localizedName == name
                    || app.bundleURL?.deletingPathExtension().lastPathComponent == name
            }?
            .processIdentifier
    }

    package func hasWindow(pid: Int32) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        return !(AXRead.elements(kAXWindowsAttribute, of: application) ?? []).isEmpty
    }
}
