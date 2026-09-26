import AppKit
import ApplicationServices
import CompanionCore
import Foundation

/// Wave 16o-3: every 100 ms from press to commit, the Accessibility element
/// under the cursor. In memory only; `stop` hands it to the turn and forgets.
/// Samples arrive on a private queue: an AX call on a busy app can block.
public final class PointerSampler: @unchecked Sendable {
    public static let interval: TimeInterval = 0.1
    private let probe: @Sendable (CGPoint) -> PointedElement?
    private let location: @Sendable () -> CGPoint
    private let ownsPoint: @Sendable (CGPoint) -> Bool
    private let now: @Sendable () -> TimeInterval
    private let ticks: Bool
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "companion.pointer", qos: .userInitiated)
    private var startedAt: TimeInterval?
    private var samples: [PointedElement] = []
    private var timer: DispatchSourceTimer?

    public init(
        probe: @escaping @Sendable (CGPoint) -> PointedElement? = AXPointerProbe.element(at:),
        location: @escaping @Sendable () -> CGPoint = AXPointerProbe.cursor,
        ownsPoint: @escaping @Sendable (CGPoint) -> Bool = AXPointerProbe.ownWindowCovers,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        ticks: Bool = true
    ) {
        self.probe = probe
        self.location = location
        self.ownsPoint = ownsPoint
        self.now = now
        self.ticks = ticks
    }

    public func start() {
        lock.withLock {
            timer?.cancel()
            startedAt = now()
            samples = []
            guard ticks else { timer = nil; return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: Self.interval)
            source.setEventHandler { [weak self] in self?.sample() }
            timer = source
            source.resume()
        }
    }

    /// One reading, kept only if it is a new referent (collapsed as it goes,
    /// so a long hold never grows the buffer past `PointerTrace.maxItems`).
    public func sample() {
        guard let started = lock.withLock({ startedAt }) else { return }
        let point = location()
        // Over our own window the AX hit test is answered in-process, on this
        // queue, and runs SwiftUI off the main actor (crash 2026-09-26).
        guard !ownsPoint(point), var element = probe(point) else { return }
        element.at = now() - started
        lock.withLock {
            guard startedAt == started else { return }
            samples = PointerTrace.collapse(samples + [element])
        }
    }

    public func stop() -> [PointedElement] {
        lock.withLock {
            timer?.cancel()
            timer = nil
            startedAt = nil
            defer { samples = [] }
            return samples
        }
    }
}

public enum AXPointerProbe {
    /// Longest wait for one app's answer: past it the sample is skipped.
    static let messagingTimeout: Float = 0.05
    static let maxText = 120

    /// Global coordinates, origin top-left, as Accessibility wants them.
    public static func cursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// Whether one of Companion's own clickable windows is under the point.
    /// Deadlock-free only while nothing on main ever waits on the sampler's
    /// private queue: keep it that way.
    /// Click-through windows (the glow, the resting island) are skipped: the
    /// window server skips them too when it hit-tests. A window of ours hidden
    /// behind another app's reads as covering, which only skips a sample.
    public static func ownWindowCovers(_ point: CGPoint) -> Bool {
        let check: @Sendable () -> Bool = {
            MainActor.assumeIsolated {
                // Accessibility's origin is the primary screen's top-left.
                let height = NSScreen.screens.first?.frame.height ?? 0
                let flipped = CGPoint(x: point.x, y: height - point.y)
                // No NSApplication (a test process): there are no windows of ours.
                guard let app = NSApp else { return false }
                return app.windows.contains {
                    $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(flipped)
                }
            }
        }
        return Thread.isMainThread ? check() : DispatchQueue.main.sync(execute: check)
    }

    public static func element(at point: CGPoint) -> PointedElement? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        // Our own overlays and island are not what the user means.
        guard pid != getpid() else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? ""
        let names = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
        let text = names.lazy.map { string($0, of: hit) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        return PointedElement(app: app, role: string(kAXRoleAttribute, of: hit),
                              text: String(text.prefix(maxText)), at: 0)
    }

    private static func string(_ name: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
