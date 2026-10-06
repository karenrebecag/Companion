import CompanionCore
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// A mic that moved to another input built a new engine. The realtime player
// was attached to the old one at open, so without a re-attach the agent goes
// mute for the rest of the session.

@Suite @MainActor struct MicRestartSessionTests {
    @Test func aRestartedMicReattachesThePlayerToTheNewEngine() async {
        let h = makeVoiceHarness(online: true)
        await h.session.start()
        await pumpUntil("listening") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        let before = h.player.sharedStarts.count
        h.mic.emitRestart(.restarted(echoCancellation: true))
        await pumpUntil("player re-attached") { h.player.sharedStarts.count == before + 1 }
        expectEq(h.player.sharedStarts.last, true, "reinicio: el reproductor sigue al motor con eco")
        h.mic.emitRestart(.restarted(echoCancellation: false))
        await pumpUntil("player re-attached without echo cancellation") {
            h.player.sharedStarts.count == before + 2
        }
        expectEq(h.player.sharedStarts.last, false, "reinicio: y al motor propio si ya no hay eco")
    }

    @Test func aMicThatCouldNotRestartFailsTheSessionAsMicUnavailable() async {
        let h = makeVoiceHarness(online: true)
        await h.session.start()
        await pumpUntil("listening") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        h.mic.emitRestart(.failed)
        await pumpUntil("failed") { h.watch.latest.state == .error }
        expectEq(h.watch.latest.failure, .micUnavailable, "reinicio fallido: sin micrófono")
    }

    @Test func aRestartAfterTheFirstHoldStillReachesTheSession() async {
        // A short ready budget: a regression here must fail fast, not wait the default 10 minutes.
        let h = makeVoiceHarness(readyTimeout: 5, online: true)
        await h.session.start()
        await pumpUntil("listening") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        await h.session.hangUp()
        await pumpUntil("hung up") { h.watch.latest.state == .idle }
        // The scripted socket only hands the next open a fresh event stream once the last one ended.
        await h.transport.simulateStreamEnd()
        await h.session.start()
        await pumpUntil("listening again") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        let before = h.player.sharedStarts.count
        h.mic.emitRestart(.restarted(echoCancellation: true))
        await pumpUntil("second hold re-attached") { h.player.sharedStarts.count == before + 1 }
    }

    @Test func aMicRestartWhileTheAgentSpeaksDoesNotStrandTheSessionSpeaking() async {
        let h = makeVoiceHarness(online: true)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.agentAudioStarted)
        await pumpUntil("speaking") { h.watch.latest.state == .speaking }
        await h.player.play(Data([0x01, 0x00, 0x02, 0x00]))
        h.transport.yield(.responseDone)
        await settle()
        expectEq(h.watch.latest.state, .speaking, "hay audio pendiente: sigue hablando")
        h.mic.emitRestart(.restarted(echoCancellation: true))
        await pumpUntil("back to listening") { h.watch.latest.state == .listening }
    }

    @Test func aPlayerThatCannotReattachFailsTheSessionAsMicUnavailable() async {
        let h = makeVoiceHarness(online: true)
        h.player.startError = .unreachable
        await h.session.start()
        await pumpUntil("listening") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        h.mic.emitRestart(.restarted(echoCancellation: true))
        await pumpUntil("failed") { h.watch.latest.state == .error }
        expectEq(h.watch.latest.failure, .micUnavailable, "sin reproductor tras reiniciar: sin micrófono")
    }

    @Test func aRestartAfterTheSessionEndedIsIgnored() async {
        let h = makeVoiceHarness(online: true)
        await h.session.start()
        await pumpUntil("listening") {
            h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
        }
        await h.session.hangUp()
        let before = h.player.sharedStarts.count
        h.mic.emitRestart(.failed)
        h.mic.emitRestart(.restarted(echoCancellation: true))
        await settle(0.2)
        expect(h.watch.latest.state != .error, "sesión cerrada: un fallo tardío no la revive en error")
        expectEq(h.player.sharedStarts.count, before, "sesión cerrada: no se re-engancha el reproductor")
    }

    @Test func aMicThatFailsWhileTheSessionOpensIsNotLost() async {
        let h = makeVoiceHarness(readyTimeout: 5, online: true)
        h.mic.restartsDuringStart = [.failed]
        await h.session.start()
        await pumpUntil("failed") { h.watch.latest.state == .error }
        expectEq(h.watch.latest.failure, .micUnavailable, "fallo al abrir: sin micrófono")
    }

    // The error teardown runs on the reentrant actor while open is parked on an
    // await; open must not resume into a session that already failed.
    @Test func aMicThatFailsBeforeTheSocketOpensNeverOpensIt() async {
        let h = makeVoiceHarness(readyTimeout: 5, online: true)
        h.mic.holdStart = true
        h.mic.restartsDuringStart = [.failed]
        let session = h.session
        var returned = false
        let opening = Task { await session.start(); returned = true }
        await pumpUntil("mic start parked") { h.mic.startEntered }
        await pumpUntil("failed") { h.watch.latest.state == .error }
        h.mic.releaseStart()
        await pumpUntil("start returned") { returned }
        await opening.value
        expectEq(h.transport.openCount, 0, "fallo antes de abrir: no se abre el socket")
        expect(h.player.sharedStarts.isEmpty, "fallo antes de abrir: no se arranca el reproductor")
    }

    @Test func aMicThatFailsWhileTheSocketOpensLeavesNoLiveSocket() async {
        let h = makeVoiceHarness(readyTimeout: 5, online: true)
        h.transport.holdNextOpen = true
        let session = h.session
        var returned = false
        let opening = Task { await session.start(); returned = true }
        await pumpUntil("open entered") { h.transport.openEntered }
        h.mic.emitRestart(.failed)
        await pumpUntil("failed") { h.watch.latest.state == .error }
        // The error snapshot is published before teardown closes the socket;
        // mic.stop is the last step of that close, so capturing earlier could
        // count teardown's own close as the one the guard is meant to add.
        await pumpUntil("teardown done") { h.mic.stopped }
        let closesAfterTeardown = h.transport.closeCount
        h.transport.releaseOpen()
        await pumpUntil("start returned") { returned }
        await opening.value
        expect(h.transport.closeCount > closesAfterTeardown, "fallo durante la apertura: el socket abierto se cierra")
    }
}
