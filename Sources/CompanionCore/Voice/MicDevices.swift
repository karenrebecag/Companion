import Foundation

// brief ajustes-hoja-incredible E35
// The ports the settings row and the capture share. UI cannot import the
// audio target, so both read the real devices through what is installed here.

package protocol MicPreferenceStoring: Sendable {
    func load() -> MicPreference
    /// False when the choice could not be written: the caller must not act as
    /// if it were stored.
    @discardableResult func save(_ preference: MicPreference) -> Bool
}

/// UserDefaults is not Sendable in this SDK. The suite is only read and
/// written through this lock-free API, which is safe for one key.
package final class MicPreferenceStore: MicPreferenceStoring, @unchecked Sendable {
    package static let key = "companion.mic.choice"
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Unset or unreadable means the built-in mic: that is what capture
    /// already pinned, so a machine with no saved choice does not move. Core
    /// has no log, so an unreadable value falls back without a line.
    package func load() -> MicPreference {
        guard let data = defaults.data(forKey: Self.key) else { return .builtIn }
        let preference: MicPreference
        do {
            preference = try JSONDecoder().decode(MicPreference.self, from: data)
        } catch {
            return .builtIn
        }
        if case .device(let id, let name) = preference, id.isEmpty || name.isEmpty {
            return .builtIn
        }
        return preference
    }

    @discardableResult
    package func save(_ preference: MicPreference) -> Bool {
        let data: Data
        do {
            data = try JSONEncoder().encode(preference)
        } catch {
            return false
        }
        defaults.set(data, forKey: Self.key)
        return true
    }
}

package protocol MicDeviceWatch: Sendable {
    func cancel()
}

package protocol MicDevicePort: Sendable {
    func snapshot() -> MicDeviceSnapshot
    func watch(_ onChange: @escaping @Sendable (MicDeviceSnapshot) -> Void) -> any MicDeviceWatch
}

package enum MicProbeFault: Equatable, Sendable {
    case blocked
    case noInput
    case failed
}

package protocol MicMeter: Sendable {
    /// Whether the microphone is already allowed. UI cannot import the audio
    /// framework, and opening the popup must never trigger the prompt.
    var microphoneAuthorized: Bool { get }
    func onLevel(_ handler: @escaping @Sendable (Double) -> Void)
    func start(target: MicTarget) async -> MicProbeFault?
    func stop()
}

/// The composition root registers the real devices once. The slot is locked:
/// a second registration must not replace the port the open mic is reading.
package enum MicDevices {
    private final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var port: (any MicDevicePort)?
        var meter: (any MicMeter)?
    }

    private static let slot = Slot()
    package static let store = MicPreferenceStore()

    package static var port: (any MicDevicePort)? {
        slot.lock.withLock { slot.port }
    }

    package static var meter: (any MicMeter)? {
        slot.lock.withLock { slot.meter }
    }

    package static func install(port: any MicDevicePort, meter: (any MicMeter)?) {
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if slot.port == nil { slot.port = port }
        if slot.meter == nil { slot.meter = meter }
    }
}
