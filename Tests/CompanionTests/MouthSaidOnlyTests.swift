import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Code review 2026-09-25 (LOW-2). The language gate dropped a sentence from
// the voice, but the live bubble (`showStream`) and the assistant turn that
// `act(said:)` hands the next round still carried it: the model read back
// its own leaked reasoning as something it had said.

@Test @MainActor func testTheBubbleAndTheToolRoundOnlyCarryWhatWasSpoken() async {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "por qué no abriste la terminal"
    let chat = ScriptedChat()
    chat.rounds = [
        [
            .text("Listo. We need to answer why. "),
            .toolCalls([ToolCallRef(id: "1", name: "list_apps", arguments: "{}")]),
        ],
        [.text("Ya está.")],
    ]
    let synth = ScriptedSynth()
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.languageRecognizer = FakeRecognizer()
    runtime.parentTools = EchoingParentTools(output: "Terminal, Safari")
    await runtime.submit(config: Config(language: .es)) { _ in }

    expectEq(synth.queue, ["Listo.", "Ya está."], "L2: la voz no dice la fuga")
    expectEq(chat.histories.count, 2, "L2: hubo segunda ronda")
    let said = chat.histories.last?.last { $0.role == .assistant }?.content ?? ""
    expect(!said.contains("We need"), "L2: act(said:) no lleva lo descartado (\(said))")
    expect(said.contains("Listo."), "L2: sí lleva lo dicho")
    expect(!thread.stream.contains("We need"), "L2: la burbuja no muestra lo descartado (\(thread.stream))")
    expectEq(thread.turns.last?.content, "Listo. Ya está.", "L2: el hilo, igual que antes")
}
