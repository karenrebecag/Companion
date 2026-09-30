import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// 16q-1, third review round. The words of a cancelled hold must not be lent
// to the next hold (the report was stamped with the live press), and the
// closed-ids FIFO keeps distinct ids, not repeats.

@Test @MainActor func approvals16q1Round3Tests() async {
    await testTheWordsOfACancelledHoldAreNotLentToTheNextHold()
    await testACancelledSubmitReportsNoWordsWhateverTheTranscript()
    await testTheHoldsOwnPressTravelsWithItsWords()
    await testNoteHeardStoresOnlyTheLivePressWords()
    await testRepeatedClosesKeepSixtyFourDistinctIDs()
}

private final class HeardLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(String, TimeInterval?)] = []
    var all: [(String, TimeInterval?)] { lock.withLock { items } }
    func add(_ text: String, _ pressed: TimeInterval?) { lock.withLock { items.append((text, pressed)) } }
}

/// Hold A said "sí" while its submit was in flight; press B cancelled it and
/// the report landed after B's press: it carries A's press, not B's.
@MainActor func testTheWordsOfACancelledHoldAreNotLentToTheNextHold() async {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await q1AskedAndSaid(h, jobs, "r1")
    await q1HeldKey(h)
    let pressA = await h.session.timeline.pressed
    await h.session.discard()
    await pumpUntil("prestado: el hold A termino") { h.watch.latest.state != .listening }
    await q1HeldKey(h)
    let pressB = await h.session.timeline.pressed
    expect(pressA != pressB, "rig: dos presses distintos")
    await h.session.noteHeard("sí", pressed: pressA)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "prestado: las palabras del hold A no responden en el hold B")
    jobs.open()
    await h.session.hangUp()
}

@MainActor func testACancelledSubmitReportsNoWordsWhateverTheTranscript() async {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: ScriptedThread())
    let log = HeardLog()
    runtime.onHeard = { text, pressed in log.add(text, pressed) }
    runtime.leftoverHeard = "sí"
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        await runtime.submit(config: Config(language: .es), pressed: 7) { _ in }
    }
    task.cancel()
    await task.value
    expectEq(log.all.map(\.0), [""], "cancelado con palabras: la sesion oye nada")
}

@MainActor func testTheHoldsOwnPressTravelsWithItsWords() async {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: ScriptedThread())
    let log = HeardLog()
    runtime.onHeard = { text, pressed in log.add(text, pressed) }
    runtime.leftoverHeard = "  "
    await runtime.submit(config: Config(language: .es), pressed: 7) { _ in }
    expectEq(log.all.map { $0.1 }, [7], "el press del hold viaja con lo que oyo")
}

@MainActor func testRepeatedClosesKeepSixtyFourDistinctIDs() async {
    let h = makeVoiceHarness(language: .es)
    let cap = VoiceSession.closedApprovalCap
    for index in 0 ..< cap { await h.session.approvalClosed(requestId: "d\(index)") }
    for _ in 0 ..< 10 { await h.session.approvalClosed(requestId: "d\(cap - 1)") }
    await h.session.noteApproval(q1Req("d0"))
    expect(await h.session.pendingApproval == nil, "repetidos: el mas viejo sigue cerrado")
    await h.session.hangUp()
}

/// The press comparison of `noteHeard` on its own: with no approval in play,
/// the stored words are the only thing that shows whether it held.
@MainActor func testNoteHeardStoresOnlyTheLivePressWords() async {
    let h = makeVoiceHarness(language: .es)
    await q1HeldKey(h)
    let pressA = await h.session.timeline.pressed
    await h.session.discard()
    await pumpUntil("press: el hold A termino") { h.watch.latest.state != .listening }
    await q1HeldKey(h)
    let pressB = await h.session.timeline.pressed
    expect(pressA != pressB, "rig: dos presses distintos")
    await h.session.noteHeard("sí", pressed: pressB)
    expectEq(await h.session.heardThisHold?.text, "sí", "press vivo: las palabras se guardan")
    await h.session.noteHeard("dale", pressed: pressA)
    expect(await h.session.heardThisHold == nil, "press viejo: no se guarda nada y se borra lo anterior")
    await h.session.discard()
    await h.session.hangUp()
}
