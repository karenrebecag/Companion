import CompanionCore
import CoreAudio
import Foundation

/// Lists input devices and tells listeners when the set or the default changes.
package final class CoreAudioInputPort: MicDevicePort, @unchecked Sendable {
    private let lock = NSLock()
    private var watchers: [UUID: @Sendable (MicDeviceSnapshot) -> Void] = [:]
    private var listening = false
    private var listener: AudioObjectPropertyListenerBlock?

    package init() {}

    package func snapshot() -> MicDeviceSnapshot { AudioDevicePin.inputSnapshot() }

    package func watch(
        _ onChange: @escaping @Sendable (MicDeviceSnapshot) -> Void
    ) -> any MicDeviceWatch {
        let id = UUID()
        lock.withLock {
            watchers[id] = onChange
            guard !listening else { return }
            listening = true
            startListening()
        }
        return PortWatch { [weak self] in self?.remove(id) }
    }

    private func remove(_ id: UUID) {
        let block = lock.withLock { () -> AudioObjectPropertyListenerBlock? in
            watchers[id] = nil
            guard watchers.isEmpty, listening else { return nil }
            listening = false
            defer { listener = nil }
            return listener
        }
        // Outside the lock: removing can wait on a listener that is delivering,
        // and delivering takes this lock.
        if let block { stopListening(block) }
    }

    private func deliver() {
        let snapshot = AudioDevicePin.inputSnapshot()
        let callbacks = lock.withLock { Array(watchers.values) }
        for callback in callbacks { callback(snapshot) }
    }

    /// Caller holds `lock`: the flag and the registration change together, so
    /// a watch and a cancel racing cannot leave a listener nobody removes.
    private func startListening() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.deliver()
        }
        listener = block
        for selector in Self.selectors {
            var location = address(selector)
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &location, .main, block)
            if status != noErr { Log.app("audio: input listener add failed (\(status))") }
        }
    }

    private func stopListening(_ block: @escaping AudioObjectPropertyListenerBlock) {
        for selector in Self.selectors {
            var location = address(selector)
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &location, .main, block)
            if status != noErr { Log.app("audio: input listener remove failed (\(status))") }
        }
    }

    private static let selectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
    ]

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}

package final class PortWatch: MicDeviceWatch, @unchecked Sendable {
    private let end: @Sendable () -> Void
    init(_ end: @escaping @Sendable () -> Void) { self.end = end }
    package func cancel() { end() }
}
