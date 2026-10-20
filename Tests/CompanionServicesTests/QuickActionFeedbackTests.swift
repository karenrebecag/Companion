import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Feedback inmediato: an action that succeeded is confirmed at toolDone by the
// earcon and the island receipt. The brain's sentence is spoken only when it
// says something the receipt does not.

private final class QuickOpenTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
    }
}

/// Records what the earcon saw: how many model rounds had started by then.
private final class FeedbackSoundSpy: InterfaceSounding, @unchecked Sendable {
    private let lock = NSLock()
    private let chat: ScriptedChat
    private var cues: [SoundCue] = []
    private var rounds: [Int] = []
    init(chat: ScriptedChat) { self.chat = chat }
    var played: [SoundCue] { lock.withLock { cues } }
    var roundsAtPlay: [Int] { lock.withLock { rounds } }
    func play(_ cue: SoundCue) {
        let started = chat.histories.count
        lock.withLock {
            cues.append(cue)
            rounds.append(started)
        }
    }
}

private final class MarkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [TurnTimeline.Point] = []
    var all: [TurnTimeline.Point] { lock.withLock { points } }
    func record(_ point: TurnTimeline.Point) { lock.withLock { points.append(point) } }
}

private struct OpenTurn {
    let synth: ScriptedSynth
    let sound: FeedbackSoundSpy
    let marks: MarkRecorder
}

/// One hold: the model opens Safari, then answers with `reply`.
@MainActor private func openTurn(reply: String) async -> OpenTurn {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let chat = ScriptedChat()
    let call = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    chat.rounds = [[.toolCalls([call])], [.text(reply)]]
    let synth = ScriptedSynth()
    let sound = FeedbackSoundSpy(chat: chat)
    let marks = MarkRecorder()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: ScriptedThread())
    runtime.parentTools = QuickOpenTools()
    runtime.feedbackSound = sound
    runtime.markTimeline = { point in marks.record(point) }
    let box = AudioStreamBox<SessionEvent>()
    runtime.events = box
    await runtime.submit(config: Config(language: .es)) { _ in }
    box.finish()
    return OpenTurn(synth: synth, sound: sound, marks: marks)
}

@Test @MainActor func testAQuickActionConfirmsAtToolDoneBeforeTheBrainSpeaks() async {
    let turn = await openTurn(reply: "Listo, abrí Safari.")
    expectEq(turn.sound.played, [.confirm], "feedback: un earcon de confirmación")
    expectEq(turn.sound.roundsAtPlay, [1],
             "feedback: suena antes de que arranque la segunda ronda del modelo")
    expect(turn.marks.all.contains(.feedback), "feedback: marca release→feedback")
}

@Test @MainActor func testAnEmptyReplyAfterAQuickActionStaysSilent() async {
    let turn = await openTurn(reply: "")
    expect(turn.synth.queue.isEmpty, "silencio: sin texto del modelo no suena nada (\(turn.synth.queue))")
}

@Test @MainActor func testWhatTheModelSaysAfterAQuickActionIsSpokenAsIs() async {
    let turn = await openTurn(reply: "El clima de hoy es soleado.")
    let spoken = turn.synth.queue.joined(separator: " ")
    expect(spoken.contains("El clima de hoy es soleado."), "dato: la voz dice lo que dice el modelo (\(spoken))")
}
