import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// The screen through public APIs only: AppKit for displays and apps,
/// CoreGraphics for the front-to-back order, Accessibility for every frame
/// read and write. Facts it relies on (measured by Incredible on macOS 15):
/// - Chromium and Electron run with AXEnhancedUserInterface on, which makes
///   a frame write animate and land off target; it is switched off around
///   the write and put back.
/// - Size, then position, then size: macOS refuses a position that would
///   push a still-oversized window off its display.
/// - A full-screen window refuses a position write until it leaves full
///   screen, which takes about two seconds.
/// - Electron keeps its Accessibility tree off until a client asks through
///   AXManualAccessibility.
/// Stage Manager and other Spaces are out of scope here: only windows
/// Accessibility can reach on the visible Spaces are listed.
package actor AXWindowArranger: WindowArranging {
    private static let messagingTimeout: Float = 1
    /// Smaller than this is a palette or a sliver, not a window to arrange.
    private static let minimumSide = 50.0
    private static let pollInterval: Duration = .milliseconds(100)

    private let trust: @Sendable () -> Bool
    /// Ids are minted here and kept while the element lives: Accessibility
    /// has no public window number, and undo has to find the same window.
    private var known: [(id: Int, pid: pid_t, element: AXUIElement)] = []
    private var nextID = 1
    private var manualAccessibilityAsked: Set<pid_t> = []

    package init(trust: @escaping @Sendable () -> Bool) {
        self.trust = trust
    }

    package nonisolated func isTrusted() -> Bool { trust() }

    package func displays() async -> [DisplayInfo] {
        await MainActor.run {
            DisplayInfo.fromAppKit(NSScreen.screens.map { screen in
                DisplayInfo.AppKitScreen(
                    name: screen.localizedName,
                    frame: Self.appKit(screen.frame), visibleFrame: Self.appKit(screen.visibleFrame))
            })
        }
    }

    package func windows() async -> [WindowInfo] {
        let painted = Self.frontToBackPIDs()
        let rank = Dictionary(painted.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .enumerated()
            .sorted { (rank[$0.element.processIdentifier] ?? Int.max, $0.offset)
                < (rank[$1.element.processIdentifier] ?? Int.max, $1.offset) }
            .map(\.element)
        var seen: [(id: Int, pid: pid_t, element: AXUIElement)] = []
        var result: [WindowInfo] = []
        for app in apps {
            let pid = app.processIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)"
            let hidden = app.isHidden
            for element in await standardWindows(pid: pid, painted: rank[pid] != nil) {
                guard let frame = AXRead.frame(of: element),
                      frame.width >= Self.minimumSide, frame.height >= Self.minimumSide
                else { continue }
                let id = identity(of: element, pid: pid)
                seen.append((id, pid, element))
                result.append(WindowInfo(
                    id: id, app: name, title: AXRead.string(kAXTitleAttribute, of: element), pid: pid,
                    frame: Self.rect(frame),
                    minimized: Self.flag(kAXMinimizedAttribute, of: element),
                    fullscreen: Self.flag(Self.fullScreenAttribute, of: element),
                    appHidden: hidden))
            }
        }
        known = seen
        return result
    }

    package func move(windowID: Int, to frame: WindowRect) async throws -> WindowRect {
        guard let entry = known.first(where: { $0.id == windowID }) else {
            throw ContractError.notFound("that window is gone; read the inventory again")
        }
        let element = entry.element
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        try await prepare(element)
        let app = AXUIElementCreateApplication(entry.pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        let enhanced = Self.flag(Self.enhancedUIAttribute, of: app)
        if enhanced { Self.setFlag(Self.enhancedUIAttribute, false, on: app, pid: entry.pid) }
        defer {
            if enhanced { Self.setFlag(Self.enhancedUIAttribute, true, on: app, pid: entry.pid) }
        }
        let status = Self.write(frame, to: element, pid: entry.pid)
        guard status == .success else {
            Log.app("windows: position refused pid=\(entry.pid) axerror=\(status.rawValue)")
            throw ContractError(
                code: "move_refused",
                message: "the app refused the move (AXError \(status.rawValue)); the window may be fixed in place")
        }
        return AXRead.frame(of: element).map(Self.rect) ?? frame
    }

    package func setFullScreen(windowID: Int, on: Bool) async throws {
        guard let entry = known.first(where: { $0.id == windowID }) else {
            throw ContractError.notFound("that window is gone; read the inventory again")
        }
        AXUIElementSetMessagingTimeout(entry.element, Self.messagingTimeout)
        guard Self.flag(Self.fullScreenAttribute, of: entry.element) != on else { return }
        try await fullScreen(on, entry.element)
    }

    package func raise(windowID: Int) async {
        guard let entry = known.first(where: { $0.id == windowID }) else { return }
        let status = AXUIElementPerformAction(entry.element, kAXRaiseAction as CFString)
        if status != .success { Log.app("windows: raise refused pid=\(entry.pid) axerror=\(status.rawValue)") }
        if NSRunningApplication(processIdentifier: entry.pid)?.activate() != true {
            Log.app("windows: could not activate pid=\(entry.pid)")
        }
    }

    // MARK: - Reads

    private func standardWindows(pid: pid_t, painted: Bool) async -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        var list = AXRead.elements(kAXWindowsAttribute, of: app) ?? []
        // Painted windows that Accessibility does not list: an Electron app
        // with its tree still off. Asked once per process.
        if list.isEmpty, painted, !manualAccessibilityAsked.contains(pid) {
            manualAccessibilityAsked.insert(pid)
            if Self.setFlag(Self.manualAccessibilityAttribute, true, on: app, pid: pid) {
                _ = await wait(seconds: 1) { !(AXRead.elements(kAXWindowsAttribute, of: app) ?? []).isEmpty }
                list = AXRead.elements(kAXWindowsAttribute, of: app) ?? []
            }
        }
        return list.filter { AXRead.string(kAXSubroleAttribute, of: $0) == kAXStandardWindowSubrole }
    }

    private func identity(of element: AXUIElement, pid: pid_t) -> Int {
        if let match = known.first(where: { $0.pid == pid && CFEqual($0.element, element) }) {
            return match.id
        }
        defer { nextID += 1 }
        return nextID
    }

    /// Owners of on-screen, normal-layer windows, frontmost first. Owner
    /// pids need no Screen Recording grant; window names would.
    private static func frontToBackPIDs() -> [pid_t] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            Log.app("windows: the window server list was unavailable")
            return []
        }
        var order: [pid_t] = []
        for entry in info where (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  !order.contains(pid) else { continue }
            order.append(pid)
        }
        return order
    }

    // MARK: - Writes

    /// Full screen first, since it also refuses the un-minimize; each step
    /// waits for the window to settle before the frame is written.
    private func prepare(_ element: AXUIElement) async throws {
        if Self.flag(Self.fullScreenAttribute, of: element) {
            try await fullScreen(false, element)
        }
        if Self.flag(kAXMinimizedAttribute, of: element) {
            let status = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            if status != .success { Log.app("windows: un-minimize refused axerror=\(status.rawValue)") }
            _ = await wait(seconds: 2) { !Self.flag(kAXMinimizedAttribute, of: element) }
        }
    }

    /// The change takes about two seconds; the frame lands a moment after
    /// the flag flips, and only then can a frame be written.
    private func fullScreen(_ on: Bool, _ element: AXUIElement) async throws {
        let before = AXRead.frame(of: element)
        let status = AXUIElementSetAttributeValue(
            element, Self.fullScreenAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
        guard status == .success else {
            throw ContractError(
                code: "move_refused",
                message: "the window would not \(on ? "enter" : "leave") full screen (AXError \(status.rawValue))")
        }
        guard await wait(seconds: 4, until: { Self.flag(Self.fullScreenAttribute, of: element) == on }) else {
            Log.app("windows: full screen did not flip to \(on) within 4 s")
            throw ContractError(
                code: "move_refused", message: "the window did not \(on ? "enter" : "leave") full screen in time")
        }
        _ = await wait(seconds: 1) { AXRead.frame(of: element) != before }
    }

    private static func write(_ frame: WindowRect, to element: AXUIElement, pid: pid_t) -> AXError {
        var size = CGSize(width: frame.width, height: frame.height)
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin)
        else { return .failure }
        let first = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let position = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        let last = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        if first != .success || last != .success {
            Log.app("windows: size write refused pid=\(pid) axerror=\(first.rawValue),\(last.rawValue)")
        }
        return position
    }

    /// True when the write took. A failure is logged here, so callers that
    /// can go on without it need not check.
    @discardableResult
    private static func setFlag(_ name: String, _ value: Bool, on element: AXUIElement, pid: pid_t) -> Bool {
        let status = AXUIElementSetAttributeValue(
            element, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
        if status != .success { Log.app("windows: \(name) write refused pid=\(pid) axerror=\(status.rawValue)") }
        return status == .success
    }

    /// Polls `done` until it holds or the time runs out; false on timeout.
    private func wait(seconds: Double, until done: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            if done() { return true }
            do {
                try await Task.sleep(for: Self.pollInterval)
            } catch {
                return done()
            }
        }
        return done()
    }

    // MARK: - Values

    private static let fullScreenAttribute = "AXFullScreen"
    private static let enhancedUIAttribute = "AXEnhancedUserInterface"
    private static let manualAccessibilityAttribute = "AXManualAccessibility"

    private static func flag(_ name: String, of element: AXUIElement) -> Bool {
        (AXRead.number(name, of: element) ?? 0) != 0
    }

    private static func rect(_ frame: CGRect) -> WindowRect {
        WindowRect(
            x: Int(frame.origin.x.rounded()), y: Int(frame.origin.y.rounded()),
            width: Int(frame.width.rounded()), height: Int(frame.height.rounded()))
    }

    private static func appKit(_ frame: CGRect) -> DisplayInfo.AppKitRect {
        DisplayInfo.AppKitRect(
            x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
    }
}
