import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Mid-session: the chosen microphone is unplugged while the mic is open.
// Capture has to move to the system default instead of going silent.

private let mac = MicInput(id: "mac", name: "Mac", builtIn: true)
private let usb = MicInput(id: "usb", name: "USB", builtIn: false)
private let both = MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "Mac")
private let usbPref = MicPreference.device(id: "usb", name: "USB")

private func follower(
    _ port: FakeMicPort, _ preference: MicPreference, _ log: LockedBox<[MicTarget]>
) -> MicRouteFollower {
    MicRouteFollower(port: port, preference: { preference }, restart: { log.value.append($0) })
}

@Suite struct MicRouteFollowerTests {
    @Test func theChosenDeviceDisappearingMovesCaptureToTheSystemDefault() {
        let port = FakeMicPort(both)
        let log = LockedBox<[MicTarget]>([])
        let follow = follower(port, usbPref, log)
        follow.begin()
        port.publish(MicDeviceSnapshot(devices: [mac], systemDefaultName: "Mac"))
        expectEq(log.value, [.systemDefault], "se fue: un reinicio hacia el del sistema")
        port.publish(both)
        expectEq(log.value, [.systemDefault, .device("usb")], "volvió: un reinicio hacia el elegido")
        follow.end()
    }

    @Test func anUnrelatedChangeDoesNotRestartCapture() {
        let port = FakeMicPort(both)
        let log = LockedBox<[MicTarget]>([])
        let follow = follower(port, usbPref, log)
        follow.begin()
        port.publish(MicDeviceSnapshot(
            devices: [mac, usb, MicInput(id: "z", name: "Z", builtIn: false)], systemDefaultName: "Mac"))
        port.publish(MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "USB"))
        expectEq(log.value, [], "ajeno: ni un dispositivo nuevo ni mover el del sistema reinicia")
        follow.end()
    }

    @Test func theSystemDefaultMovingRestartsAFollowingCapture() {
        let port = FakeMicPort(both)
        let log = LockedBox<[MicTarget]>([])
        let follow = follower(port, .systemDefault, log)
        follow.begin()
        port.publish(MicDeviceSnapshot(devices: [mac, usb], systemDefaultName: "USB"))
        expectEq(log.value, [.systemDefault], "el del sistema se movió: reinicia")
        follow.end()
    }

    @Test func endingStopsWatchingAndBeginTwiceWatchesOnce() {
        let port = FakeMicPort(both)
        let log = LockedBox<[MicTarget]>([])
        let follow = follower(port, usbPref, log)
        follow.begin()
        follow.begin()
        expectEq(port.watcherCount, 1, "dos begin: un solo observador")
        follow.end()
        expectEq(port.watcherCount, 0, "end: sin observadores")
        port.publish(MicDeviceSnapshot(devices: [mac], systemDefaultName: "Mac"))
        expectEq(log.value, [], "end: ya no reinicia")
    }

    @Test func anEngineStoppedByTheSystemWhileRunningIsRestarted() {
        expect(MicRouteFollower.shouldRestartAfterConfigurationChange(running: true, engineRunning: false),
               "configuración: el motor se detuvo con la captura abierta")
        expect(!MicRouteFollower.shouldRestartAfterConfigurationChange(running: true, engineRunning: true),
               "configuración: un cambio que no lo detuvo se deja")
        expect(!MicRouteFollower.shouldRestartAfterConfigurationChange(running: false, engineRunning: false),
               "configuración: parado a propósito no se reabre")
    }
}
