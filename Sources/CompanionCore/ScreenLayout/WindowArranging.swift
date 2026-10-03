import Foundation

/// The screen as the arranger needs it. Frames are global, top-left origin;
/// windows come front to back, so the first match is the one the user sees.
package protocol WindowArranging: Sendable {
    func isTrusted() -> Bool
    /// The main display first, numbered from 1.
    func displays() async -> [DisplayInfo]
    func windows() async -> [WindowInfo]
    /// Writes the frame (leaving full screen or un-minimizing first when it
    /// must) and returns the frame the app actually accepted.
    func move(windowID: Int, to frame: WindowRect) async throws -> WindowRect
    /// macOS's own full screen, waiting until the window reports the change.
    func setFullScreen(windowID: Int, on: Bool) async throws
    func raise(windowID: Int) async
}

/// The frames from before the last real arrange. Held by the runner, never
/// sent to the model: a frame list echoed back through a tool argument is a
/// frame list the model can rewrite. Synchronous on purpose: the approval
/// check reads it before deciding whether undo needs a sheet. It stays after
/// an undo: undoing again finds everything in place and moves nothing, and
/// the next real arrange replaces it.
package final class ArrangeUndoStore: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: [WindowInfo]?

    package init() {}

    package var hasSnapshot: Bool { lock.withLock { snapshot != nil } }

    package func save(_ windows: [WindowInfo]) { lock.withLock { snapshot = windows } }

    package func current() -> [WindowInfo]? { lock.withLock { snapshot } }
}

/// One moving call at a time. A second arrange or undo while one is still
/// writing frames is refused, not queued: two interleaved arranges would
/// fight over the same windows and the snapshot would capture a half-done
/// layout. Reads and dry runs never take it.
private final class MovingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false

    func enter() -> Bool {
        lock.withLock {
            guard !running else { return false }
            running = true
            return true
        }
    }

    func leave() { lock.withLock { running = false } }
}

/// inventory, list_layouts, arrange and undo over the port, as text the
/// model reads.
package struct WindowArrangeEngine: Sendable {
    private let arranging: any WindowArranging
    private let undo: ArrangeUndoStore
    private let gate = MovingGate()

    package init(arranging: any WindowArranging, undo: ArrangeUndoStore) {
        self.arranging = arranging
        self.undo = undo
    }

    package func run(_ call: ArrangeWindowsCall) async -> Result<String, ContractError> {
        guard call == .listLayouts || arranging.isTrusted() else {
            return .failure(WindowArrangement.permission)
        }
        if call.needsApproval {
            guard gate.enter() else { return .failure(WindowArrangement.busy) }
        }
        defer { if call.needsApproval { gate.leave() } }
        switch call {
        case .listLayouts:
            return .success(WindowLayouts.listing)
        case .inventory:
            let displays = await arranging.displays()
            return .success(WindowArrangement.inventory(displays: displays, windows: await arranging.windows()))
        case .arrange(let request):
            return await arrange(request)
        case .undo:
            return await restore()
        }
    }

    private func arrange(_ request: ArrangeRequest) async -> Result<String, ContractError> {
        let displays = await arranging.displays()
        let display: DisplayInfo
        switch WindowArrangement.display(request.screen, in: displays) {
        case .success(let found): display = found
        case .failure(let error): return .failure(error)
        }
        let windows = await arranging.windows()
        var arrangement = WindowArrangement.plan(request, display: display, displays: displays, windows: windows)
        guard !request.dryRun else { return .success(arrangement.report) }
        // Every frame first, one raise at the end: raising is what animates
        // and steals focus, so it happens once.
        for index in arrangement.placed.indices {
            let placement = arrangement.placed[index]
            do {
                let placed = try await place(placement.window.id, at: placement.requested, displays: displays)
                arrangement.placed[index].actual = placed.frame
                arrangement.placed[index].clampFailure = placed.clampFailure
            } catch {
                arrangement.placed[index].failure = Self.reason(error)
            }
        }
        guard let first = arrangement.placed.first(where: { $0.failure == nil }) else {
            return .failure(WindowArrangement.nothingMoved(arrangement.report))
        }
        // Only an arrange that moved something replaces the snapshot, with the
        // frames read before it: a failed one must not take away the undo of
        // the last one that worked.
        undo.save(windows)
        await arranging.raise(windowID: first.window.id)
        return .success(arrangement.report)
    }

    private func restore() async -> Result<String, ContractError> {
        guard let snapshot = undo.current() else { return .failure(WindowArrangement.nothingToUndo) }
        let displays = await arranging.displays()
        let plan = WindowArrangement.restore(snapshot: snapshot, live: await arranging.windows())
        var moved = 0
        var failed: [(WindowInfo, String)] = []
        var unclamped: [(WindowInfo, String)] = []
        for (window, frame) in plan.moves {
            do {
                let placed = try await place(window.id, at: frame, displays: displays)
                moved += 1
                if let reason = placed.clampFailure { unclamped.append((window, reason)) }
            } catch {
                failed.append((window, Self.reason(error)))
            }
        }
        for window in plan.fullScreen {
            do {
                try await arranging.setFullScreen(windowID: window.id, on: true)
                moved += 1
            } catch {
                failed.append((window, Self.reason(error)))
            }
        }
        let report = WindowArrangement.restoreReport(
            moved: moved, failed: failed, unclamped: unclamped, closed: plan.closed,
            allClosed: !snapshot.isEmpty && plan.closed.count == snapshot.count)
        guard moved > 0 || failed.isEmpty else { return .failure(WindowArrangement.nothingMoved(report)) }
        return .success(report)
    }

    /// An app with a minimum size keeps it and can end up hanging off the
    /// display; it is pulled back inside the work area, size unchanged. Only
    /// the first write failing means the window did not move: a refused
    /// clamp leaves it moved, and undo must still be able to bring it back.
    private func place(
        _ id: Int, at frame: WindowRect, displays: [DisplayInfo]
    ) async throws -> (frame: WindowRect, clampFailure: String?) {
        let actual = try await arranging.move(windowID: id, to: frame)
        let inside = actual.clamped(into: DisplayInfo.workArea(containing: frame, in: displays))
        guard inside != actual else { return (actual, nil) }
        do {
            return (try await arranging.move(windowID: id, to: inside), nil)
        } catch {
            return (actual, Self.reason(error))
        }
    }

    private static func reason(_ error: any Error) -> String {
        (error as? ContractError)?.message ?? String(describing: error)
    }
}
