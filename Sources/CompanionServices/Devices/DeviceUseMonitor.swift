import CompanionCore
import CoreAudio
import CoreMediaIO
import Foundation

/// Reads whether any process holds the default microphone or any camera, by
/// the devices' own "running somewhere" flags. Polled: those flags have no
/// change notice that works for every device, and the island needs seconds, not
/// milliseconds, to go compact.
package struct DeviceUseMonitor: DeviceUseWatching {
    package static let pollInterval: Duration = .seconds(2)

    package init() {}

    package func changes() -> AsyncStream<DeviceUse> {
        AsyncStream { continuation in
            let task = Task.detached {
                var last: DeviceUse?
                while !Task.isCancelled {
                    let now = DeviceUse(microphone: Self.microphoneInUse(), camera: Self.cameraInUse())
                    if now != last {
                        last = now
                        continuation.yield(now)
                    }
                    do { try await Task.sleep(for: Self.pollInterval) } catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != AudioObjectID(kAudioObjectUnknown)
        else { return false }
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return flag(device, &address)
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == OSStatus(kCMIOHardwareNoError),
              size > 0
        else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == OSStatus(kCMIOHardwareNoError)
        else { return false }
        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        return devices.contains { device in
            var address = running
            return cmioFlag(device, &address)
        }
    }

    private static func flag(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private static func cmioFlag(_ object: CMIOObjectID, _ address: inout CMIOObjectPropertyAddress) -> Bool {
        var value: UInt32 = 0
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &value) == OSStatus(kCMIOHardwareNoError)
        else { return false }
        return value != 0
    }
}
