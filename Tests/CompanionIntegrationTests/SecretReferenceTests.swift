import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit

// Valores sintéticos: ninguno es un dato real.

private final class RecordingTools: ParentToolExecuting, @unchecked Sendable {
    private(set) var received: [String: String] = [:]
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        received[name] = argumentsJSON
        return ParentToolOutcome(ok: true, output: "typed \(argumentsJSON)", tool: name)
    }
}

@Test @MainActor func aSecretTheOwnerWritesIsTypedButNeverReachesTheModelOrTheThread() async {
    let key = "sk-chatvalueabcdefgh1234"
    let reference = SecretKeeper.shared.seal(key)
    let type = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"\#(reference)"}"#)
    let search = ToolCallRef(id: "w1", name: "web_search", arguments: #"{"query":"\#(reference)"}"#)
    let chat = FakeChatProvider(replies: [.success([.toolCalls([type, search])]), .success([.text("Listo.")])])
    let tools = RecordingTools()
    let vm = primed(chat: chat, parentTools: CompositeParentTools([tools]), config: Config(language: .es))
    vm.draft = "escribe \(key) en el campo"
    vm.send()
    await pumpUntil("secreto: el turno terminó") { !vm.busy && chat.histories.count == 2 }

    // The value opens at the keystrokes (SecretTypingTests), never in the arguments.
    expectEq(tools.received["type_text"], #"{"text":"\#(reference)"}"#, "type_text recibe la referencia")
    expect(tools.received["web_search"] == nil, "una tool que saca datos de la Mac no recibe la referencia abierta")
    let seen = chat.histories.flatMap { $0 }.map(\.content).joined(separator: "\n")
    expect(!seen.contains(key), "el modelo nunca ve el valor: \(seen)")
    expect(seen.contains(reference), "el modelo ve la referencia")
    expect(!vm.messages.contains { $0.text.contains(key) }, "el hilo guardado no tiene el valor")
}

/// Review H1: the voice built its request from the raw words after the thread
/// had sealed them.
@Test @MainActor func aSecretSaidAloudNeverReachesTheModel() async {
    let key = "sk-voicevalueabcdefgh1234"
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "escribe \(key)"
    let chat = ScriptedChat()
    chat.rounds = [[.text("Listo.")]]
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: ScriptedThread())
    await runtime.submit(config: Config(language: .es)) { _ in }
    let seen = chat.histories.flatMap { $0 }.map(\.content).joined(separator: "\n")
    expect(!chat.histories.isEmpty, "voz: el modelo recibió el turno")
    expect(!seen.contains(key), "voz: el modelo nunca ve el valor: \(seen)")
}
