import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func motionTests() {
    testMotionTimeDurations()
    testMotionTimeOrdering()
    testStaggerDurations()
}

@MainActor func testMotionTimeDurations() {
    expectEq(MotionTime.fast, 0.15, "fast is 150ms")
    expectEq(MotionTime.base, 0.2, "base is 200ms")
    expectEq(MotionTime.panel, 0.3, "panel is 300ms")
    expectEq(MotionTime.enter, 0.6, "enter is 600ms")
    expectEq(MotionTime.layout, 0.9, "layout is 900ms")
}

@MainActor func testMotionTimeOrdering() {
    expect(MotionTime.fast < MotionTime.base,
           "fast < base")
    expect(MotionTime.base < MotionTime.panel,
           "base < panel")
    expect(MotionTime.panel < MotionTime.enter,
           "panel < enter")
    expect(MotionTime.enter < MotionTime.layout,
           "enter < layout")
}

@MainActor func testStaggerDurations() {
    expectEq(Stagger.dense, 0.03, "dense stagger 30ms")
    expectEq(Stagger.base, 0.05, "base stagger 50ms")
    expectEq(Stagger.loose, 0.075, "loose stagger 75ms")
    expect(Stagger.dense < Stagger.base, "dense < base")
    expect(Stagger.base < Stagger.loose, "base < loose")
}
