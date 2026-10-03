import ApplicationServices
import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

/// One observer per pid, released when the target changes: an observer per
/// window or per call would leak run-loop sources for the life of the app.
@Test @MainActor func singleObserverSlotTests() {
    testTheSamePidReusesItsObserver()
    testANewPidReleasesTheOldOne()
    testAFailedCreationKeepsNothing()
    testNotificationNamesMatchTheSystemConstants()
}

private final class FakeObserver {
    let pid: Int32
    var closed = false
    init(_ pid: Int32) { self.pid = pid }
}

@MainActor func testTheSamePidReusesItsObserver() {
    let slot = SingleObserverSlot<FakeObserver>()
    var made = 0
    let make: (Int32) -> FakeObserver? = { made += 1; return FakeObserver($0) }
    let a = slot.handle(for: 7, make: { make(7) }, release: { $0.closed = true })
    let b = slot.handle(for: 7, make: { make(7) }, release: { $0.closed = true })
    expect(a === b, "mismo pid: el mismo observador")
    expectEq(made, 1, "mismo pid: se crea una vez")
}

@MainActor func testANewPidReleasesTheOldOne() {
    let slot = SingleObserverSlot<FakeObserver>()
    let a = slot.handle(for: 7, make: { FakeObserver(7) }, release: { $0.closed = true })
    let b = slot.handle(for: 8, make: { FakeObserver(8) }, release: { $0.closed = true })
    expect(a?.closed == true, "otro pid: el observador anterior se libera")
    expect(b?.closed == false && b?.pid == 8, "otro pid: el nuevo queda vivo")
}

@MainActor func testAFailedCreationKeepsNothing() {
    let slot = SingleObserverSlot<FakeObserver>()
    let a = slot.handle(for: 7, make: { FakeObserver(7) }, release: { $0.closed = true })
    let none = slot.handle(for: 8, make: { nil }, release: { $0.closed = true })
    expect(none == nil, "creacion fallida: nil, nunca un observador de otro pid")
    expect(a?.closed == true, "creacion fallida: el anterior ya se solto")
    var made = 0
    _ = slot.handle(for: 8, make: { made += 1; return FakeObserver(8) }, release: { $0.closed = true })
    expectEq(made, 1, "creacion fallida: el siguiente intento vuelve a crear")
}

/// The names Core keeps as strings must stay the system's own, or the
/// observer registers for nothing and every result says "no change".
@MainActor func testNotificationNamesMatchTheSystemConstants() {
    let expected: [AXNotification: String] = [
        .windowCreated: kAXWindowCreatedNotification,
        .sheetCreated: kAXSheetCreatedNotification,
        .focusedWindowChanged: kAXFocusedWindowChangedNotification,
        .mainWindowChanged: kAXMainWindowChangedNotification,
        .titleChanged: kAXTitleChangedNotification,
        .focusedUIElementChanged: kAXFocusedUIElementChangedNotification,
        .valueChanged: kAXValueChangedNotification,
        .elementDestroyed: kAXUIElementDestroyedNotification,
    ]
    for notification in AXNotification.allCases {
        expectEq(notification.rawValue, expected[notification], "AX: \(notification) usa el nombre del sistema")
    }
}
