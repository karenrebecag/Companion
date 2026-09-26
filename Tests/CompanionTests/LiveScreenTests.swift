import AppKit
import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 16a: the real walk against real apps, read-only (no click). Runs only
// with COMPANION_LIVE_AX=1 in a shell that has Accessibility; it measures,
// it does not gate.
@Test func liveScreenWalk() {
    guard ProcessInfo.processInfo.environment["COMPANION_LIVE_AX"] == "1" else { return }
    print("live: trusted=\(AXIsProcessTrusted())")
    let screen = AXScreen(selfBundleID: "com.karen.companion", trust: { AXIsProcessTrusted() })
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    for app in apps {
        let bundle = app.bundleIdentifier ?? "?"
        let clock = ContinuousClock()
        let start = clock.now
        let walk = screen.walk(pid: app.processIdentifier)
        let took = clock.now - start
        guard let walk else { print("live: \(bundle) no window"); continue }
        let scan = ScreenScan.build(walk, app: app.localizedName ?? bundle)
        print("live: \(bundle) \(took) nodes=\(walk.nodes.count) elements=\(scan.elements.count) "
            + "partial=\(scan.partial) chars=\(scan.render().count)")
        print(scan.render().split(separator: "\n").prefix(12).joined(separator: "\n"))
    }
}
