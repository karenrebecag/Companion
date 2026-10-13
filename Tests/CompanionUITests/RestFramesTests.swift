import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Observation
import Testing

// At rest the app must draw nothing: a hidden window stops its orbs, and the
// toast clock sleeps while there is no toast.

@Test @MainActor func aWindowOffScreenIsNotVisible() {
    expect(SurfaceVisibility.visible(.visible), "an on-screen window is visible")
    expect(!SurfaceVisibility.visible([]), "ordered out, minimized or covered is not")
}

@Test @MainActor func theIslandOrbAnimatesOnlyWhenSeen() {
    expect(IslandVoiceOrb.animates(active: true, surfaceVisible: true), "shown orb moves")
    expect(!IslandVoiceOrb.animates(active: true, surfaceVisible: false), "hidden window: frames stop")
    expect(!IslandVoiceOrb.animates(active: false, surfaceVisible: true), "fading panel: frames stop")
}

@Test @MainActor func anEmptyToastStackSchedulesOneFrame() {
    let start = Date(timeIntervalSince1970: 1000)
    let idle = Array(ToastTicks(active: false).entries(from: start, mode: .normal).prefix(5))
    expectEq(idle, [start], "no toast, no clock")
    let live = Array(ToastTicks(active: true).entries(from: start, mode: .normal).prefix(3))
    expectEq(live, [start, start.addingTimeInterval(0.5), start.addingTimeInterval(1)], "a toast ticks twice a second")
}

@Test @MainActor func aTickThatExpiresNothingDoesNotRepaint() {
    let center = NoticeCenter(now: { 0 })
    center.toast("hola")
    let notified = Flag()
    withObservationTracking { _ = center.queue } onChange: { notified.set() }
    center.tick(at: 1)
    expect(!notified.value, "nothing expired, nobody is told")
    center.tick(at: NoticeQueue.lifetime + 1)
    expect(notified.value, "a real expiry repaints")
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}
