import Foundation

/// What open_app needs to know about a launch it asked for: which process
/// it became, and whether that process has a window yet. A fresh app is
/// "open" long before it can be typed into.
package protocol AppWindowProbing: Sendable {
    func pid(ofApp name: String) -> Int32?
    func hasWindow(pid: Int32) -> Bool
}

/// How long open_app waits for the window. Ten seconds covers a cold launch
/// of a heavy app without holding a spoken turn for the half minute a slow
/// one can take.
package struct WindowWait: Sendable, Equatable {
    package let timeout: TimeInterval
    package let poll: TimeInterval

    package init(timeout: TimeInterval, poll: TimeInterval) {
        self.timeout = timeout
        self.poll = poll
    }

    package static let standard = WindowWait(timeout: 10, poll: 0.1)

    /// Polls `ready` until it holds or the timeout passes; a cancelled turn
    /// stops waiting. The pid it was ready for, or nil.
    package func wait(_ ready: @Sendable () -> Int32?) async -> Int32? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while !Task.isCancelled {
            if let pid = ready() { return pid }
            guard clock.now < deadline else { return nil }
            do {
                try await Task.sleep(for: .seconds(poll))
            } catch {
                return nil
            }
        }
        return nil
    }
}
