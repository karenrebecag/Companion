import CompanionCore

/// Where capture reads the user's choice and the devices from. The live value
/// reads the shared registry; tests pass their own so nothing touches
/// UserDefaults.standard or the sound card.
package struct MicRouting: Sendable {
    package var port: @Sendable () -> (any MicDevicePort)?
    package var preference: @Sendable () -> MicPreference
    package var inputDevice: @Sendable (MicTarget) -> UInt32?

    package init(
        port: @escaping @Sendable () -> (any MicDevicePort)?,
        preference: @escaping @Sendable () -> MicPreference,
        inputDevice: @escaping @Sendable (MicTarget) -> UInt32?
    ) {
        self.port = port
        self.preference = preference
        self.inputDevice = inputDevice
    }

    package static let live = MicRouting(
        port: { MicDevices.port },
        preference: { MicDevices.store.load() },
        inputDevice: { AudioDevicePin.captureInput(target: $0) })

    package func target() -> MicTarget {
        MicChoice.target(preference: preference(), snapshot: port()?.snapshot() ?? .empty)
    }
}
