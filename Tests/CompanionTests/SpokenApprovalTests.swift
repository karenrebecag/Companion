import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Review 16h-2 round 3 (HIGH): a spoken "yes" is words the model reports,
// and with the voice free while a job runs they may answer something else.
// It reaches a sheet only in classic, only once the voice itself said the
// question, and only in a hold that began after that, the dwell included.
// Everything else asks for the sheet's click.

@Test @MainActor func spokenApprovalTests() async {
    await testASheetFromBeforeTheHoldWithNoAnnouncementNeedsAClick()
    await testASheetThatAppearsDuringTheHoldNeedsAClick()
    await testRealtimeNeverTakesASpokenYes()
    await testAnAnnouncedSheetIsAnsweredInALaterHold()
}

// Low risk (20c D1): a Bash request takes the click whatever the timing.
private let sheet = ApprovalRequest(
    requestId: "r1", toolName: "find_places", summary: "cines cerca", inputJSON: "{}")

@MainActor private func holding(_ h: VoiceHarness) async {
    await h.session.hold()
    await pumpUntil("sí hablado: hold") { h.watch.latest.state == .listening }
}

@MainActor func testASheetFromBeforeTheHoldWithNoAnnouncementNeedsAClick() async {
    let h = makeVoiceHarness(language: .es)
    await h.session.noteApproval(sheet)
    h.clock.now += 5
    await holding(h)
    h.clock.now += 1
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "sí hablado: una hoja que la voz nunca dijo pide el clic")
    await h.session.hangUp()
}

@MainActor func testASheetThatAppearsDuringTheHoldNeedsAClick() async {
    let h = makeVoiceHarness(language: .es)
    await holding(h)
    h.clock.now += 1
    await h.session.noteApproval(sheet)
    h.clock.now += ApprovalClickGuard.dwell + 1
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "sí hablado: la hoja que aparece con la tecla abajo pide el clic")
    await h.session.hangUp()
}

@MainActor func testRealtimeNeverTakesASpokenYes() async {
    let h = makeVoiceHarness(language: .es)
    await h.session.start()
    await pumpUntil("realtime: escuchando") { h.watch.latest.state == .listening }
    await h.session.noteApproval(sheet)
    h.clock.now += 10
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "realtime: sin holds, el sí hablado nunca resuelve")
    await h.session.hangUp()
}

@MainActor func testAnAnnouncedSheetIsAnsweredInALaterHold() async {
    let h = makeVoiceHarness(language: .es)
    await h.session.noteApproval(sheet)
    await h.session.approvalAnnounced(sheet.requestId)
    h.clock.now += 5
    await holding(h)
    h.clock.now += 1
    await h.session.noteHeard("sí, dale", pressed: await h.session.timeline.pressed)
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .resolved, "sí hablado: dicha la pregunta, un hold posterior la contesta")
    await h.session.hangUp()
}
