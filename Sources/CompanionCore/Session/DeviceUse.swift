import Foundation

/// Whether another app holds the microphone or the camera right now. An
/// adapter in Services reads the devices; Core only decides what it means.
package struct DeviceUse: Sendable, Equatable {
    package var microphone: Bool
    package var camera: Bool

    package static let idle = DeviceUse(microphone: false, camera: false)

    package init(microphone: Bool, camera: Bool) {
        self.microphone = microphone
        self.camera = camera
    }
}

/// The port the reducer is fed through: a stream of every change in use.
package protocol DeviceUseWatching: Sendable {
    func changes() -> AsyncStream<DeviceUse>
}

package enum MeetingPresence {
    /// A meeting is a camera in use, or a microphone in use that is not
    /// Companion's own listening: the mic is open for Companion as well, and
    /// that must not make the island think somebody else is in a call.
    package static func compact(_ use: DeviceUse, ownMicrophone: Bool) -> Bool {
        use.camera || (use.microphone && !ownMicrophone)
    }
}
