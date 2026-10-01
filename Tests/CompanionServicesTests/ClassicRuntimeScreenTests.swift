import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15b-7b (review follow-up). `senseVoice` used to compute `hasText`
// from `ctx.screenSnippets` BEFORE `screen.finish(wait:)` ran — but AX text
// only ever arrives THROUGH `finish` (harvested at press, 15b-6), so
// `hasText` was always false and every order paid vision's 2 s wait. The
// fix: ask the screen port for its already-running AX harvest first.

@Test @MainActor func classicRuntimeScreenTests() async {
    await testNonScreenOrderWithAXTextDoesNotAwaitVision()
    await testScreenPointingOrderStillWaitsForVision()
}

@MainActor func testNonScreenOrderWithAXTextDoesNotAwaitVision() async {
    let screen = FakeScreenSeeing()
    screen.axResult = [ScreenSnippet(app: "Mail", text: "Inbox (3)")]
    // If `finish(wait:)` were ever asked to wait, this fake would hang for
    // it — proving the turn is not delayed by a hanging vision call.
    screen.hangsUntilWaitElapses = true
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Mail"
    let thread = ScriptedThread()
    let chat = ScriptedChat()
    chat.deltas = [.text("Abrí Mail.")]
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: thread)
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice))
    runtime.screen = screen

    await runtime.submit(config: Config(language: .en)) { _ in }

    expect(thread.finished, "15b-7b: el turno termina (no se queda colgado esperando visión)")
    expectEq(screen.waits, [.zero],
             "15b-7b: con texto AX ya cosechado, finish(wait:) pide .zero")
}

@MainActor func testScreenPointingOrderStillWaitsForVision() async {
    let screen = FakeScreenSeeing()
    screen.axResult = [ScreenSnippet(app: "Safari", text: "Titular del día")]
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "¿qué dice esto?"
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: thread)
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice))
    runtime.screen = screen

    await runtime.submit(config: Config(language: .en)) { _ in }

    expectEq(screen.waits, [.seconds(2)],
             "15b-7b: una orden que señala la pantalla sigue esperando la visión")
}

/// Wave 15b-7b: a screen port fake that records the `wait` `finish` was
/// asked for and can prove a call that should not wait never sits on one.
final class FakeScreenSeeing: ScreenSeeing, @unchecked Sendable {
    var axResult: [ScreenSnippet] = []
    var briefToReturn = ScreenBrief()
    var hangsUntilWaitElapses = false
    private let lock = NSLock()
    private var _waits: [Duration] = []
    var waits: [Duration] {
        lock.withLock { _waits }
    }

    private var _begins = 0
    /// Every `begin` is a screenshot on its way to the vision model.
    var begins: Int { lock.withLock { _begins } }

    func begin(app: String?) { lock.withLock { _begins += 1 } }

    private var _pointings = 0
    /// Wave 16o-3: pointer sampling, local and on every pipeline.
    var pointings: Int { lock.withLock { _pointings } }
    func beginPointing() { lock.withLock { _pointings += 1 } }
    func cancel() {}
    func axSnippets() async -> [ScreenSnippet] { axResult }
    func finish(wait: Duration) async -> ScreenBrief {
        lock.withLock { _waits.append(wait) }
        if hangsUntilWaitElapses, wait > .zero {
            try? await Task.sleep(for: wait)
        }
        return briefToReturn
    }
}
