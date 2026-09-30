import CompanionCore
import CoreAudio
import Foundation

/// Listens for default-output-device changes so plugging AirPods mid-session
/// flips the interrupt capability without restarting anything.
package final class AudioOutputWatcher: OutputRouteObserving, @unchecked Sendable {
    private let box = AudioStreamBox<Bool>()
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private let queue = DispatchQueue(label: "companion.output-route")
    private var listener: AudioObjectPropertyListenerBlock?

    package var echoFreeUpdates: AsyncStream<Bool> { box.stream }

    package init() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.publish()
        }
        listener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        publish()
    }

    deinit {
        if let listener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
        }
        box.finish()
    }

    private func publish() {
        box.yield(AudioDevicePin.outputIsEchoFree())
    }
}
