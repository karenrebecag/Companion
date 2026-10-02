import CompanionCore
import Foundation
import Testing

// classic-spoken-yes-parent-sheet, phase 1a: a classic hold turn whose parent
// tool waits on the sheet rests, so the question can be asked and answered
// with another press. Without the rest the turn's stream never closes, the
// synth never says `.finished`, and nothing said meanwhile is ever announced.

private func apply(_ machine: inout TurnMachine, _ event: TurnEvent) -> [TurnEffect] {
    machine.handle(event, at: 0)
}

private func holdThinking() -> TurnMachine {
    var m = TurnMachine()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .holdReleased(hasSpeech: true))
    return m
}

private func parkedAtRest() -> TurnMachine {
    var m = holdThinking()
    _ = apply(&m, .sheetParked)
    return m
}

@Test func aParkFromThinkingRestsTheTurnAtOnce() {
    var m = holdThinking()
    #expect(apply(&m, .sheetParked) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(m.snapshot.pipeline == nil)
    #expect(!m.snapshot.holdArmed)
    #expect(m.snapshot.sheetParked)
}

@Test func aParkWhileTheLineStreamsLetsItFinishThenRests() {
    var m = holdThinking()
    _ = apply(&m, .firstSentence)
    #expect(apply(&m, .sheetParked) == [.finishSpeechStream])
    #expect(m.snapshot.state == .speaking, "the work line still plays")
    #expect(apply(&m, .speechFinished) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(m.snapshot.sheetParked, "the rest after the line keeps the mark")
}

@Test func onlyAClassicHoldTurnParks() {
    var realtime = TurnMachine()
    _ = apply(&realtime, .holdPressed(preferRealtime: true))
    _ = apply(&realtime, .realtimeSessionReady)
    _ = apply(&realtime, .serverSpeechStopped)
    let realtimeBefore = realtime.snapshot
    #expect(apply(&realtime, .sheetParked).isEmpty)
    #expect(realtime.snapshot == realtimeBefore)

    var typed = TurnMachine()
    _ = apply(&typed, .typedSubmit)
    let typedBefore = typed.snapshot
    #expect(apply(&typed, .sheetParked).isEmpty)
    #expect(typed.snapshot == typedBefore)

    // Hands-free: its ear is shut for the whole wait, nobody can answer.
    var handsFree = TurnMachine()
    _ = apply(&handsFree, .startVoice(preferRealtime: false))
    _ = apply(&handsFree, .classicListenArmed)
    _ = apply(&handsFree, .advance(hasSpeech: true))
    let handsFreeBefore = handsFree.snapshot
    #expect(apply(&handsFree, .sheetParked).isEmpty)
    #expect(handsFree.snapshot == handsFreeBefore)
}

@Test func aParkFromSpeakingWithNoStreamRestsAtOnce() {
    var m = holdThinking()
    _ = apply(&m, .replyCompleted)
    #expect(m.snapshot.state == .speaking)
    #expect(apply(&m, .sheetParked) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(m.snapshot.sheetParked)
}

@Test func aSecondParkWhileTheLineFinishesIsANoOp() {
    var m = holdThinking()
    _ = apply(&m, .firstSentence)
    _ = apply(&m, .sheetParked)
    #expect(apply(&m, .sheetParked).isEmpty)
}

/// A press before the rest lands is a cut (brief §10 item 8): the turn dies,
/// so nothing is parked any more.
@Test func aPressWhileTheParkedLineStillPlaysCutsTheTurn() {
    var m = holdThinking()
    _ = apply(&m, .firstSentence)
    _ = apply(&m, .sheetParked)
    #expect(apply(&m, .holdPressed(preferRealtime: false))
            == [.cancelAgentOutput(steer: true), .requestClassicListen])
    #expect(!m.snapshot.sheetParked)
}

@Test func anInterruptWhileTheParkedLineStillPlaysCutsTheTurn() {
    var m = holdThinking()
    _ = apply(&m, .firstSentence)
    _ = apply(&m, .sheetParked)
    #expect(apply(&m, .interrupt) == [.cancelAgentOutput(steer: false), .stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(!m.snapshot.sheetParked)
}

@Test func lateTurnEventsAtRestChangeNothing() {
    var m = parkedAtRest()
    let rested = m.snapshot
    for event: TurnEvent in [.replyCompleted, .firstSentence, .speechFinished, .delegateAnnounced] {
        #expect(apply(&m, event).isEmpty)
        #expect(m.snapshot == rested)
    }
}

@Test func aRealtimePressOverAParkedSheetStaysClassic() {
    var m = parkedAtRest()
    #expect(apply(&m, .holdPressed(preferRealtime: true)) == [.requestClassicListen])
    #expect(m.snapshot.pipeline != .realtime)
    #expect(m.snapshot.sheetParked)
}

@Test func aParkOutsideTheTurnIsIgnored() {
    var m = TurnMachine()
    #expect(apply(&m, .sheetParked).isEmpty)
    #expect(!m.snapshot.sheetParked)
}

@Test func aPressOverTheParkedSheetCutsNothing() {
    var m = parkedAtRest()
    #expect(apply(&m, .holdPressed(preferRealtime: false)) == [.requestClassicListen])
    _ = apply(&m, .classicListenArmed)
    #expect(m.snapshot.sheetParked, "the answer hold still knows the sheet waits")
}

@Test func aDiscardedAnswerHoldKeepsTheMark() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    #expect(apply(&m, .holdDiscarded) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(m.snapshot.sheetParked)
}

