import CompanionCore
@testable import CompanionServices
import CoreGraphics
import Foundation
import Testing

// Wave 15d-1 (TDD row 1, tap side). The HID tap itself, fed synthetic
// events and an injected clock: FN opens the mic on the way down, a tap or
// a chord cancels it, a long hold releases. The dictation key still waits.

@Test @MainActor func holdKeyTapTests() async {
    await testFNPressesOnTheWayDownAndCancelsATap()
    await testFNHeldPastTheThresholdReleases()
    await testFNChordCancelsTheOpenMic()
    await testTheDictationKeyStillWaitsForTheThreshold()
    await testFNHeldPastTheThresholdConfirms()
}

private final class TapClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

private final class TapEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [HoldKeyEvent] = []
    var events: [HoldKeyEvent] { lock.withLock { seen } }

    init(_ stream: AsyncStream<HoldKeyEvent>) {
        Task { [weak self] in
            for await event in stream { self?.store(event) }
        }
    }

    private func store(_ event: HoldKeyEvent) {
        lock.withLock { seen.append(event) }
    }
}

private func flagsEvent(code: CGKeyCode = 63, down: Bool, flag: CGEventFlags = .maskSecondaryFn) -> CGEvent? {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true) else {
        return nil
    }
    event.type = .flagsChanged
    event.flags = down ? flag : []
    return event
}

private func keyEvent(code: CGKeyCode) -> CGEvent? {
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
}

@MainActor func testFNPressesOnTheWayDownAndCancelsATap() async {
    let clock = TapClock()
    let tap = HoldKeyTap(now: { clock.now })
    let seen = TapEvents(tap.events)
    guard let down = flagsEvent(down: true), let up = flagsEvent(down: false) else {
        expect(false, "tap: no se pudo crear el evento")
        return
    }
    clock.now = 10
    _ = tap.handle(type: .flagsChanged, event: down)
    await pumpUntil("tap: pressed al bajar") { seen.events == [.pressed] }
    clock.now = 10.1
    let swallowed = tap.handle(type: .flagsChanged, event: up)
    await pumpUntil("tap: cancelado al soltar pronto") { seen.events == [.pressed, .cancelled] }
    expect(swallowed, "tap: FN se traga el tap para que Globe no dispare")
}

@MainActor func testFNHeldPastTheThresholdReleases() async {
    let clock = TapClock()
    let tap = HoldKeyTap(now: { clock.now })
    let seen = TapEvents(tap.events)
    guard let down = flagsEvent(down: true), let up = flagsEvent(down: false) else {
        expect(false, "hold: no se pudo crear el evento")
        return
    }
    clock.now = 20
    _ = tap.handle(type: .flagsChanged, event: down)
    clock.now = 20.4
    _ = tap.handle(type: .flagsChanged, event: up)
    await pumpUntil("hold: pressed y released") { seen.events == [.pressed, .released] }
    await settle(0.35)
    expectEq(seen.events, [.pressed, .released], "hold: ningún armado tardío después")
}

@MainActor func testFNChordCancelsTheOpenMic() async {
    let clock = TapClock()
    let tap = HoldKeyTap(now: { clock.now })
    let seen = TapEvents(tap.events)
    guard let down = flagsEvent(down: true), let arrow = keyEvent(code: 123),
          let up = flagsEvent(down: false) else {
        expect(false, "acorde: no se pudo crear el evento")
        return
    }
    clock.now = 30
    _ = tap.handle(type: .flagsChanged, event: down)
    clock.now = 30.05
    _ = tap.handle(type: .keyDown, event: arrow)
    clock.now = 30.5
    _ = tap.handle(type: .flagsChanged, event: up)
    await pumpUntil("acorde: pressed y cancelado") { seen.events == [.pressed, .cancelled] }
    await settle(0.05)
    expectEq(seen.events, [.pressed, .cancelled], "acorde: el up no es un release")
}

/// The dictation modifier types symbols: arming it on the way down would
/// open the mic on every `@`. It keeps the 12h threshold.
@MainActor func testTheDictationKeyStillWaitsForTheThreshold() async {
    let clock = TapClock()
    let tap = HoldKeyTap(
        keyCode: 61, flag: .maskAlternate, swallowsRelease: false, tapThreshold: 0.1,
        armsOnDown: false, now: { clock.now })
    let seen = TapEvents(tap.events)
    guard let down = flagsEvent(code: 61, down: true, flag: .maskAlternate),
          let up = flagsEvent(code: 61, down: false, flag: .maskAlternate) else {
        expect(false, "dictado: no se pudo crear el evento")
        return
    }
    clock.now = 40
    _ = tap.handle(type: .flagsChanged, event: down)
    await settle(0.03)
    expect(seen.events.isEmpty, "dictado: bajar no arma el micro")
    clock.now = 40.05
    _ = tap.handle(type: .flagsChanged, event: up)
    await settle(0.15)
    expect(seen.events.isEmpty, "dictado: un tap no emite nada")
}

/// Code review 2026-09-24: the tap emits `.confirmed` at the threshold while
/// FN is still down; network work waits for it.
@MainActor func testFNHeldPastTheThresholdConfirms() async {
    let clock = TapClock()
    let tap = HoldKeyTap(tapThreshold: 0.1, now: { clock.now })
    let seen = TapEvents(tap.events)
    guard let down = flagsEvent(down: true), let up = flagsEvent(down: false) else {
        expect(false, "confirmado: no se pudo crear el evento")
        return
    }
    clock.now = 50
    _ = tap.handle(type: .flagsChanged, event: down)
    clock.now = 50.2
    await pumpUntil("confirmado: pressed y confirmed") { seen.events == [.pressed, .confirmed] }
    clock.now = 50.5
    _ = tap.handle(type: .flagsChanged, event: up)
    await pumpUntil("confirmado: y released") { seen.events == [.pressed, .confirmed, .released] }
}
