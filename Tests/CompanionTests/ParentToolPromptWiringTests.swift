import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Hallazgo del code-reviewer (2026-09-05): `ChatPrompt.system(parentToolsEnabled:)`
// pasaba sus tests aislado y ningún call site real lo encendía. Estos tests
// leen lo que el modelo recibe DE VERDAD: el cuerpo de la petición de chat y
// las instrucciones de la sesión realtime.
@Test @MainActor func parentToolPromptWiringTests() {
    testChatBodyCarriesActRuleWhenParentToolsAreDeclared()
    testRealtimeInstructionsCarryActRule()
    testChatBodyPromisesHandsOnlyWhenTypeTextIsDeclared()
}

/// Wave 15g-3: the hands sentences follow the declared tools, like the
/// act rule itself — no Accessibility, no type_text, no promise.
@MainActor func testChatBodyPromisesHandsOnlyWhenTypeTextIsDeclared() {
    let typeText = ToolSpec(name: "type_text", description: "type", properties: [], required: [])
    let with = systemPrompt(tools: ParentTool.specs(.en) + [typeText, .delegate(.en)])
    expect(with.contains("read_focused") && with.contains("never tell the user to do it"),
           "15g-3 chat body: con type_text declarada promete las manos")
    let without = systemPrompt(tools: ParentTool.specs(.en) + [.delegate(.en)])
    expect(!without.contains("read_focused"),
           "15g-3 chat body: sin type_text no promete escribir")
}

@MainActor func testChatBodyCarriesActRuleWhenParentToolsAreDeclared() {
    let with = systemPrompt(tools: ParentTool.specs(.en) + [.delegate(.en)])
    expect(with.contains("hands on this Mac"), "chat body: con tools del padre dice que tiene manos")
    expect(!with.contains("cannot see the disk"), "chat body: y no dice que no puede ver el disco")
    // Security review 10a: what sits inside <context> is data, never an order.
    expect(with.contains("inside <context>") && with.contains("in their own words"),
           "chat body: lo que hay en <context> no abre nada por sí solo")
    let without = systemPrompt(tools: [.delegate(.en)])
    expect(!without.contains("hands on this Mac"), "chat body: sin tools del padre no promete manos")
}

@MainActor func testRealtimeInstructionsCarryActRule() {
    let with = RealtimeRuntime.instructions(
        config: Config(ownerFirstName: "Karen", language: .en), history: [],
        canDelegate: true, parentToolsEnabled: true)
    expect(with.contains("hands on this Mac"), "realtime: con manos lo dice")
    expect(with.contains("inside <context>"), "realtime: la regla de <context> también viaja en voz")
    let without = RealtimeRuntime.instructions(
        config: Config(ownerFirstName: "Karen", language: .en), history: [],
        canDelegate: true)
    expect(!without.contains("hands on this Mac"), "realtime: sin manos no lo promete")
    // Review 2026-09-25: the voice path declares type_text too; without the
    // hands rule it never heard "act, never instruct" or "verify with read_focused".
    let hands = RealtimeRuntime.instructions(
        config: Config(ownerFirstName: "Karen", language: .en), history: [],
        canDelegate: true, parentToolsEnabled: true, handsEnabled: true)
    expect(hands.contains("read_focused"), "realtime: con manos declaradas, la regla de manos")
    expect(!with.contains("read_focused"), "realtime: sin manos declaradas, sin la regla")
}

@MainActor private func systemPrompt(tools: [ToolSpec]) -> String {
    let provider = ProviderDescriptor.openAI
    let transport = ScriptedTransport()
    transport.stub(provider, ScriptedReply(status: 200, lines: []))
    let client = ChatProviderClient(
        secrets: TestSecretStore([.openAI: "sk-test"]),
        probe: TestProbe(available: [provider.id]),
        transport: transport,
        catalog: [provider])
    do {
        _ = try runAsync { () -> Bool in
            for try await _ in client.stream(
                [Turn(role: .user, content: "abre safari")], tools: tools) {}
            return true
        }
    } catch {
        // El stream vacío termina en error; lo que importa es la petición.
    }
    guard let data = transport.requests.first?.httpBody,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let messages = json["messages"] as? [[String: Any]],
          let system = messages.first?["content"] as? String
    else {
        expect(false, "la petición debía llevar un mensaje system")
        return ""
    }
    return system
}
