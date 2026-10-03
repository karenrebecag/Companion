import CompanionCore
import Foundation

/// A screen of windows that moves like the AX adapter: a window with a
/// minimum size keeps it (the app refuses to shrink), a refused one throws,
/// a closed one is gone from the next read. One move can be held mid-flight
/// to test what overlaps it; only one, so a broken overlap check fails the
/// test instead of hanging it.
package final class FakeWindowArranger: WindowArranging, @unchecked Sendable {
    private let lock = NSLock()
    private var trusted: Bool
    private var screens: [DisplayInfo]
    private var current: [WindowInfo]
    private var minimums: [Int: (width: Int, height: Int)] = [:]
    /// Window id to how many moves it accepts before refusing.
    private var refusing: [Int: Int] = [:]
    private var accepted: [Int: Int] = [:]
    private var failingFullScreen: Set<Int> = []
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var movesLog: [(id: Int, frame: WindowRect)] = []
    private var raisedLog: [Int] = []
    private var fullScreenLog: [(id: Int, on: Bool)] = []

    package init(trusted: Bool = true, displays: [DisplayInfo], windows: [WindowInfo]) {
        self.trusted = trusted
        self.screens = displays
        self.current = windows
    }

    package var moves: [(id: Int, frame: WindowRect)] { lock.withLock { movesLog } }
    package var raised: [Int] { lock.withLock { raisedLog } }
    package var fullScreenCalls: [(id: Int, on: Bool)] { lock.withLock { fullScreenLog } }

    package func isFullScreen(_ id: Int) -> Bool? {
        lock.withLock { current.first { $0.id == id }?.fullscreen }
    }

    package func frame(of id: Int) -> WindowRect? {
        lock.withLock { current.first { $0.id == id }?.frame }
    }

    package func setTrusted(_ value: Bool) { lock.withLock { trusted = value } }

    package func setMinimum(_ id: Int, width: Int, height: Int) {
        lock.withLock { minimums[id] = (width, height) }
    }

    package func refuse(_ id: Int, afterMoves allowed: Int = 0) {
        lock.withLock { refusing[id] = (accepted[id] ?? 0) + allowed }
    }

    package func allowMoves(_ id: Int) { lock.withLock { refusing[id] = nil } }

    package func failFullScreen(_ id: Int) { lock.withLock { _ = failingFullScreen.insert(id) } }

    /// The user dragging a window by hand.
    package func setFrame(_ id: Int, _ frame: WindowRect) {
        lock.withLock {
            guard let index = current.firstIndex(where: { $0.id == id }) else { return }
            current[index].frame = frame
        }
    }

    package func window(_ id: Int) -> WindowInfo? { lock.withLock { current.first { $0.id == id } } }

    package func holdNextMove() { lock.withLock { holding = true } }

    package var heldMoves: Int { lock.withLock { held.count } }

    package func releaseMoves() {
        let waiting = lock.withLock {
            defer { held = [] }
            return held
        }
        for continuation in waiting { continuation.resume() }
    }

    package func close(_ id: Int) { lock.withLock { current.removeAll { $0.id == id } } }

    package func isTrusted() -> Bool { lock.withLock { trusted } }

    package func displays() async -> [DisplayInfo] { lock.withLock { screens } }

    package func windows() async -> [WindowInfo] { lock.withLock { current } }

    package func move(windowID: Int, to frame: WindowRect) async throws -> WindowRect {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now = lock.withLock {
                guard holding else { return true }
                holding = false
                held.append(continuation)
                return false
            }
            if now { continuation.resume() }
        }
        return try lock.withLock {
            guard let index = current.firstIndex(where: { $0.id == windowID }) else {
                throw ContractError.notFound("window \(windowID) is gone")
            }
            if let limit = refusing[windowID], (accepted[windowID] ?? 0) >= limit {
                throw ContractError(code: "move_refused", message: "the app refused the move")
            }
            accepted[windowID, default: 0] += 1
            movesLog.append((windowID, frame))
            let minimum = minimums[windowID] ?? (0, 0)
            let settled = WindowRect(
                x: frame.x, y: frame.y,
                width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
            current[index].frame = settled
            current[index].minimized = false
            current[index].fullscreen = false
            return settled
        }
    }

    package func setFullScreen(windowID: Int, on: Bool) async throws {
        try lock.withLock {
            guard let index = current.firstIndex(where: { $0.id == windowID }) else {
                throw ContractError.notFound("window \(windowID) is gone")
            }
            guard !failingFullScreen.contains(windowID) else {
                throw ContractError(code: "move_refused", message: "the window would not enter full screen")
            }
            fullScreenLog.append((windowID, on))
            current[index].fullscreen = on
        }
    }

    package func raise(windowID: Int) async {
        lock.withLock { raisedLog.append(windowID) }
    }
}

/// One 1512x982 laptop panel with a 33 px menu bar, numbered like AppKit's.
package enum WindowFixtures {
    package static let laptop = DisplayInfo(
        number: 1, name: "Built-in Display",
        frame: WindowRect(x: 0, y: 0, width: 1512, height: 982),
        workArea: WindowRect(x: 0, y: 33, width: 1512, height: 949))

    package static let external = DisplayInfo(
        number: 2, name: "External",
        frame: WindowRect(x: 1512, y: -298, width: 1920, height: 1080),
        workArea: WindowRect(x: 1512, y: -298, width: 1920, height: 1080))

    package static func window(
        _ id: Int, _ app: String, _ title: String = "",
        frame: WindowRect = WindowRect(x: 100, y: 100, width: 800, height: 600),
        minimized: Bool = false, fullscreen: Bool = false
    ) -> WindowInfo {
        WindowInfo(id: id, app: app, title: title, pid: Int32(1000 + id), frame: frame,
                   minimized: minimized, fullscreen: fullscreen)
    }
}