@Test func wordsThatOpenANewTurnClearTheMark() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    #expect(apply(&m, .holdReleased(hasSpeech: true)) == [.submitUtterance])
    #expect(!m.snapshot.sheetParked)
}

/// The runtime's own empty-hold path (`ClassicRuntime` on nothing heard)
/// and a silent release both hang up; neither stops the parked turn.
@Test func aSilentAnswerHoldKeepsTheMark() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    #expect(apply(&m, .holdReleased(hasSpeech: false)) == [.stopClassicIO])
    #expect(m.snapshot.sheetParked)

    var hungUp = parkedAtRest()
    _ = apply(&hungUp, .holdPressed(preferRealtime: false))
    _ = apply(&hungUp, .classicListenArmed)
    #expect(apply(&hungUp, .hangUp) == [.stopClassicIO])
    #expect(hungUp.snapshot.sheetParked)
}

/// A hang-up stops the mic and the speaker, not the turn task: Stop must
/// still reach the turn afterwards.
@Test func aStopAfterAHangUpStillCutsTheParkedTurn() {
    var m = parkedAtRest()
    _ = apply(&m, .hangUp)
    #expect(apply(&m, .interrupt) == [.cancelAgentOutput(steer: false)])
    #expect(!m.snapshot.sheetParked)
}

@Test func aStopAfterAFailureStillCutsTheParkedTurn() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .turnFailed(.micUnavailable))
    #expect(m.snapshot.state == .error)
    #expect(m.snapshot.sheetParked)
    #expect(apply(&m, .interrupt) == [.cancelAgentOutput(steer: false)])
    #expect(!m.snapshot.sheetParked)
}

@Test func aBargeInWhileTheParkedLinePlaysClearsTheMark() {
    var m = TurnMachine()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .holdReleased(hasSpeech: true))
    _ = apply(&m, .firstSentence)
    _ = apply(&m, .sheetParked)
    let effects = apply(&m, .heardWhileSpeaking(heard: "espera espera no", agentSaying: "dame un momento"))
    #expect(effects == [.cancelAgentOutput(steer: true)])
    #expect(!m.snapshot.sheetParked)
}

/// #87 non-regression: Stop at rest still cuts the parked turn, as a stop
/// and not as a change of course.
@Test func anInterruptAtRestCutsTheParkedTurn() {
    var m = parkedAtRest()
    #expect(apply(&m, .interrupt) == [.cancelAgentOutput(steer: false)])
    #expect(!m.snapshot.sheetParked)
    #expect(apply(&m, .sheetResumed).isEmpty, "a cut turn never speaks again")
    #expect(m.snapshot.state == .idle)
}

/// The brake's own discard lands too, but the stop must not wait for it.
@Test func anInterruptDuringTheAnswerHoldCutsTheParkedTurn() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    #expect(apply(&m, .interrupt) == [.cancelAgentOutput(steer: false), .stopClassicIO])
    #expect(m.snapshot.state == .idle)
    #expect(!m.snapshot.sheetParked)
}

@Test func anInterruptAtRestWithNothingParkedStillDoesNothing() {
    var m = TurnMachine()
    #expect(apply(&m, .interrupt).isEmpty)
}

@Test func aResumeFromRestReopensTheTurnsVoice() {
    var m = parkedAtRest()
    #expect(apply(&m, .sheetResumed) == [.stopClassicIO, .beginSpeechStream])
    #expect(m.snapshot.state == .speaking)
    #expect(m.snapshot.pipeline == .classic)
    #expect(m.snapshot.holdArmed)
    #expect(m.snapshot.streamingStarted)
    #expect(!m.snapshot.sheetParked)
    // The reply after the click ends like any hold reply.
    _ = apply(&m, .replyCompleted)
    #expect(apply(&m, .speechFinished) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
}

@Test func aResumeWhileAnAnswerHoldIsOpenOnlyClearsTheMark() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    #expect(apply(&m, .sheetResumed).isEmpty)
    #expect(m.snapshot.state == .listening, "the open hold is left alone")
    #expect(!m.snapshot.sheetParked)
}

/// The HACK in `sheetResumed`, pinned: a click before the rest lands lets
/// the line finish and the turn rests unparked; the reply is not heard.
@Test func aResumeBeforeTheRestLeavesTheLineToFinish() {
    var m = holdThinking()
    _ = apply(&m, .firstSentence)
    _ = apply(&m, .sheetParked)
    #expect(apply(&m, .sheetResumed).isEmpty)
    #expect(m.snapshot.state == .speaking)
    #expect(!m.snapshot.sheetParked)
    #expect(apply(&m, .speechFinished) == [.stopClassicIO])
    #expect(m.snapshot.state == .idle)
}

@Test func aResumeWhileTheAnswerHoldsMicStartsOnlyClearsTheMark() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    #expect(m.snapshot.classicListenPending)
    #expect(apply(&m, .sheetResumed).isEmpty)
    #expect(!m.snapshot.sheetParked)
}

/// The main 1b flow: press, nothing said, then the click.
@Test func aResumeAfterADiscardedAnswerHoldReopensTheVoiceOnce() {
    var m = parkedAtRest()
    _ = apply(&m, .holdPressed(preferRealtime: false))
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .holdDiscarded)
    #expect(apply(&m, .sheetResumed) == [.stopClassicIO, .beginSpeechStream])
    #expect(m.snapshot.state == .speaking)
    #expect(m.snapshot.holdArmed)
    #expect(apply(&m, .sheetResumed).isEmpty)
}

@Test func aResumeWithNothingParkedDoesNothing() {
    var m = holdThinking()
    #expect(apply(&m, .sheetResumed).isEmpty)
    #expect(m.snapshot.state == .thinking)
}
