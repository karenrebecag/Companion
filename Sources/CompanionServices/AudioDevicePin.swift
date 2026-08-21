import AudioToolbox
import CoreAudio
import Foundation

/// VPIO builds an aggregate from the SYSTEM DEFAULT devices; with a virtual
/// device in the chain (Teams et al.) that aggregate fails with -10875.
/// Apple's documented escape: pin BOTH buses of the voice-processing unit to
/// explicit devices, on global scope, BEFORE the unit initializes.
/// https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice
enum AudioDevicePin {
    /// Built-in mic + built-in speakers: the pair VPIO can always aggregate.
    static func builtInPair() -> (input: AudioDeviceID, output: AudioDeviceID)? {
        var input: AudioDeviceID?
        var output: AudioDeviceID?
        for device in allDevices() {
            guard transportType(device) == kAudioDeviceTransportTypeBuiltIn else {
                continue
            }
            if input == nil, channelCount(device, scope: kAudioObjectPropertyScopeInput) > 0 {
                input = device
            }
            if output == nil, channelCount(device, scope: kAudioObjectPropertyScopeOutput) > 0 {
                output = device
            }
        }
        guard let input, let output else { return nil }
        return (input, output)
    }

    /// Plain AUHAL input: pin only the input bus to the built-in mic. After a
    /// failed VPIO attempt the process default can stay glued to the broken
    /// aggregate (input reads 3ch instead of the built-in mic's 1ch) and the
    /// graph starts but never delivers a buffer.
    static func pinInput(_ unit: AudioUnit) -> Bool {
        guard let pair = builtInPair() else { return false }
        return setDevice(unit, device: pair.input, element: 1)
    }

    /// Both buses, both devices, before init — partial pinning can fail if
    /// either side is not aggregatable (Apple's guidelines).
    static func pin(
        _ unit: AudioUnit, input: AudioDeviceID, output: AudioDeviceID
    ) -> Bool {
        setDevice(unit, device: input, element: 1)
            && setDevice(unit, device: output, element: 0)
    }

    /// True when the default output cannot feed back into the mic: bluetooth
    /// headsets do their own echo control, and headphones have no room echo.
    static func outputIsEchoFree() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        switch transportType(device) {
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return true
        case kAudioDeviceTransportTypeBuiltIn:
            return dataSource(device) == kIOAudioOutputPortSubTypeHeadphones
        default:
            return false
        }
    }

    // MARK: - CoreAudio plumbing

    private static let headphonesSource: UInt32 = 0x6864_706E // 'hdpn'
    private static var kIOAudioOutputPortSubTypeHeadphones: UInt32 { headphonesSource }

    private static func setDevice(
        _ unit: AudioUnit, device: AudioDeviceID, element: AudioUnitElement
    ) -> Bool {
        var value = device
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            element,
            &value,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            Log.app("audio: pin device on element \(element) failed (\(status))")
        }
        return status == noErr
    }

    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }
        return devices
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != 0 else { return nil }
        return device
    }

    private static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return value
    }

    private static func dataSource(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }
        return value
    }

    private static func channelCount(
        _ device: AudioDeviceID, scope: AudioObjectPropertyScope
    ) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size > 0 else { return 0 }
        let list = UnsafeMutablePointer<AudioBufferList>.allocate(
            capacity: Int(size) / MemoryLayout<AudioBufferList>.stride + 1)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr
        else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
