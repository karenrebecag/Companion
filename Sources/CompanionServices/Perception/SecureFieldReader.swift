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

    /// `shown` holds the pids that own a window on the captured display: an
    /// app with one on screen and an empty tree is an unbuilt tree, not an
    /// app with nothing to hide.
    package static func read(
        pids: [pid_t], shown: Set<pid_t>, enhancedPIDs: Set<pid_t> = []
    ) -> SecureFieldMask.Read {
        read(pids: pids, shown: shown, tree: LiveSecureFieldTree(enhancedPIDs: enhancedPIDs))
    }

    static func read<Tree: SecureFieldTree>(
        pids: [pid_t], shown: Set<pid_t>, tree: Tree
    ) -> SecureFieldMask.Read {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var frames: [CGRect] = []
        for pid in pids {
            let freshlyPrimed = tree.prime(pid)
            guard let windows = windowList(
                of: pid, shown: shown.contains(pid), freshlyPrimed: freshlyPrimed, tree: tree
            ) else {
                return .incomplete("no accessibility tree for an app with windows on screen")
            }
            var walk = Walk(tree: tree, clock: clock, deadline: deadline)
            for window in windows { walk.visit(window) }
            if let reason = walk.incomplete { return .incomplete(reason) }
            frames += walk.frames
        }
        return .fields(frames)
    }

    /// A freshly primed Chromium or Electron app can answer with a partial
    /// tree, even one that already has a window, so it is read again after a
    /// settle. An empty tree is re-read the same way; one still empty with a
    /// window on screen is withheld. Nil means the read must be withheld.
    private static func windowList<Tree: SecureFieldTree>(
        of pid: pid_t, shown: Bool, freshlyPrimed: Bool, tree: Tree
    ) -> [Tree.Node]? {
        guard var list = windows(of: pid, tree: tree) else { return nil }
        if freshlyPrimed || (list.isEmpty && shown) {
            tree.settle()
            guard let again = windows(of: pid, tree: tree) else { return nil }
            list = again
        }
        if list.isEmpty && shown { return nil }
        return list
    }

    private static func windows<Tree: SecureFieldTree>(
        of pid: pid_t, tree: Tree
    ) -> [Tree.Node]? {
        switch tree.windows(pid) {
        case .value(let found): return found
        case .absent, .unsupported: return []
        case .failed: return nil
        }
    }

    private struct Walk<Tree: SecureFieldTree> {
        let tree: Tree
        let clock: ContinuousClock
        let deadline: ContinuousClock.Instant
        var nodes = 0
        var frames: [CGRect] = []
        var incomplete: String?

        mutating func visit(_ node: Tree.Node) {
            guard incomplete == nil else { return }
            guard nodes < SecureFieldReader.maxNodes, clock.now < deadline else {
                incomplete = "accessibility walk over budget"
                return
            }
            nodes += 1
            guard case .value(let role) = tree.role(node) else {
                incomplete = "element role unreadable"
                return
            }
            // A subrole read that times out must not pass as "no subrole": that
            // is how a password field with a timed-out read slipped through.
            let subrole: String
            switch tree.subrole(node) {
            case .value(let read): subrole = read
            case .absent, .unsupported: subrole = ""
            case .failed:
                incomplete = "subrole unreadable"
                return
            }
            if AXSecure.isSecure(role: role, subrole: subrole) {
                // A secure field's children are its glyphs: nothing below it
                // is needed, and nothing below it may be read.
                guard let frame = tree.frame(node) else {
                    incomplete = "secure field frame unreadable"
                    return
                }
                frames.append(frame)
                return
            }
            switch tree.children(node) {
            case .value(let children):
                for child in children {
                    visit(child)
                    if incomplete != nil { return }
                }
            case .absent, .unsupported:
                // No children attribute is a leaf, not a failed read.
                return
            case .failed:
                incomplete = "children unreadable"
            }
        }
    }
}
