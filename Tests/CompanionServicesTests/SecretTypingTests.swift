import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Valores sintéticos: ninguno es un dato real.

private func typing(_ text: String) -> ToolCallRef {
    let data = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data()
    return ToolCallRef(id: "c1", name: "type_text", arguments: String(decoding: data, as: UTF8.self))
}

/// The approval binds the reference the owner saw; the value appears only at
/// the keystrokes, so a terminal ticket still matches (review H2).
@Test @MainActor func aReferenceTypedIntoATerminalOpensOnlyAtTheKeystrokes() async {
    let said = SecretKeeper.shared.seal("escribe sk-terminalvalue1234567890")
    let reference = String(said.dropFirst("escribe ".count))
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    let runner = handsRunner(hands, bundle: "com.apple.Terminal")
    let call = typing(reference)
    expect(runner.approval(for: call, said: said) == nil, "terminal: la referencia dicha no pide hoja")
    let out = await runner.execute(name: call.name, argumentsJSON: call.arguments)
    expect(out.ok, "terminal: el ticket coincide y escribe — \(out.output)")
    expectEq(hands.injected.map(\.text), ["sk-terminalvalue1234567890"], "se teclea el valor real")
}

/// Every path passes the composite: a tool that can carry text off the Mac
/// never gets a reference, and what a tool echoes goes back to it.
@Test func theCompositeRefusesReferencesOutsideTypingAndResealsWhatComesBack() async {
    let said = SecretKeeper.shared.seal("clave sk-compositevalue123456789")
    let reference = String(said.dropFirst("clave ".count))
    let echo = EchoTools(echo: "typed sk-compositevalue123456789")
    let tools = CompositeParentTools([echo])
    let search = await tools.execute(name: "web_search", argumentsJSON: #"{"query":"\#(reference)"}"#)
    expect(search.output.hasPrefix("protected_value:"), "web_search con referencia: rechazado")
    expect(echo.calls.isEmpty, "web_search: el runner nunca la recibe")
    let typed = await tools.execute(name: "type_text", argumentsJSON: #"{"text":"\#(reference)"}"#)
    expectEq(typed.output, "typed \(reference)", "la salida vuelve a la referencia")
}

private final class EchoTools: ParentToolExecuting, @unchecked Sendable {
    let echo: String
    private(set) var calls: [String] = []
    init(echo: String) { self.echo = echo }
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        calls.append(name)
        return ParentToolOutcome(ok: true, output: echo, tool: name)
    }
}
