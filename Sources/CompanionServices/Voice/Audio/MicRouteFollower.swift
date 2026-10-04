import CompanionCore
import Foundation

/// While the mic is open, watches the input list and asks for a restart when
/// the input capture is pinned to would be a different one: the chosen device
/// unplugged (capture must move to the system default) or plugged back in.
/// Capture re-resolves the device itself, so the restart carries only the
/// target it should end up on. A pick made in settings while the mic is open
/// is not an event here, because it changes no device: it takes effect on the
/// next start (or the next device change), so an open mic never switches
/// input under someone who is mid-sentence.
package final class MicRouteFollower: @unchecked Sendable {
    private let port: any MicDevicePort
    private let preference: @Sendable () -> MicPreference
    private let restart: @Sendable (MicTarget) -> Void
    private let state = LockedState()

    private final class LockedState: @unchecked Sendable {
        let lock = NSLock()
        var route: MicRoute?
        var watch: (any MicDeviceWatch)?
    }

    package init(
        port: any MicDevicePort,
        preference: @escaping @Sendable () -> MicPreference,
        restart: @escaping @Sendable (MicTarget) -> Void
    ) {
        self.port = port
        self.preference = preference
        self.restart = restart
    }

    package func begin() {
        end()
        let first = route(port.snapshot())
        let watch = port.watch { [weak self] snapshot in self?.changed(snapshot) }
        let stale = state.lock.withLock { () -> (any MicDeviceWatch)? in
            state.route = first
            defer { state.watch = watch }
            return state.watch
        }
        stale?.cancel()
    }

    package func end() {
        let watch = state.lock.withLock { () -> (any MicDeviceWatch)? in
            state.route = nil
            defer { state.watch = nil }
            return state.watch
        }
        watch?.cancel()
    }

    /// The engine stops itself when its device goes away. Stopped on purpose
    /// (`running` false) is not a reason to reopen the mic.
    package static func shouldRestartAfterConfigurationChange(
        running: Bool, engineRunning: Bool
    ) -> Bool {
        running && !engineRunning
    }

    private func changed(_ snapshot: MicDeviceSnapshot) {
        let next = route(snapshot)
        let moved = state.lock.withLock { () -> Bool in
            guard state.watch != nil, let current = state.route, current != next else { return false }
            state.route = next
            return true
        }
        if moved { restart(next.target) }
    }

    private func route(_ snapshot: MicDeviceSnapshot) -> MicRoute {
        MicChoice.route(preference: preference(), snapshot: snapshot)
    }
}
