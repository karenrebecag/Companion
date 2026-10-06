import Darwin
import Foundation

/// One window of one process, compared by AX identity (`CFEqual`). The
/// Accessibility element is the only thing that makes two windows of the
/// same app distinct; titles change, positions change, and a shell can
/// rewrite its own title under you.
package struct HandsWindow: @unchecked Sendable, Equatable {
    /// Box: the AXUIElement is a CoreFoundation reference, not a Swift
    /// type. `CFEqual` already does the right thing on it.
    private let ref: AnyObject

    package init(_ ref: AnyObject) { self.ref = ref }

    package static func == (lhs: HandsWindow, rhs: HandsWindow) -> Bool {
        CFEqual(lhs.ref, rhs.ref)
    }
}

/// The front window of an app, as the hands compare it. A port of its own so
/// the production factory can be proved against a fake: a factory that drops
/// this wiring silently turns every window check into "no window, nothing to
/// compare".
package protocol FrontWindowReading: Sendable {
    func frontWindow(pid: Int32) -> HandsWindow?
}

/// The app the user was in when they spoke (review 2026-09-25, HIGH-1),
/// and the window inside it that `look` or `focus_window` saw, so a
/// switched window of the same app is never typed into silently. The model can take
/// seconds; if the user switched apps or windows meanwhile, typing into
/// whatever is in front now would land somewhere nobody asked for.
final class TurnTarget: @unchecked Sendable {
    /// The fields the runner reads together. A snapshot is a copy taken
    /// under the lock; the caller cannot see a torn read where pid matched
    /// but window did not (or vice versa).
    struct Snapshot: Sendable {
        var pid: Int32?
        var window: HandsWindow?
        var bundle: String?
        var repin: Bool
    }

    private let lock = NSLock()
    private var state = Snapshot(pid: nil, window: nil, bundle: nil, repin: false)

    func begin(_ pid: Int32?) {
        lock.withLock { state = Snapshot(pid: pid, window: nil, bundle: nil, repin: false) }
    }

    /// One atomic read of every field that describes the pin, so a pin that
    /// flips pid between two locks cannot pass a precondition half-checked.
    func snapshot() -> Snapshot { lock.withLock { state } }

    var pinnedBundle: String? { lock.withLock { state.bundle } }

    /// An open the user asked for moved the front on purpose; the app is
    /// only frontmost a moment later, so the next hands call pins it — and
    /// anything after that is held to it (security review 16, H1).
    func release() {
        lock.withLock { state = Snapshot(pid: nil, window: nil, bundle: nil, repin: true) }
    }

    /// Takes the pending repin: the first call after an open pins whatever
    /// is in front. The window is only written by `latch` (from `look` and
    /// `focus_window`), so a repin always starts without one.
    func pin(for observed: Int32) -> Int32? {
        lock.withLock {
            if state.repin {
                state = Snapshot(pid: observed, window: nil, bundle: nil, repin: false)
            }
            return state.pid
        }
    }

    /// The single write path for pid + window + bundle: every field that
    /// describes a pin changes together or not at all. A look that has no
    /// window must NOT drop an existing latch for the same pid (so the
    /// caller passes nil and the same-pid branch keeps the prior window),
    /// but a pid change clears the previous latch entirely so the old app
    /// cannot bleed into the new one.
    func latch(window: HandsWindow?, pid: Int32, bundle: String?) {
        lock.withLock {
            if pid != state.pid {
                state = Snapshot(pid: pid, window: window, bundle: bundle, repin: false)
            } else if window != nil {
                state.window = window
                state.bundle = bundle
            }
        }
    }
}

/// The bridge's caller for a call: the shim's pid and the lineage above
/// it. Voice and chat never set it (they have no MCP shim), so
/// `callers.contains(front)` is false for them and the runner falls back to
/// `pin(for:)`. Set with `HandsCaller.$apps.withValue(...)` so a TaskLocal
/// wraps the resolution without leaking into the next call.
package enum HandsCaller {
    /// The pids the bridge treats as the same caller as the front app: a
    /// terminal the shim launched is still on this side of the door.
    @TaskLocal package static var apps: Set<Int32> = []

    /// Walks `ppid` from `pid` up to a process whose parent is itself (or
    /// pid 1, or whose parent we cannot read). 32 steps is more than enough
    /// for any shim and bounds a cycle. A partial chain only shrinks the
    /// set, so it can refuse a real caller but never admit a stranger.
    package static func lineage(of pid: Int32?) -> Set<Int32> {
        lineage(of: pid, parent: parent(of:))
    }

    /// The parent lookup is a parameter so the bounds (a cycle, a chain
    /// longer than the cap, an unreadable middle step) can be exercised
    /// without building real process trees.
    static func lineage(of pid: Int32?, parent: (Int32) -> Int32?) -> Set<Int32> {
        guard let pid, pid > 0 else { return [] }
        var collected: Set<Int32> = []
        var current = pid
        for _ in 0..<maxDepth {
            // An unreadable step ends the walk without admitting that pid.
            guard let ppid = parent(current) else { return collected }
            collected.insert(current)
            if ppid <= 1 || ppid == current { return collected }
            current = ppid
        }
        return collected
    }

    static let maxDepth = 32

    private static func parent(of pid: pid_t) -> pid_t? {
        // Read the kinfo_proc straight from sysctl; no [CChar] rebind, no
        // force unwrap. `size` is the real stride of the struct, the call
        // returns the bytes the kernel actually wrote, and the ppid comes
        // out of the struct that was filled in.
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            sysctl(&mib, u_int(mib.count), ptr, &size, nil, 0)
        }
        guard result == 0, size >= MemoryLayout<kinfo_proc>.stride else { return nil }
        return info.kp_eproc.e_ppid
    }
}
