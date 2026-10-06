import CompanionCore
import CompanionTestKit
import Foundation

package final class FakeMicWatch: MicDeviceWatch, @unchecked Sendable {
    private let end: @Sendable () -> Void
    package init(_ end: @escaping @Sendable () -> Void) { self.end = end }
    package func cancel() { end() }
}

package final class FakeMicPort: MicDevicePort, @unchecked Sendable {
    private let snapshotBox: LockedBox<MicDeviceSnapshot>
    private let watchers = LockedBox<[UUID: @Sendable (MicDeviceSnapshot) -> Void]>([:])

    package init(_ snapshot: MicDeviceSnapshot) {
        snapshotBox = LockedBox(snapshot)
    }

    package var watcherCount: Int { watchers.value.count }

    package func snapshot() -> MicDeviceSnapshot { snapshotBox.value }

    package func watch(
        _ onChange: @escaping @Sendable (MicDeviceSnapshot) -> Void
    ) -> any MicDeviceWatch {
        let id = UUID()
        watchers.value[id] = onChange
        return FakeMicWatch { [watchers] in watchers.value[id] = nil }
    }

    package func publish(_ snapshot: MicDeviceSnapshot) {
        snapshotBox.value = snapshot
        for watcher in watchers.value.values { watcher(snapshot) }
    }
}

/// Starts can be held so a test decides which of two overlapping probes
/// finishes first.
package final class FakeMicMeter: MicMeter, @unchecked Sendable {
    private let handler = LockedBox<(@Sendable (Double) -> Void)?>(nil)
    private let startLog = LockedBox<[MicTarget]>([])
    private let stopCount = LockedBox(0)
    private let faults = LockedBox<[MicProbeFault?]>([])
    private let released = LockedBox<Set<Int>>([])
    private let holding: Bool

    package init(holdStarts: Bool = false, authorized: Bool = true) {
        holding = holdStarts
        microphoneAuthorized = authorized
    }

    package let microphoneAuthorized: Bool

    package var starts: [MicTarget] { startLog.value }
    package var stops: Int { stopCount.value }

    /// Faults are consumed in order, one per start; no entry means success.
    package func script(_ fault: MicProbeFault?) { faults.value.append(fault) }

    /// Lets the held start at `index` (0-based) return.
    package func release(_ index: Int) { released.value.insert(index) }

    package func emit(_ level: Double) { handler.value?(level) }

    package func onLevel(_ handler: @escaping @Sendable (Double) -> Void) {
        self.handler.value = handler
    }

    package func start(target: MicTarget) async -> MicProbeFault? {
        let index = startLog.withLock { log -> Int in
            log.append(target)
            return log.count - 1
        }
        let fault = faults.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        while holding, !released.value.contains(index) { await Task.yield() }
        return fault
    }

    package func stop() { stopCount.value += 1 }
}

package final class SpyMicStore: MicPreferenceStoring, @unchecked Sendable {
    private let current: LockedBox<MicPreference>
    private let saved = LockedBox<[MicPreference]>([])

    package init(_ preference: MicPreference = .builtIn) {
        current = LockedBox(preference)
    }

    package var saves: [MicPreference] { saved.value }
    private let failing = LockedBox(false)

    /// The next `save` reports it could not write.
    package func failNextSave() { failing.value = true }

    package func load() -> MicPreference { current.value }

    package func save(_ preference: MicPreference) -> Bool {
        if failing.withLock({ flag in defer { flag = false }; return flag }) { return false }
        current.value = preference
        saved.value.append(preference)
        return true
    }
}
