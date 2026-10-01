import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15b-9. `<time_since_last_interaction>` reads the thread's own clock
// (`ConversationPresenting.lastInteraction()`), never a sensor's own guess
// and never the turn's own arrival: the value is captured BEFORE that
// arrival stamps `lastActivity` to now, or every turn would report zero
// seconds since itself.

@Test @MainActor func interactionClockTests() async {
    await testHoldSevenSecondsAfterAnAckShowsSeven()
    await testHoldSixMinutesLaterRollsOverWithNoTag()
    await testTypedTurnTwentySecondsAfterAHoldShowsTwentyNotZero()
    await testFirstTurnOfTheAppShowsNoTag()
    await testJobResultThirtySecondsAgoShowsThirty()
}

// MARK: - Harness

/// The real presenter (`ChatViewModel`) as `ClassicRuntime`'s thread: only
/// the real presenter implements `lastInteraction()` with an actual clock
/// (every scripted fake elsewhere takes the port's default of `nil`), so
/// this wave's behavior can only be proven end to end.
private struct InteractionHarness {
    let vm: ChatViewModel
    let vmChat: FakeChatProvider
    let runtime: ClassicRuntime
    let transcriber: FakeTranscriber
    let runtimeChat: ScriptedChat
}

@MainActor
private func makeInteractionHarness(clock: RolloverClock) -> InteractionHarness {
    let vmChat = FakeChatProvider()
    let vm = ChatViewModel(
        chat: vmChat, secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default,
        sensor: FakeContextSensor(TurnContext(source: .typed)),
        now: { clock.date })
    vm.onAppear()
    let transcriber = FakeTranscriber()
    let runtimeChat = ScriptedChat()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: runtimeChat, thread: vm)
    runtime.now = { clock.date }
    runtime.sensor = FakeContextSensor(TurnContext(source: .typed))
    return InteractionHarness(
        vm: vm, vmChat: vmChat, runtime: runtime, transcriber: transcriber,
        runtimeChat: runtimeChat)
}

private func ackDecide(_: String, _: Bool) async -> DecisionOutcome {
    .acted(
        ParentToolOutcome(ok: true, output: "", target: "Safari"),
        ToolCallRef(id: "1", name: "open_app", arguments: #"{"name":"Safari"}"#))
}

// MARK: - 1: a hold 7s after a router ack

@MainActor func testHoldSevenSecondsAfterAnAckShowsSeven() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let h = makeInteractionHarness(clock: clock)
    h.transcriber.stoppedText = "abre Safari"
    h.runtime.decide = ackDecide
    await h.runtime.submit(config: Config(language: .en)) { _ in }

    clock.advance(by: 7)
    h.runtime.decide = nil
    h.transcriber.stoppedText = "qué hora es"
    h.runtimeChat.deltas = [.text("Son las 2.")]
    await h.runtime.submit(config: Config(language: .en)) { _ in }

    let content = h.runtimeChat.histories.last?.last?.content ?? ""
    expect(content.contains("<time_since_last_interaction seconds=\"7\">"),
           "reloj1: 7 s desde el acuse del router")
}

// MARK: - 2: a hold 6 minutes later rolls over, no tag

@MainActor func testHoldSixMinutesLaterRollsOverWithNoTag() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let h = makeInteractionHarness(clock: clock)
    h.transcriber.stoppedText = "abre Safari"
    h.runtime.decide = ackDecide
    await h.runtime.submit(config: Config(language: .en)) { _ in }
    let oldId = h.vm.conversationId

    clock.advance(by: 360)
    h.runtime.decide = nil
    h.transcriber.stoppedText = "qué hora es"
    h.runtimeChat.deltas = [.text("Son las 2.")]
    await h.runtime.submit(config: Config(language: .en)) { _ in }

    expect(h.vm.conversationId != oldId, "reloj2: hilo nuevo tras 6 min de espera")
    let content = h.runtimeChat.histories.last?.last?.content ?? ""
    expect(!content.contains("<time_since_last_interaction"),
           "reloj2: sin tag cuando el turno dispara el rollover")
}

// MARK: - 3: a typed turn 20s after a hold shows 20, not 0

@MainActor func testTypedTurnTwentySecondsAfterAHoldShowsTwentyNotZero() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let h = makeInteractionHarness(clock: clock)
    h.transcriber.stoppedText = "hola"
    h.runtimeChat.deltas = [.text("Hola, ¿en qué ayudo?")]
    await h.runtime.submit(config: Config(language: .en)) { _ in }

    clock.advance(by: 20)
    h.vm.draft = "y esto qué es"
    h.vm.send()
    await pumpUntil("reloj3: turno escrito termina") { !h.vm.busy }

    let content = h.vmChat.histories.last?.last?.content ?? ""
    expect(content.contains("<time_since_last_interaction seconds=\"20\">"),
           "reloj3: 20 s desde el hold — capturado antes de pisar el reloj, no 0")
}

// MARK: - 4: the app's first turn never shows a tag

@MainActor func testFirstTurnOfTheAppShowsNoTag() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let h = makeInteractionHarness(clock: clock)
    h.vmChat.replies = [.success([.text("hola")])]
    h.vm.draft = "primera vez"
    h.vm.send()
    await pumpUntil("reloj4: primer turno termina") { !h.vm.busy }

    let content = h.vmChat.histories.last?.last?.content ?? ""
    expect(content.contains("<context"), "reloj4: el bloque de contexto sí se arma")
    expect(!content.contains("<time_since_last_interaction"),
           "reloj4: nada que contar en el primer turno")
}

// MARK: - 5: a job result 30s ago is the clock's source

@MainActor func testJobResultThirtySecondsAgoShowsThirty() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let h = makeInteractionHarness(clock: clock)
    await h.vm.appendAssistant("Terminé de exportar el reporte.")

    clock.advance(by: 30)
    h.transcriber.stoppedText = "qué tal salió"
    h.runtimeChat.deltas = [.text("Bien.")]
    await h.runtime.submit(config: Config(language: .en)) { _ in }

    let content = h.runtimeChat.histories.last?.last?.content ?? ""
    expect(content.contains("<time_since_last_interaction seconds=\"30\">"),
           "reloj5: 30 s desde el resultado del encargo, no desde otra cosa")
}
