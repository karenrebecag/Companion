@testable import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Gap 1c: a lost Screen Recording grant is a permission card with the way to
// Settings, once per run, instead of sight going quiet.

@Test func screenRecordingLossIsAPermissionCard() {
    expectEq(SessionMachine.card(for: .screenRecordingDenied), .permission(.screenRecordingDenied),
             "a lost grant is fixed in Settings, like the other permissions")
}

@Test func screenRecordingLossShowsTheCardOncePerRun() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    let kind = machine.projection.kind
    _ = machine.handle(.screenRecordingLost)
    expectEq(machine.projection.notice, .permission(.screenRecordingDenied), "the card is up")
    expectEq(machine.projection.cards, [.permission(.screenRecordingDenied)], "and listed")
    expectEq(machine.projection.kind, kind, "a notice, not a transition: the turn owns the kind")
    _ = machine.handle(.pressed)
    expect(machine.projection.notice == nil, "starting something new clears it")
    _ = machine.handle(.screenRecordingLost)
    expect(machine.projection.notice == nil, "a second loss in the same run does not nag")
}
